# Apple Workout Sync App

`ios/RunningPageSync` is a self-use iOS companion app for syncing Apple Watch runs recorded with Apple Workout into this running_page repository without Strava.

The app reads Apple Health workouts, routes, metrics, metadata, and events through HealthKit. It exports workouts as extended GPX files, packages each sync batch into one ZIP archive, uploads that archive to a private draft GitHub Release, then triggers `run_data_sync.yml` with `run_type=only_gpx` and the temporary Release asset ID. The workflow deletes the asset after a successful import, so raw routes never enter Git history.

## Requirements

- Xcode 26 or newer.
- An iPhone with Apple Health workout data.
- A GitHub fine-grained personal access token for this repository.
- `xcodegen` installed locally. This machine already has it at `/opt/homebrew/bin/xcodegen`.

## GitHub Token

Create a fine-grained personal access token scoped to this repository.

Required repository permissions:

- Contents: Read and write.
- Actions: Read and write.

The app stores the token in the iOS Keychain. The token is never committed to this repository.

## Build and Install

Generate the Xcode project:

```bash
cd ios/RunningPageSync
xcodegen generate
open RunningPageSync.xcodeproj
```

In Xcode:

1. Select the `RunningPageSync` target.
2. Open Signing & Capabilities.
3. Select your personal development team.
4. Connect your iPhone.
5. Build and run on the device.
6. Approve Health access when prompted.

The command-line build can verify source compilation without signing:

```bash
cd ios/RunningPageSync
xcodebuild -project RunningPageSync.xcodeproj -scheme RunningPageSync -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## App Setup

Open Settings in the app and fill in:

- Owner: your GitHub username or organization.
- Repository: the repository name.
- Branch: `master` unless you changed the default branch.
- Workflow file: `run_data_sync.yml`.
- Token: your fine-grained GitHub personal access token.

Tap Save.

## Sync Flow

1. Open the app after recording a run with Apple Workout.
2. Tap Authorize Health Access if needed.
3. Tap Reload Workouts.
4. Tap Sync on one workout, or tap Sync All Missing Runs.
5. For batch sync, the app reads the published activity inventory from GitHub Pages and compares it with all running workouts in HealthKit.
6. The app packages the missing GPX files into one ZIP and uploads it to the private draft `RunningPage Sync Inbox` Release.
7. The app triggers GitHub Actions once with `run_type=only_gpx` and the temporary Release asset ID.
8. GitHub Actions downloads and validates the archive, imports its GPX files, updates `src/static/activities.json`, regenerates SVG assets, and publishes the running page.
9. After a successful import, GitHub Actions deletes the temporary Release asset. GPX files are neither committed nor retained in the Action cache.

## Repair Historical Routes

Use **Repair All Routes** when older published routes have lost their beginning
or ending. The app re-reads every route still available in HealthKit, uploads
small private batches, and starts one rebuild Action containing all batches.
The importer matches HealthKit workouts to legacy provider records by start
time and distance, so it replaces the damaged route without changing the old
activity ID or creating a duplicate. Workouts for which HealthKit has no route
are left unchanged.

Keep the app open while it reads and uploads the batches. After the rebuild is
triggered, the app can be closed while GitHub Actions completes the import and
deployment.

## Notes

- The first version is manual. It does not run in the background after every workout.
- Standard GPX fields contain the route, timestamps, and elevation.
- Garmin-compatible track-point extensions contain heart rate so the existing running_page importer can calculate and display average heart rate.
- Running Page Sync extensions preserve HealthKit summary statistics and raw samples for heart rate, energy, distance, steps, flights climbed, running power, speed, ground contact time, stride length, vertical oscillation, physical effort, recovery heart rate, VO2 max, and workout effort score when those values exist.
- Workout metadata, source and device information, pause/lap events, and Core Location accuracy, speed, and course values are also retained.
- HealthKit only returns data types that the user authorizes and that Apple Workout recorded for the selected run.
- Sync Again uploads another temporary archive with the same deterministic GPX filename. The Action cache records content hashes, so unchanged data is skipped and changed workout data is imported again.
- The draft inbox Release remains unpublished and normally contains no assets between successful syncs. A failed workflow intentionally leaves its asset available for diagnosis or retry.
- Workouts without route points are exported with their duration, distance, metrics, metadata, and events. This supports indoor runs when Apple Workout did not record a GPS route.
- Batch matching requires the repository's GitHub Pages site and Vite manifest to be publicly readable.
- Historical repair does not simplify GPX points and never invents a route for an indoor workout.
- Running on a simulator is not useful because HealthKit workout data and route authorization must be tested on a real iPhone.
