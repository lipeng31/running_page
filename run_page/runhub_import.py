"""RunHub v1 append-only adapter for the existing running_page SQLite/JSON schema.

Does not invoke Generator.load/update_or_create_activity: both mutate legacy rows.
All source IDs/receipts stay in the authenticated draft Release state, not Pages.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import datetime as dt
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sqlite3
import xml.etree.ElementTree as ET
import zipfile
from zoneinfo import ZoneInfo

UTC = dt.timezone.utc
EPOCH = dt.datetime(1970, 1, 1)
RPS = 'https://github.com/lipeng31/running_page/xmlschemas/WorkoutExtension/v1'
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_GPX = 32 * 1024 * 1024
GENERATED_SVG = re.compile(r'(?:github(?:_[0-9]{4})?|grid|circular|year_[0-9]{4}|year_summary(?:_[0-9]{4})?|mol(?:_[a-z]+)?)\.svg')

class ProtocolError(ValueError):
    pass

def digest(data):
    return hashlib.sha256(data).hexdigest()

def iso(value):
    return value.astimezone(UTC).isoformat(timespec='seconds').replace('+00:00', 'Z')

def date(value):
    parsed = dt.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    return parsed.replace(tzinfo=UTC) if parsed.tzinfo is None else parsed.astimezone(UTC)

def number(value, *, minimum=0):
    result = float(value)
    if not math.isfinite(result) or result < minimum:
        raise ProtocolError('Invalid numeric value')
    return result

def seconds(value):
    # SQLAlchemy's SQLite Interval representation is an epoch-relative DATETIME.
    if isinstance(value, (int, float)):
        return number(value, minimum=0.000001)
    return number((dt.datetime.fromisoformat(value) - EPOCH).total_seconds(), minimum=0.000001)

def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}', value):
        raise ProtocolError('Invalid opaque identifier')
    return value

def pack_files(files):
    result = io.BytesIO()
    with zipfile.ZipFile(result, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    return result.getvalue()

def unpack(data, names, max_size=MAX_ARCHIVE):
    if len(data) > max_size:
        raise ProtocolError('Archive exceeds limit')
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        infos = z.infolist()
        if len(infos) != len(names) or {i.filename for i in infos} != set(names):
            raise ProtocolError('Archive members do not match protocol')
        if any(i.flag_bits & 1 for i in infos) or sum(i.file_size for i in infos) > max_size:
            raise ProtocolError('Archive exceeds limits or is encrypted')
        return {i.filename: z.read(i) for i in infos}

def _connect(path):
    if not Path(path).is_file():
        raise ProtocolError('Existing database required; refusing empty baseline')
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
        raise ProtocolError('Database integrity failure')
    fields = {r['name'] for r in db.execute('PRAGMA table_info(activities)')}
    required = {'run_id', 'name', 'distance', 'moving_time', 'elapsed_time', 'type', 'start_date', 'start_date_local', 'summary_polyline'}
    if not required <= fields:
        raise ProtocolError('Unsupported activities schema')
    return db

@contextmanager
def connect(path):
    db = _connect(path)
    try:
        with db:
            yield db
    finally:
        db.close()

def row_workout(row, source, source_id):
    return {'id':source_id,'source':source,'startedAt':iso(date(row['start_date'])),'activityType':'running' if (row['type'] or '').lower() in ('run','running') else (row['type'] or 'unknown').lower(),'duration':seconds(row['moving_time']),'distanceMeters':number(row['distance']) if row['distance'] is not None else None}

def ensure_schema(db):
    db.execute('CREATE TABLE IF NOT EXISTS runhub_sources (source TEXT NOT NULL, source_id TEXT NOT NULL, activity_id INTEGER NOT NULL, workout_json TEXT NOT NULL, content_sha256 TEXT NOT NULL, PRIMARY KEY(source, source_id), FOREIGN KEY(activity_id) REFERENCES activities(run_id))')
    db.execute('CREATE TABLE IF NOT EXISTS runhub_jobs (task_id TEXT PRIMARY KEY, source TEXT NOT NULL, source_id TEXT NOT NULL, content_sha256 TEXT NOT NULL, outcome TEXT NOT NULL, activity_id INTEGER, created_at TEXT NOT NULL)')

def baseline(db, public):
    if not isinstance(public, list) or not public:
        raise ProtocolError('Nonempty published baseline required')
    public_ids = [int(r['run_id']) for r in public]
    rows = list(db.execute('SELECT * FROM activities'))
    # Existing generator excludes distance <= 0.1; preserve this rendering boundary.
    expected = {r['run_id'] for r in rows if r['distance'] is not None and float(r['distance']) > 0.1}
    if len(set(public_ids)) != len(public_ids) or set(public_ids) != expected:
        raise ProtocolError('Database and published activity identities disagree')
    # Do not silently accept a newer JSON and older DB with coincidentally equal counts.
    by_id = {r['run_id']: r for r in rows}
    for row in public:
        stored = by_id[int(row['run_id'])]
        if abs(float(stored['distance']) - float(row['distance'])) > 0.01 or date(stored['start_date']) != date(row['start_date']):
            raise ProtocolError('Database and published activity summaries disagree')
    return rows

def parse_gpx(data, expected_id):
    if len(data) > MAX_GPX or b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ProtocolError('Unsupported XML')
    root = ET.fromstring(data)
    if root.tag.split('}')[-1] != 'gpx':
        raise ProtocolError('GPX root required')
    ext = root.find('./{*}extensions')
    if ext is None:
        raise ProtocolError('Source summary required')
    def field(name, required=True):
        node = ext.find('{'+RPS+'}'+name)
        if node is None or node.text is None:
            if required:
                raise ProtocolError('Required source summary missing')
            return None
        return node.text
    if field('workout_id') != expected_id:
        raise ProtocolError('GPX identity mismatch')
    start = date(field('start_time'))
    end = date(field('end_time'))
    duration = number(field('moving_time'), minimum=0.000001)
    distance = number(field('distance'), minimum=0.100001)
    elapsed = number(field('elapsed_time'), minimum=duration)
    if end < start or abs((end-start).total_seconds()-elapsed) > 2:
        raise ProtocolError('Inconsistent elapsed time')
    if start < dt.datetime(1900, 1, 1, tzinfo=UTC) or start > dt.datetime.now(UTC) + dt.timedelta(minutes=5):
        raise ProtocolError('Unsupported workout date')
    tracks = root.findall('./{*}trk')
    if len(tracks) != 1 or (tracks[0].findtext('./{*}type') or '').lower() not in ('run','running'):
        raise ProtocolError('Only running GPX supported')
    points = []
    for p in tracks[0].findall('./{*}trkseg/{*}trkpt'):
        lat, lon = number(p.attrib['lat'], minimum=-90), number(p.attrib['lon'], minimum=-180)
        if lat > 90 or lon > 180:
            raise ProtocolError('Invalid coordinate')
        points.append((lat, lon))
    hr = field('average_hr', False)
    elevation = field('elevation_gain', False)
    return {'id':expected_id, 'source':'appleHealth', 'startedAt':iso(start), 'activityType':'running', 'duration':duration, 'distanceMeters':distance}, {
        'name':tracks[0].findtext('./{*}name') or 'Run', 'distance':distance,
        'moving_time':str(EPOCH+dt.timedelta(seconds=duration)), 'elapsed_time':str(EPOCH+dt.timedelta(seconds=elapsed)),
        'type':'Run', 'subtype':'Run' if points else 'Indoor',
        'start_date':str(start), 'start_date_local':start.astimezone(ZoneInfo('Asia/Shanghai')).strftime('%Y-%m-%d %H:%M:%S'),
        'location_country':'', 'summary_polyline':encode_polyline(points), 'source_id':expected_id,
        'average_heartrate':number(hr) if hr is not None else None,
        'average_speed':distance/duration, 'elevation_gain':number(elevation) if elevation is not None else None,
    }

def encode_polyline(points):
    last = [0, 0]
    out = []
    for point in points:
        for i, value in enumerate(point):
            current = math.floor(value * 1e5 + 0.5)
            diff = current-last[i]; last[i] = current
            bits = ~(diff << 1) if diff < 0 else diff << 1
            while bits >= 32:
                out.append(chr((32 | (bits & 31))+63)); bits >>= 5
            out.append(chr(bits+63))
    return ''.join(out)

def public_record(row, privacy_filter):
    keys = ['run_id','name','distance','type','subtype','start_date','start_date_local','location_country','average_heartrate','average_speed','elevation_gain']
    out = {key:row.get(key) for key in keys}
    out['moving_time'] = str(dt.timedelta(seconds=seconds(row['moving_time'])))
    out['summary_polyline'] = privacy_filter(row['summary_polyline']) or ''
    return out

def import_archive(db_path, public_path, archive, repository, task_id, gpx_sha256, privacy_filter):
    identifier(task_id)
    files = unpack(archive, ['request.json','workout.gpx'], MAX_GPX+1024*1024)
    request = json.loads(files['request.json'])
    if request.get('version') != 1 or request.get('repository','').lower() != repository.lower() or request.get('taskID') != task_id or request.get('source') != 'appleHealth':
        raise ProtocolError('Request binding mismatch')
    source_id = identifier(request.get('sourceID'))
    actual_hash = digest(files['workout.gpx'])
    if actual_hash != gpx_sha256 or request.get('sha256') != actual_hash:
        raise ProtocolError('Content hash mismatch')
    workout, row = parse_gpx(files['workout.gpx'], source_id)
    public = json.loads(Path(public_path).read_bytes())
    with connect(db_path) as db:
        old_rows = baseline(db, public)
        db.execute('BEGIN IMMEDIATE')
        ensure_schema(db)
        old_job = db.execute('SELECT * FROM runhub_jobs WHERE task_id=?',(task_id,)).fetchone()
        if old_job:
            if (old_job['source'], old_job['source_id'], old_job['content_sha256']) != ('appleHealth', source_id, actual_hash):
                raise ProtocolError('Task ID already bound to another input')
            return dict(old_job)
        source = db.execute('SELECT * FROM runhub_sources WHERE source=? AND source_id=?',('appleHealth',source_id)).fetchone()
        fields = {r['name'] for r in db.execute('PRAGMA table_info(activities)')}
        exact = list(db.execute('SELECT run_id FROM activities WHERE source_id=?',(source_id,))) if 'source_id' in fields else []
        outcome, activity_id = 'conflict', None
        if source:
            if source['content_sha256'] == actual_hash:
                outcome, activity_id = 'existing', source['activity_id']
        elif len(exact) == 1:
            outcome, activity_id = 'existing', exact[0]['run_id']
            workout = row_workout(next(r for r in old_rows if r['run_id'] == activity_id), 'appleHealth', source_id)
        elif not exact:
            # Conservative cross-source detection; do not rewrite or automatically claim a fuzzy match.
            candidates = [r for r in old_rows if abs((date(r['start_date'])-date(workout['startedAt'])).total_seconds()) <= 300]
            if not candidates:
                # Stable 52-bit ID preserves exact JavaScript integer representation, with collision refusal.
                activity_id = int(digest(('appleHealth:'+source_id).encode())[:13],16)
                if db.execute('SELECT 1 FROM activities WHERE run_id=?',(activity_id,)).fetchone():
                    activity_id = None
                else:
                    row['run_id'] = activity_id
                    insert = {k:v for k,v in row.items() if k in fields}
                    sql = 'INSERT INTO activities ('+','.join(insert)+') VALUES ('+','.join('?' for _ in insert)+')'
                    db.execute(sql, tuple(insert.values()))
                    outcome = 'added'
        if outcome in ('added','existing') and not source:
            db.execute('INSERT INTO runhub_sources VALUES (?,?,?,?,?)',('appleHealth',source_id,activity_id,json.dumps(workout,sort_keys=True),actual_hash))
        db.execute('INSERT INTO runhub_jobs VALUES (?,?,?,?,?,?,?)',(task_id,'appleHealth',source_id,actual_hash,outcome,activity_id,iso(dt.datetime.now(UTC))))
        # Verify byte-equivalent SQL values for every preexisting activity before committing.
        after = {r['run_id']:tuple(r) for r in db.execute('SELECT * FROM activities')}
        if any(after[r['run_id']] != tuple(r) for r in old_rows):
            raise ProtocolError('Append-only invariant violated')
        if outcome == 'added':
            public.append(public_record(row, privacy_filter))
            public.sort(key=lambda r:(r['start_date_local'],r['run_id']))
        result = dict(db.execute('SELECT * FROM runhub_jobs WHERE task_id=?',(task_id,)).fetchone())
    # All changes occur in disposable runner working files; durability only after a validated snapshot upload.
    Path(public_path).write_text(json.dumps(public,separators=(',',':')),encoding='utf-8')
    return result

def manifest(db_path, public_path, repository, published=False):
    public = json.loads(Path(public_path).read_bytes())
    with connect(db_path) as db:
        rows = baseline(db,public)
        tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        mappings = list(db.execute('SELECT * FROM runhub_sources')) if 'runhub_sources' in tables else []
        mapped_ids = {r['activity_id'] for r in mappings}
        records = []
        for r in rows:
            if r['run_id'] in mapped_ids:
                continue
            source_id = r['source_id'] if 'source_id' in r.keys() else None
            records.append({'workout':row_workout(r,'appleHealth' if source_id else 'running_page',source_id or str(r['run_id'])),'activityID':str(r['run_id'])})
        row_ids = {r['run_id'] for r in rows}
        for r in mappings:
            workout = json.loads(r['workout_json'])
            if r['activity_id'] not in row_ids or workout.get('source') != r['source'] or workout.get('id') != r['source_id']:
                raise ProtocolError('Orphaned or inconsistent source receipt')
            actual = row_workout(next(a for a in rows if a['run_id'] == r['activity_id']),r['source'],r['source_id'])
            records.append({'workout':actual,'activityID':str(r['activity_id'])})
        identities = [(r['workout']['source'],r['workout']['id']) for r in records]
        if len(set(identities)) != len(identities):
            raise ProtocolError('Duplicate exact source identities in baseline')
        valid_receipts = {(r['workout']['source'],r['workout']['id'],r['activityID']) for r in records}
        if 'runhub_jobs' in tables:
            for job in db.execute('SELECT * FROM runhub_jobs'):
                if job['outcome'] not in ('added','existing','conflict'):
                    raise ProtocolError('Invalid persisted job outcome')
                if job['outcome'] in ('added','existing') and (job['source'],job['source_id'],str(job['activity_id'])) not in valid_receipts:
                    raise ProtocolError('Job receipt is not backed by an activity')
        jobs = [{'taskID':r['task_id'],'source':r['source'],'sourceID':r['source_id'],'outcome':r['outcome'],'activityID':str(r['activity_id']) if r['activity_id'] is not None else None,'published':published and r['outcome'] in ('added','existing')} for r in db.execute('SELECT * FROM runhub_jobs')] if 'runhub_jobs' in tables else []
    start = min([date(r['workout']['startedAt']) for r in records]+[dt.datetime(1900,1,1,tzinfo=UTC)])
    return {'version':1,'repository':repository,'appendOnly':True,'serializedWrites':True,'durableStorage':True,'complete':True,'coverageStart':iso(start),'coverageEnd':iso(dt.datetime.now(UTC)+dt.timedelta(minutes=5)),'records':records,'jobs':jobs}

def state_archive(db_path, public_path, repository, seed_cache_key=None, assets_path=None):
    # Constructing a state must pass full schema/inventory validation before upload.
    manifest(db_path,public_path,repository)
    database, public = Path(db_path).read_bytes(), Path(public_path).read_bytes()
    generated = {}
    if assets_path is not None:
        for path in sorted(Path(assets_path).glob('*.svg')):
            if GENERATED_SVG.fullmatch(path.name):
                if path.is_symlink(): raise ProtocolError('Generated asset symlinks are unsupported')
                generated[path.name] = path.read_bytes()
    metadata = {'version':1,'repository':repository,'databaseSHA256':digest(database),'activitiesSHA256':digest(public),'generatedAssets':{name:digest(data) for name,data in generated.items()}}
    if seed_cache_key is not None: metadata['seedCacheKey'] = seed_cache_key
    files = {'data.db':database,'activities.json':public,'metadata.json':json.dumps(metadata,sort_keys=True).encode()}
    files.update({'generated-assets/'+name:data for name,data in generated.items()})
    return pack_files(files)

def restore_state(data, directory, repository):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = set(archive.namelist())
    required = {'data.db','activities.json','metadata.json'}
    extras = names-required
    if any(not name.startswith('generated-assets/') or not GENERATED_SVG.fullmatch(name.removeprefix('generated-assets/')) for name in extras):
        raise ProtocolError('Unexpected snapshot asset')
    files = unpack(data,required|extras)
    metadata = json.loads(files['metadata.json'])
    generated = metadata.get('generatedAssets',{})
    if not isinstance(generated,dict) or set(generated) != {name.removeprefix('generated-assets/') for name in extras}:
        raise ProtocolError('Generated asset inventory mismatch')
    if any(digest(files['generated-assets/'+name]) != sha for name,sha in generated.items()):
        raise ProtocolError('Generated asset integrity mismatch')
    if metadata.get('version') != 1 or metadata.get('repository','').lower() != repository.lower() or metadata.get('databaseSHA256') != digest(files['data.db']) or metadata.get('activitiesSHA256') != digest(files['activities.json']):
        raise ProtocolError('Snapshot identity/integrity mismatch')
    directory = Path(directory); directory.mkdir(parents=True,exist_ok=True)
    for name in ('data.db','activities.json'):
        (directory/name).write_bytes(files[name])
    if generated:
        (directory/'generated-assets').mkdir(exist_ok=True)
        for name in generated:
            (directory/'generated-assets'/name).write_bytes(files['generated-assets/'+name])
    manifest(directory/'data.db',directory/'activities.json',repository)
    return metadata

if __name__ == '__main__':
    p=argparse.ArgumentParser(description='Package verified existing baseline for private RunHub draft Release bootstrap')
    p.add_argument('--db',required=True);p.add_argument('--activities',required=True);p.add_argument('--repository',required=True);p.add_argument('--output',required=True);p.add_argument('--assets')
    args=p.parse_args()
    Path(args.output).write_bytes(state_archive(args.db,args.activities,args.repository,assets_path=args.assets))
    print('Validated bootstrap snapshot written; no network writes performed.')
