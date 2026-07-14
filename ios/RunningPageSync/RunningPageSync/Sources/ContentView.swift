import RunningPageSyncCore
import SwiftUI

struct ContentView: View {
    @StateObject private var healthService = HealthKitWorkoutService()
    @StateObject private var settingsStore = GitHubSettingsStore()
    @StateObject private var syncedStore = SyncedWorkoutStore()
    @StateObject private var syncCoordinator = SyncCoordinator()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                actionsSection
                WorkoutListView(
                    workouts: healthService.workouts,
                    syncedStore: syncedStore,
                    isSyncing: syncCoordinator.isSyncing,
                    sync: { workout in
                        Task {
                            await syncCoordinator.sync(
                                workout: workout,
                                settings: settingsStore.settings,
                                token: settingsStore.token,
                                healthService: healthService,
                                syncedStore: syncedStore
                            )
                        }
                    }
                )
            }
            .navigationTitle("RunningPage Sync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(settingsStore: settingsStore)
                }
            }
            .task {
                await loadWorkoutsIfPossible()
            }
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Health") {
                Text(healthService.authorizationState.title)
            }
            LabeledContent("GitHub") {
                Text(settingsStore.isReady ? "Configured" : "Needs settings")
            }
            if let message = syncCoordinator.message {
                Text(message)
                    .foregroundStyle(syncCoordinator.messageIsError ? .red : .secondary)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Authorize Health Access") {
                Task {
                    await healthService.authorizeAndLoad()
                }
            }
            Button("Reload Workouts") {
                Task {
                    await healthService.loadRecentRunningWorkouts()
                }
            }
            Button("Sync All Missing Runs") {
                Task {
                    await syncCoordinator.syncAllMissing(
                        workouts: healthService.workouts,
                        settings: settingsStore.settings,
                        token: settingsStore.token,
                        healthService: healthService,
                        syncedStore: syncedStore
                    )
                }
            }
            .disabled(syncCoordinator.isSyncing || healthService.workouts.isEmpty)
        }
    }

    private func loadWorkoutsIfPossible() async {
        guard healthService.authorizationState != .notDetermined else {
            return
        }
        await healthService.loadRecentRunningWorkouts()
    }
}

private extension HealthAuthorizationState {
    var title: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .authorized:
            "Authorized"
        case .unavailable:
            "Unavailable"
        case .failed:
            "Failed"
        }
    }
}
