import Foundation
import RunningPageSyncCore

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let exporter = GPXExporter()
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
            setMessage("Uploading GPX to GitHub...", isError: false)
            let metricCount = try await upload(
                workout: workout,
                settings: settings,
                token: token,
                healthService: healthService
            )

            setMessage("Triggering running_page sync...", isError: false)
            try await githubClient.dispatchWorkflow(settings: settings, token: token)

            syncedStore.markSynced(workout.id)
            setMessage(
                "Sync started with \(metricCount) metric types.",
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

            var uploadedCount = 0
            var failures: [String] = []
            for (index, workout) in missingWorkouts.enumerated() {
                setMessage(
                    "Uploading missing run \(index + 1) of \(missingWorkouts.count)...",
                    isError: false
                )
                do {
                    _ = try await upload(
                        workout: workout,
                        settings: settings,
                        token: token,
                        healthService: healthService
                    )
                    syncedStore.markSynced(workout.id)
                    uploadedCount += 1
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

            guard uploadedCount > 0 else {
                setMessage(
                    "No missing runs were uploaded. \(failures.first ?? "Unknown error.")",
                    isError: true
                )
                return
            }

            setMessage("Triggering running_page sync...", isError: false)
            try await githubClient.dispatchWorkflow(settings: settings, token: token)

            if failures.isEmpty {
                setMessage("Sync started for \(uploadedCount) missing runs.", isError: false)
            } else {
                setMessage(
                    "Sync started for \(uploadedCount) runs; \(failures.count) failed. \(failures[0])",
                    isError: true
                )
            }
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
    }

    private func upload(
        workout: WorkoutSummary,
        settings: GitHubSettings,
        token: String,
        healthService: HealthKitWorkoutService
    ) async throws -> Int {
        let workoutData = try await healthService.loadWorkoutData(for: workout)
        let gpx = try exporter.export(workout: workout, data: workoutData)
        let path = "GPX_OUT/\(fileName(for: workout))"
        try await githubClient.uploadGPX(
            settings: settings,
            token: token,
            path: path,
            content: Data(gpx.utf8),
            message: "Add Apple Workout GPX \(workout.startDate.formatted(date: .numeric, time: .shortened))"
        )
        return workoutData.metrics.count
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
