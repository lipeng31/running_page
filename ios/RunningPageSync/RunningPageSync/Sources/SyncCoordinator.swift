import Foundation
import RunningPageSyncCore

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let exporter = GPXExporter()
    private let archiveBuilder = ZipArchiveBuilder()
    private let githubClient = GitHubClient()
    private let inventoryClient = ActivityInventoryClient()

    func setMessage(_ message: String, isError: Bool) {
        self.message = message
        self.messageIsError = isError
    }

    func sync(
        workout: WorkoutSummary,
        settings: GitHubSettings,
        token: String,
        healthService: HealthKitWorkoutService,
        syncedStore: SyncedWorkoutStore
    ) async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            setMessage("Reading route and workout metrics...", isError: false)
            let preparedWorkout = try await prepare(
                workout: workout,
                healthService: healthService
            )
            setMessage("Uploading a private temporary GPX archive...", isError: false)
            let releaseAssetID = try await uploadArchive(
                entries: [preparedWorkout.entry],
                settings: settings,
                token: token
            )

            setMessage("Triggering running_page sync...", isError: false)
            try await githubClient.dispatchWorkflow(
                settings: settings,
                token: token,
                releaseAssetID: releaseAssetID
            )

            syncedStore.markSynced(workout.id)
            setMessage(
                "Sync started with \(preparedWorkout.metricCount) metric types.",
                isError: false
            )
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    func syncAllMissing(
        workouts: [WorkoutSummary],
        settings: GitHubSettings,
        token: String,
        healthService: HealthKitWorkoutService,
        syncedStore: SyncedWorkoutStore
    ) async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkoutSyncError.missingToken
            }
            setMessage("Reading the current Action cache inventory...", isError: false)
            let cachedActivities = try await inventoryClient.fetch(settings: settings)
            let missingWorkouts = ActivityMatcher.missingWorkouts(
                workouts,
                cachedActivities: cachedActivities
            ).sorted { $0.startDate < $1.startDate }

            guard !missingWorkouts.isEmpty else {
                setMessage("All Health workouts are already in the Action cache.", isError: false)
                return
            }

            var preparedWorkouts: [PreparedWorkout] = []
            var failures: [String] = []
            for (index, workout) in missingWorkouts.enumerated() {
                setMessage(
                    "Preparing missing run \(index + 1) of \(missingWorkouts.count)...",
                    isError: false
                )
                do {
                    let preparedWorkout = try await prepare(
                        workout: workout,
                        healthService: healthService
                    )
                    preparedWorkouts.append(preparedWorkout)
                } catch {
                    if let syncError = error as? WorkoutSyncError,
                       case let .invalidGitHubResponse(statusCode) = syncError,
                       statusCode == 401 || statusCode == 403 {
                        throw syncError
                    }
                    failures.append(
                        "\(workout.startDate.formatted(date: .numeric, time: .shortened)): \(error.localizedDescription)"
                    )
                }
            }

            guard !preparedWorkouts.isEmpty else {
                setMessage(
                    "No missing runs were prepared. \(failures.first ?? "Unknown error.")",
                    isError: true
                )
                return
            }

            setMessage(
                "Uploading one private archive with \(preparedWorkouts.count) runs...",
                isError: false
            )
            let releaseAssetID = try await uploadArchive(
                entries: preparedWorkouts.map(\.entry),
                settings: settings,
                token: token
            )

            setMessage("Triggering running_page sync...", isError: false)
            try await githubClient.dispatchWorkflow(
                settings: settings,
                token: token,
                releaseAssetID: releaseAssetID
            )

            for preparedWorkout in preparedWorkouts {
                syncedStore.markSynced(preparedWorkout.workout.id)
            }

            if failures.isEmpty {
                setMessage("Sync started for \(preparedWorkouts.count) missing runs.", isError: false)
            } else {
                setMessage(
                    "Sync started for \(preparedWorkouts.count) runs; \(failures.count) failed. \(failures[0])",
                    isError: true
                )
            }
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func prepare(
        workout: WorkoutSummary,
        healthService: HealthKitWorkoutService
    ) async throws -> PreparedWorkout {
        let workoutData = try await healthService.loadWorkoutData(for: workout)
        let gpx = try exporter.export(workout: workout, data: workoutData)
        return PreparedWorkout(
            workout: workout,
            entry: ZipEntry(
                name: fileName(for: workout),
                data: Data(gpx.utf8)
            ),
            metricCount: workoutData.metrics.count
        )
    }

    private func uploadArchive(
        entries: [ZipEntry],
        settings: GitHubSettings,
        token: String
    ) async throws -> Int {
        let archive = try archiveBuilder.archive(entries: entries)
        return try await githubClient.uploadGPXArchive(
            settings: settings,
            token: token,
            fileName: "apple-workouts-\(UUID().uuidString.lowercased()).zip",
            archive: archive
        )
    }

    private func fileName(for workout: WorkoutSummary) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: workout.startDate)
        let suffix = workout.id.prefix(8)
        return "\(timestamp)-apple-workout-\(suffix).gpx"
    }
}

private struct PreparedWorkout {
    let workout: WorkoutSummary
    let entry: ZipEntry
    let metricCount: Int
}
