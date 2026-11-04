"""Controlled GitHub runner transport. Credentials come only from GH_TOKEN.
No credentials, activity metadata, or source IDs are printed or included in Pages.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time
import sqlite3
import xml.etree.ElementTree as ET
import zipfile
import urllib.error
import urllib.parse
import urllib.request
from runhub_import import ProtocolError, digest, import_archive, manifest, restore_state, state_archive, unpack, MAX_GPX

RELEASE_TAG = 'runhub-state'

class GitHub:
    def __init__(self, repository, token):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository) or not token:
            raise ProtocolError('Repository/authentication missing')
        self.repository=repository; self.token=token
        self.root='https://api.github.com/repos/'+repository
    def request(self,path,method='GET',data=None,binary=False,url=None):
        target=url or self.root+path
        headers={'Authorization':'Bearer '+self.token,'Accept':'application/octet-stream' if binary else 'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'RunHub-Target-v1'}
        if data is not None: headers['Content-Type']='application/octet-stream'
        req=urllib.request.Request(target,data=data,headers=headers,method=method)
        # GitHub asset redirects use signed URLs. Strip Authorization on cross-origin redirect.
        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,req,fp,code,msg,headers,newurl):
                redirected=super().redirect_request(req,fp,code,msg,headers,newurl)
                if redirected and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
                    redirected.remove_header('Authorization')
                if urllib.parse.urlsplit(newurl).scheme != 'https': raise ProtocolError('Insecure redirect')
                return redirected
        stage = ('asset-upload' if url is not None else
                 'release-enumeration' if path.startswith('/releases?') else
                 'asset-download' if path.startswith('/releases/assets/') else
                 'asset-enumeration' if path.startswith('/releases/') and '/assets?' in path else
                 'workflow-runs' if '/runs?' in path else
                 'workflow-state' if path.startswith('/actions/workflows/') else 'api-request')
        try:
            with urllib.request.build_opener(Redirect()).open(req,timeout=120) as response:
                body=response.read(160*1024*1024+1)
                if len(body)>160*1024*1024: raise ProtocolError('Response too large')
                return body if binary else json.loads(body)
        except urllib.error.HTTPError as error:
            # Codes and fixed stage labels are useful without leaking response body, signed URL or credentials.
            raise ProtocolError(f'GitHub HTTP {error.code} during {stage}') from None
    def release(self):
        matches=[]
        for page in range(1,1001):
            batch=self.request(f'/releases?per_page=100&page={page}')
            if not isinstance(batch,list): raise ProtocolError('Unexpected release enumeration response')
            matches.extend(r for r in batch if r.get('tag_name') == RELEASE_TAG)
            if len(batch)<100:
                if len(matches)!=1: raise ProtocolError('Exactly one RunHub state Release is required')
                if not matches[0].get('draft'): raise ProtocolError('Durable state Release must remain private draft')
                return matches[0]
        raise ProtocolError('Release pagination incomplete')
    def assets(self,release_id):
        result=[]
        for page in range(1,1001):
            batch=self.request(f'/releases/{release_id}/assets?per_page=100&page={page}')
            result.extend(batch)
            if len(batch)<100: return result
        raise ProtocolError('Asset pagination incomplete')
    def upload(self,release,name,data):
        url=release['upload_url'].split('{')[0]+'?'+urllib.parse.urlencode({'name':name})
        if urllib.parse.urlsplit(url).scheme != 'https' or urllib.parse.urlsplit(url).netloc != 'uploads.github.com': raise ProtocolError('Unexpected upload origin')
        result=self.request('',method='POST',data=data,url=url)
        if result.get('name') != name or result.get('size') != len(data): raise ProtocolError('Asset upload acknowledgement mismatch')
        readback=self.request('/releases/assets/'+str(result['id']),binary=True)
        if digest(readback) != digest(data): raise ProtocolError('Durable asset readback mismatch')
        return result
    def assert_sole_writer(self):
        # Both legacy workflows can publish cache-derived older snapshots. They must be disabled.
        for filename in ('run_data_sync.yml','gh-pages.yml'):
            wf=self.request('/actions/workflows/'+filename)
            if wf.get('state') not in ('disabled_manually','disabled_inactivity'):
                raise ProtocolError('Legacy data/page writer still active')
        # Also refuse if a previously dispatched legacy run is still queued/running after disable.
        for filename in ('run_data_sync.yml','gh-pages.yml'):
            for status in ('in_progress','queued','waiting','pending','requested'):
                runs=self.request('/actions/workflows/'+filename+'/runs?status='+status+'&per_page=1')
                if runs.get('total_count',0): raise ProtocolError('Legacy writer has unfinished runs')

def context():
    repo=os.environ['GITHUB_REPOSITORY']; api=GitHub(repo,os.environ['GH_TOKEN'])
    api.assert_sole_writer()
    release=api.release()
    run=os.environ['GITHUB_RUN_ID']; attempt=os.environ.get('GITHUB_RUN_ATTEMPT','1')
    if not run.isdigit() or not attempt.isdigit(): raise ProtocolError('Invalid runner identity')
    return repo,api,release,run+'-'+attempt

def drain_inputs(api, assets, workspace, repository, task, asset_id, sha, privacy_filter):
    """Drain persisted input assets so cancellation of older queued Actions runs loses no work."""
    candidates=[a for a in assets if re.fullmatch(r'runhub-input-[A-Za-z0-9_.:-]{1,160}\.zip',a['name']) and a.get('state','uploaded') == 'uploaded']
    explicit=None
    if task or asset_id or sha:
        if not asset_id.isdigit() or not re.fullmatch(r'[a-f0-9]{64}',sha): raise ProtocolError('Invalid task inputs')
        explicit=next((a for a in candidates if str(a['id']) == asset_id),None)
        if explicit is None or explicit['name'] != 'runhub-input-'+task+'.zip':
            raise ProtocolError('Input asset must match its task and private Release')
    database=workspace/'data.db'; public=workspace/'activities.json'
    with sqlite3.connect(database) as connection:
        table=connection.execute("SELECT 1 FROM sqlite_master WHERE name='runhub_jobs'").fetchone()
        known={r[0] for r in connection.execute('SELECT task_id FROM runhub_jobs')} if table else set()
    connection.close()
    # Process caller first to validate its explicit hash. Other valid inputs are independent queued work.
    ordered=([explicit] if explicit else [])+[a for a in sorted(candidates,key=lambda a:(a['created_at'],a['id'])) if explicit is None or a['id'] != explicit['id']]
    processed=0
    for metadata in ordered:
        expected_task=metadata['name'][len('runhub-input-'):-len('.zip')]
        if metadata is not explicit and expected_task in known: continue
        archive=api.request('/releases/assets/'+str(metadata['id']),binary=True)
        try:
            files=unpack(archive,['request.json','workout.gpx'],MAX_GPX+1024*1024)
            request=json.loads(files['request.json'])
            expected_hash=sha if metadata is explicit else request.get('sha256','')
            if request.get('taskID') != expected_task: raise ProtocolError('Queued task identity mismatch')
            import_archive(database,public,archive,repository,expected_task,expected_hash,privacy_filter)
            known.add(expected_task);processed+=1
        except (ProtocolError, ValueError, KeyError, ET.ParseError, zipfile.BadZipFile):
            if metadata is explicit: raise
            # Malformed unrelated input remains retained for review; it cannot block independent tasks.
            continue
    return processed

def prepare(args):
    repo,api,release,suffix=context()
    assets=api.assets(release['id'])
    snapshots=[a for a in assets if re.fullmatch(r'runhub-state-[A-Za-z0-9-]+\.zip',a['name'])]
    if not snapshots: raise ProtocolError('Verified bootstrap state missing')
    latest=max(snapshots,key=lambda a:(a['created_at'],a['id']))
    workspace=Path('.runhub'); workspace.mkdir(exist_ok=True)
    state_metadata=restore_state(api.request('/releases/assets/'+str(latest['id']),binary=True),workspace,repo)
    if state_metadata.get('seedCacheKey'):
        # Migration must not lose a legacy run completed between cache capture and writer shutdown.
        latest_legacy=api.request('/actions/workflows/run_data_sync.yml/runs?status=success&per_page=1')
        runs=latest_legacy.get('workflow_runs',[])
        seed_run=state_metadata['seedCacheKey'].rsplit('-',1)[-1]
        if not runs or str(runs[0]['id']) != seed_run:
            raise ProtocolError('A newer legacy sync exists; bootstrap snapshot is stale')
    task=os.environ.get('TASK_ID',''); asset_id=os.environ.get('RELEASE_ASSET_ID',''); sha=os.environ.get('GPX_SHA256','')
    # Reuse repository's established route privacy filter on *new* public records only.
    from polyline_processor import filter_out
    drain_inputs(api, assets, workspace, repo, task, asset_id, sha, filter_out)
    # Persist all results before any website build/deployment; a failed build can safely retry.
    archive=state_archive(workspace/'data.db',workspace/'activities.json',repo,assets_path=workspace/'generated-assets')
    saved=api.upload(release,'runhub-state-'+suffix+'.zip',archive)
    shutil.copyfile(workspace/'activities.json','src/static/activities.json')
    for asset in (workspace/'generated-assets').glob('*.svg'):
        shutil.copyfile(asset,Path('assets')/asset.name)
    # Marker contains only a state digest, never source identities or private job IDs.
    marker={'version':1,'stateSHA256':digest(archive),'activitiesSHA256':digest((workspace/'activities.json').read_bytes())}
    Path('public/runhub/v1').mkdir(parents=True,exist_ok=True)
    Path('public/runhub/v1/publication.json').write_text(json.dumps(marker))
    (workspace/'publication.json').write_text(json.dumps(marker))
    (workspace/'prepared.json').write_text(json.dumps({'stateAssetID':saved['id'],'stateSHA256':digest(archive),'suffix':suffix}))
    print('Validated state durably stored; website input prepared.')

def bootstrap(args):
    repo=os.environ['GITHUB_REPOSITORY']; api=GitHub(repo,os.environ['GH_TOKEN'])
    key=os.environ['SEED_CACHE_KEY']
    if not re.fullmatch(r'track_data-[a-f0-9]{40}-[0-9]+',key):
        raise ProtocolError('Exact legacy cache key required')
    if os.environ.get('SEED_CACHE_HIT') != 'true': raise ProtocolError('Exact legacy cache not restored')
    release=api.release()
    if any(a['name'].startswith('runhub-state-') and a['name'].endswith('.zip') for a in api.assets(release['id'])):
        raise ProtocolError('Durable state already seeded; refusing replacement')
    archive=state_archive('run_page/data.db','src/static/activities.json',repo,seed_cache_key=key,assets_path='assets')
    suffix=os.environ['GITHUB_RUN_ID']+'-'+os.environ.get('GITHUB_RUN_ATTEMPT','1')
    api.upload(release,'runhub-state-bootstrap-'+suffix+'.zip',archive)
    print('Exact cached baseline validated and preserved in private durable snapshot; legacy workflows unchanged.')

def verify_publication(base, expected, deadline_seconds=180, interval_seconds=5, request_timeout=15):
    """Verify the same marker, Vite manifest and actual activity bytes within one bounded attempt loop."""
    deadline=time.monotonic()+deadline_seconds
    attempt=0
    last_failure='No complete readback'
    def fetch(path, limit):
        remaining=deadline-time.monotonic()
        if remaining<=0: raise ProtocolError('Publication readback deadline reached')
        query=urllib.parse.urlencode({'state':expected['stateSHA256'],'attempt':attempt})
        request=urllib.request.Request(base+path+'?'+query,headers={
            'Cache-Control':'no-cache, no-store, max-age=0','Pragma':'no-cache','Accept':'application/json','User-Agent':'RunHub-Target-v1'})
        with urllib.request.urlopen(request,timeout=min(request_timeout,remaining)) as response:
            chunks=[];size=0
            read=getattr(response,'read1',response.read)
            while True:
                if time.monotonic()>=deadline: raise ProtocolError('Publication readback deadline reached')
                chunk=read(min(64*1024,limit-size+1))
                if not chunk: break
                size+=len(chunk)
                if size>limit: raise ProtocolError('Published response exceeds size limit')
                chunks.append(chunk)
            return b''.join(chunks)
    while time.monotonic()<deadline:
        attempt+=1
        try:
            actual=json.loads(fetch('runhub/v1/publication.json',64*1024))
            if actual!=expected: raise ProtocolError('Published generation mismatch')
            # Always reread all three pieces together; do not mix a successful old attempt with a later one.
            vite=json.loads(fetch('.vite/manifest.json',10*1024*1024))
            if not isinstance(vite,dict): raise ProtocolError('Published Vite manifest invalid')
            candidates=[v.get('file') for k,v in vite.items() if isinstance(k,str) and k.endswith('src/static/activities.json') and isinstance(v,dict)]
            if len(candidates)!=1 or not isinstance(candidates[0],str): raise ProtocolError('Published activities asset cannot be resolved')
            asset=candidates[0];parsed=urllib.parse.urlsplit(asset)
            if not asset.startswith('assets/') or '..' in asset or parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
                raise ProtocolError('Published activities asset cannot be resolved')
            public=fetch(asset,128*1024*1024)
            if digest(public)!=expected['activitiesSHA256']: raise ProtocolError('Published activities content mismatch')
            if time.monotonic()>=deadline: raise ProtocolError('Publication readback deadline reached')
            return
        except (ProtocolError,urllib.error.URLError,TimeoutError,OSError,ValueError,KeyError,TypeError) as error:
            # Only protocol errors have fixed safe text. Network/parser details can contain URLs/body fragments.
            last_failure=str(error) if isinstance(error,ProtocolError) else type(error).__name__
        remaining=deadline-time.monotonic()
        if remaining<=0: break
        time.sleep(min(interval_seconds,remaining))
    raise ProtocolError('Published content did not converge before deadline: '+last_failure)

def publish(args):
    repo,api,release,suffix=context()
    base=os.environ['PAGE_URL'].rstrip('/')+'/'
    parsed=urllib.parse.urlsplit(base)
    if parsed.scheme != 'https' or parsed.username or parsed.password: raise ProtocolError('Invalid Pages URL')
    expected=json.loads(Path('.runhub/publication.json').read_bytes())
    # CDN propagation can lag the deploy action. Keep this exact durable generation fixed across retries.
    verify_publication(base, expected)
    private=manifest('.runhub/data.db','.runhub/activities.json',repo,published=True)
    private['publication']=expected
    api.upload(release,'runhub-manifest-'+suffix+'.json',json.dumps(private,separators=(',',':')).encode())
    print('Published data read back; private terminal receipts durably stored.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('command',choices=['prepare','publish','bootstrap']);args=parser.parse_args()
    try:
        {'prepare':prepare,'publish':publish,'bootstrap':bootstrap}[args.command](args)
    except Exception as error:
        # HTTP errors and parser errors can contain credentials/health content: expose only category.
        reason = str(error) if isinstance(error, ProtocolError) else type(error).__name__
        raise SystemExit('RunHub target stopped safely: '+reason) from None
