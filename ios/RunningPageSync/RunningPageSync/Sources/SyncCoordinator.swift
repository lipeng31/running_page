import Foundation
import RunningPageSyncCore

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let exporter = GPXExporter()
    private let githubClient = GitHubClient()

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
            setMessage("Reading workout route...", isError: false)
            let locations = try await healthService.loadRouteLocations(for: workout)

            setMessage("Creating GPX...", isError: false)
            let gpx = try exporter.export(workout: workout, locations: locations)
            let path = "GPX_OUT/\(fileName(for: workout))"

            setMessage("Uploading GPX to GitHub...", isError: false)
            try await githubClient.uploadGPX(
                settings: settings,
                token: token,
                path: path,
                content: Data(gpx.utf8),
                message: "Add Apple Workout GPX \(workout.startDate.formatted(date: .numeric, time: .shortened))"
            )

            setMessage("Triggering running_page sync...", isError: false)
            try await githubClient.dispatchWorkflow(settings: settings, token: token)

            syncedStore.markSynced(workout.id)
            setMessage("Sync started in GitHub Actions.", isError: false)
        } catch {
            setMessage(error.localizedDescription, isError: true)
        }
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
