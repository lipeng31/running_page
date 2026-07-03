# Apple Workout Sync Design

## Goal

Build a self-use iOS companion app that reads Apple Watch workouts from Apple Health, exports workout routes as GPX, uploads them to this repository, and triggers the existing running_page data sync workflow without using Strava.

## Scope

The first version is a manual sync tool. The user opens the app after a run, selects a workout or taps a latest-workout action, and starts sync. The app does not attempt fully automatic background sync because iOS background execution is not reliable enough for the first implementation.

The repository will continue to treat GPX as the interchange format. Existing `run_page/gpx_sync.py`, SQLite generation, `src/static/activities.json`, SVG generation, and GitHub Pages deployment remain the authoritative downstream pipeline.

## Architecture

Create an independent iOS app under `ios/RunningPageSync/`. It will use SwiftUI for UI, HealthKit for workout and route access, Security/Keychain for GitHub token storage, and URLSession for GitHub REST API calls.

The repository workflow will be updated so `workflow_dispatch` can accept a `run_type` input. The iOS app will dispatch `run_type=only_gpx` after uploading a GPX file into `GPX_OUT/`.

## Data Flow

1. Apple Watch records a run through Apple Workout.
2. The app requests HealthKit read authorization for workouts and workout routes.
3. The app fetches recent running workouts from HealthKit.
4. For a selected workout, the app fetches associated `HKWorkoutRoute` samples and reads all route points with `HKWorkoutRouteQuery`.
5. The app serializes the route points into a GPX 1.1 document.
6. The app uploads the GPX to GitHub using the Contents API at `GPX_OUT/<timestamp>-apple-workout.gpx`.
7. The app triggers `.github/workflows/run_data_sync.yml` with `run_type=only_gpx`.
8. GitHub Actions runs the existing GPX sync path and republishes the running page.

## iOS App Features

The first version includes:

- Health authorization button and status display.
- Recent running workout list with date, distance, duration, and route availability.
- Settings form for GitHub owner, repository, branch, workflow file name, and personal access token.
- Manual sync action for a selected workout.
- Basic sync status: preparing GPX, uploading GPX, triggering workflow, complete, or failure.
- Local synced-workout tracking using workout UUIDs so already synced workouts are marked in the list.

The first version does not include:

- Background sync after every workout.
- App Store-ready onboarding.
- Multi-user account management.
- Guaranteed heart rate export. GPX route, time, distance, and elevation are the initial target.

## GitHub Token

The app will not embed a token. The user enters a fine-grained GitHub personal access token in settings. The token is stored in Keychain.

Required token capability for the repository:

- Contents write access, so the app can create GPX files.
- Actions write access, so the app can dispatch the workflow.

## Repository Workflow Changes

`.github/workflows/run_data_sync.yml` will accept `workflow_dispatch.inputs.run_type`. Runtime sync selection will be based on the dispatch input when present, otherwise the existing `RUN_TYPE` environment default.

The workflow push trigger will also include `GPX_OUT/**` as a convenience fallback, but the iOS app will use explicit workflow dispatch because it is easier to report success or failure.

## Error Handling

The app will surface user-readable errors for:

- HealthKit unavailable.
- HealthKit permission denied.
- Selected workout has no route.
- No GitHub token or incomplete settings.
- GitHub upload failure.
- GitHub workflow dispatch failure.

The app should not delete or modify existing GPX files. If GitHub reports that a target file already exists, the app will retry with a filename that includes the workout UUID suffix.

## Testing

Repository workflow changes will be covered by a small script/test that verifies dispatch input expression behavior where practical, and by checking YAML validity.

iOS code will isolate testable pieces:

- GPX serialization should be a pure Swift type with unit tests.
- GitHub request construction should be testable without network calls.
- HealthKit querying will be kept behind a service boundary because it needs device authorization and cannot be fully tested in CI.

Manual verification requires running the app on an iPhone with Health data access, selecting a workout route, syncing, and confirming that GitHub Actions imports the uploaded GPX.
