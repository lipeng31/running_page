# Apple Workout Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-use iOS companion app that exports Apple Watch workout routes from HealthKit as GPX, uploads them to this repository, and triggers the existing data sync workflow without Strava.

**Architecture:** Add a new XcodeGen-managed SwiftUI iOS app under `ios/RunningPageSync/`, with pure Swift services for GPX serialization and GitHub request construction. Update `run_data_sync.yml` so `workflow_dispatch` can choose `only_gpx` without editing the default `RUN_TYPE`.

**Tech Stack:** SwiftUI, HealthKit, CoreLocation, Security Keychain, URLSession, XCTest, XcodeGen, GitHub REST API, GitHub Actions.

---

## File Structure

- Modify `.github/workflows/run_data_sync.yml`: add dispatch input and route existing conditionals through an effective run type.
- Create `ios/RunningPageSync/project.yml`: XcodeGen project definition.
- Create `ios/RunningPageSync/RunningPageSync/Sources/*.swift`: app, models, GPX serializer, HealthKit service, GitHub client, settings/keychain, views.
- Create `ios/RunningPageSync/RunningPageSyncTests/*.swift`: unit tests for GPX serialization and GitHub request construction.
- Create `docs/apple-workout-sync-app.md`: setup and usage guide.

## Task 1: Workflow Dispatch Input

**Files:**
- Modify: `.github/workflows/run_data_sync.yml`

- [ ] **Step 1: Write a workflow behavior check**

Create a shell check command that verifies the workflow contains `workflow_dispatch.inputs.run_type` and an effective run type env.

Run:

```bash
test "$(yq '.on.workflow_dispatch.inputs.run_type.type' .github/workflows/run_data_sync.yml)" = "choice"
```

Expected before implementation: FAIL because `run_type` does not exist.

- [ ] **Step 2: Update workflow dispatch inputs**

Change `workflow_dispatch:` to include:

```yaml
  workflow_dispatch:
    inputs:
      run_type:
        description: 'Sync type to run'
        required: false
        default: ''
        type: choice
        options:
          - ''
          - only_gpx
          - only_fit
          - only_tcx
          - strava
          - nike
          - garmin
          - garmin_cn
          - keep
          - coros
          - pass
```

- [ ] **Step 3: Add effective run type**

Add `EFFECTIVE_RUN_TYPE` to workflow env:

```yaml
  EFFECTIVE_RUN_TYPE: ${{ github.event.inputs.run_type || 'strava' }}
```

If preserving custom `RUN_TYPE` is needed, use:

```yaml
  EFFECTIVE_RUN_TYPE: ${{ github.event.inputs.run_type || 'strava' }}
```

and update all `if: env.RUN_TYPE == ...` checks to `if: env.EFFECTIVE_RUN_TYPE == ...`.

- [ ] **Step 4: Add GPX push fallback path**

Add these push paths:

```yaml
      - GPX_OUT/**
      - TCX_OUT/**
      - FIT_OUT/**
```

- [ ] **Step 5: Verify workflow text**

Run:

```bash
rg "EFFECTIVE_RUN_TYPE|run_type|GPX_OUT/\\*\\*" .github/workflows/run_data_sync.yml
```

Expected: all three patterns appear.

## Task 2: XcodeGen Project Scaffold

**Files:**
- Create: `ios/RunningPageSync/project.yml`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/RunningPageSyncApp.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Resources/Info.plist`

- [ ] **Step 1: Create minimal app target**

Create `project.yml` with one iOS app target and one test target:

```yaml
name: RunningPageSync
options:
  bundleIdPrefix: com.runningpage
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    MARKETING_VERSION: 1.0
    CURRENT_PROJECT_VERSION: 1
targets:
  RunningPageSync:
    type: application
    platform: iOS
    sources:
      - RunningPageSync/Sources
    resources:
      - RunningPageSync/Resources
    info:
      path: RunningPageSync/Resources/Info.plist
    entitlements:
      path: RunningPageSync/Resources/RunningPageSync.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.runningpage.RunningPageSync
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
  RunningPageSyncTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - RunningPageSyncTests
    dependencies:
      - target: RunningPageSync
```

- [ ] **Step 2: Add HealthKit plist and entitlement**

Add `NSHealthShareUsageDescription` and `com.apple.developer.healthkit`.

- [ ] **Step 3: Generate project**

Run:

```bash
cd ios/RunningPageSync && xcodegen generate
```

Expected: `RunningPageSync.xcodeproj` is generated.

## Task 3: GPX Serialization

**Files:**
- Create: `ios/RunningPageSync/RunningPageSync/Sources/GPXExporter.swift`
- Create: `ios/RunningPageSync/RunningPageSyncTests/GPXExporterTests.swift`

- [ ] **Step 1: Write failing GPX test**

Test a route with two points and assert GPX contains metadata time, trkpt latitude/longitude, elevation, and XML escaping for workout name.

Run:

```bash
cd ios/RunningPageSync && xcodebuild test -project RunningPageSync.xcodeproj -scheme RunningPageSync -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected before implementation: FAIL because `GPXExporter` does not exist.

- [ ] **Step 2: Implement `GPXExporter`**

Implement a pure Swift struct:

