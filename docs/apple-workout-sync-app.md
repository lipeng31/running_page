# Apple Workout Sync App

`ios/RunningPageSync` is a self-use iOS companion app for syncing Apple Watch runs recorded with Apple Workout into this running_page repository without Strava.

The app reads Apple Health workouts and workout routes through HealthKit, exports the selected route as GPX, uploads it to `GPX_OUT/`, then triggers `run_data_sync.yml` with `run_type=only_gpx`.

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
4. Tap Sync on a workout, or tap Sync Latest Unsynced Run.
5. The app uploads a GPX file to `GPX_OUT/`.
6. The app triggers GitHub Actions with `run_type=only_gpx`.
7. GitHub Actions imports the GPX, updates `src/static/activities.json`, regenerates SVG assets, and publishes the running page.

## Notes

- The first version is manual. It does not run in the background after every workout.
- Route, time, distance, and elevation are exported through GPX.
- Heart rate is not included in the first version.
- If the selected workout has no route points, the app shows an error and does not upload anything.
- Running on a simulator is not useful because HealthKit workout data and route authorization must be tested on a real iPhone.
