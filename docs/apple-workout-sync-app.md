# Apple Workout Sync App

`ios/RunningPageSync` is a self-use iOS companion app for syncing Apple Watch runs recorded with Apple Workout into this running_page repository without Strava.

The app reads Apple Health workouts, routes, metrics, metadata, and events through HealthKit. It exports the selected workout as an extended GPX file, uploads it to `GPX_OUT/`, then triggers `run_data_sync.yml` with `run_type=only_gpx`.

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
- Standard GPX fields contain the route, timestamps, and elevation.
- Garmin-compatible track-point extensions contain heart rate so the existing running_page importer can calculate and display average heart rate.
- Running Page Sync extensions preserve HealthKit summary statistics and raw samples for heart rate, energy, distance, steps, flights climbed, running power, speed, ground contact time, stride length, vertical oscillation, physical effort, recovery heart rate, VO2 max, and workout effort score when those values exist.
- Workout metadata, source and device information, pause/lap events, and Core Location accuracy, speed, and course values are also retained.
- HealthKit only returns data types that the user authorizes and that Apple Workout recorded for the selected run.
- Sync Again updates the existing GPX file instead of creating a duplicate activity.
- If the selected workout has no route points, the app shows an error and does not upload anything.
- Running on a simulator is not useful because HealthKit workout data and route authorization must be tested on a real iPhone.