```swift
struct GPXExporter {
    func export(workout: WorkoutSummary, locations: [RouteLocation]) throws -> String
}
```

It should emit GPX 1.1 with `<metadata><time>`, `<trk><name>`, `<trkseg>`, and `<trkpt lat="" lon="">` nodes.

- [ ] **Step 3: Run GPX tests**

Run the same `xcodebuild test` command. Expected: PASS.

## Task 4: GitHub Client and Keychain

**Files:**
- Create: `ios/RunningPageSync/RunningPageSync/Sources/GitHubClient.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/KeychainStore.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/AppSettings.swift`
- Create: `ios/RunningPageSync/RunningPageSyncTests/GitHubClientTests.swift`

- [ ] **Step 1: Write failing GitHub request tests**

Assert upload request uses:

```text
PUT https://api.github.com/repos/{owner}/{repo}/contents/GPX_OUT/{filename}
Authorization: Bearer <token>
Accept: application/vnd.github+json
```

Assert dispatch request uses:

```text
POST https://api.github.com/repos/{owner}/{repo}/actions/workflows/run_data_sync.yml/dispatches
{"ref":"master","inputs":{"run_type":"only_gpx"}}
```

- [ ] **Step 2: Implement request builders and network methods**

Implement separate request-building methods so tests do not need real network:

```swift
func makeUploadRequest(settings: GitHubSettings, token: String, path: String, content: Data, message: String) throws -> URLRequest
func makeDispatchRequest(settings: GitHubSettings, token: String) throws -> URLRequest
```

- [ ] **Step 3: Add Keychain token storage**

Implement `KeychainStore` with `saveToken`, `loadToken`, and `deleteToken`.

- [ ] **Step 4: Run GitHub tests**

Run `xcodebuild test`. Expected: PASS.

## Task 5: HealthKit Service

**Files:**
- Create: `ios/RunningPageSync/RunningPageSync/Sources/HealthKitWorkoutService.swift`
- Modify: `ios/RunningPageSync/RunningPageSync/Sources/GPXExporter.swift`

- [ ] **Step 1: Add HealthKit service boundary**

Implement:

```swift
@MainActor
final class HealthKitWorkoutService: ObservableObject {
    func requestAuthorization() async throws
    func loadRecentRunningWorkouts(limit: Int) async throws -> [WorkoutSummary]
    func loadRouteLocations(for workout: WorkoutSummary) async throws -> [RouteLocation]
}
```

- [ ] **Step 2: Query workouts**

Use `HKSampleQuery` for `HKWorkoutType.workoutType()` with predicate for running workouts and sort by `startDate` descending.

- [ ] **Step 3: Query workout routes**

Use `HKQuery.predicateForObjects(from: workout.hkWorkout)` to fetch `HKSeriesType.workoutRoute()`, then use `HKWorkoutRouteQuery` to collect all `CLLocation` points.

- [ ] **Step 4: Handle no route**

Throw a user-facing `WorkoutSyncError.noRoute` when a selected workout has no route samples or no route points.

## Task 6: SwiftUI App Flow

**Files:**
- Create: `ios/RunningPageSync/RunningPageSync/Sources/ContentView.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/SettingsView.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/WorkoutListView.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/SyncCoordinator.swift`
- Create: `ios/RunningPageSync/RunningPageSync/Sources/SyncedWorkoutStore.swift`

- [ ] **Step 1: Implement settings form**

Fields: owner, repo, branch, workflow file name, token. Defaults: branch `master`, workflow `run_data_sync.yml`.

- [ ] **Step 2: Implement workout list**

Show recent running workouts with date, distance, duration, route unknown/unavailable state, and synced marker.

- [ ] **Step 3: Implement sync coordinator**

For selected workout:

```text
authorize/read route -> export GPX -> upload GPX -> dispatch workflow -> mark synced
```

- [ ] **Step 4: Add latest workout shortcut**

Add a button that syncs the first recent workout with a route.

## Task 7: Documentation and Verification

**Files:**
- Create: `docs/apple-workout-sync-app.md`
- Modify: `README-CN.md` or `README.md` only if a short pointer is useful.

- [ ] **Step 1: Document GitHub token setup**

Include fine-grained PAT permissions: Contents read/write and Actions read/write for this repo.

- [ ] **Step 2: Document app setup**

Include XcodeGen command, Xcode open command, signing team selection, device install, Health permission, and sync workflow.

- [ ] **Step 3: Verify repository tests**

Run:

```bash
uv run python -m unittest discover -s . -p 'test_*.py'
pnpm run build
```

- [ ] **Step 4: Verify iOS build**

Run:

```bash
cd ios/RunningPageSync
xcodegen generate
xcodebuild -project RunningPageSync.xcodeproj -scheme RunningPageSync -destination 'generic/platform=iOS' build
```

Expected: build succeeds. HealthKit runtime behavior still requires manual device verification.

## Self-Review

- Spec coverage: workflow input, GPX upload, HealthKit route reading, GitHub token storage, manual sync, and documentation are covered.
- Placeholder scan: no TBD/TODO placeholders are used as requirements.
- Type consistency: `WorkoutSummary`, `RouteLocation`, `GitHubSettings`, `GPXExporter`, and `GitHubClient` are introduced before downstream use.
