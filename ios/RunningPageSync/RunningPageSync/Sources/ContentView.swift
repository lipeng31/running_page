import RunningPageSyncCore
import SwiftUI

struct ContentView: View {
    @StateObject private var healthService = HealthKitWorkoutService()
    @StateObject private var settingsStore = GitHubSettingsStore()
    @StateObject private var syncedStore = SyncedWorkoutStore()
    @StateObject private var syncCoordinator = SyncCoordinator()
    @State private var showingSettings = false
    @State private var showingRouteRepairConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    overview
                    syncControls

                    if let message = syncCoordinator.message {
                        SyncMessage(
                            message: message,
                            isError: syncCoordinator.messageIsError,
                            isSyncing: syncCoordinator.isSyncing
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }

                    WorkoutListView(
                        workouts: healthService.workouts,
                        syncedStore: syncedStore,
                        isSyncing: syncCoordinator.isSyncing,
                        sync: syncWorkout
                    )
                    .padding(.top, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("RunningPage Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.10), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("GitHub settings", systemImage: "gearshape")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("GitHub settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(settingsStore: settingsStore)
                }
            }
            .confirmationDialog(
                "Rebuild every available route?",
                isPresented: $showingRouteRepairConfirmation,
                titleVisibility: .visible
            ) {
                Button("Repair All Routes", role: .destructive) {
                    repairAllRoutes()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This re-exports every readable HealthKit route, replaces damaged legacy routes in one GitHub Action, and may take several minutes. Workouts without HealthKit route data are left unchanged."
                )
            }
            .refreshable {
                await healthService.loadRecentRunningWorkouts()
            }
            .task {
                await healthService.authorizeAndLoad()
                if CommandLine.arguments.contains("--repair-all-routes"),
                   settingsStore.isReady {
                    await syncCoordinator.repairAllRoutes(
                        workouts: healthService.workouts,
                        settings: settingsStore.settings,
                        token: settingsStore.token,
                        healthService: healthService,
                        syncedStore: syncedStore
                    )
                } else if let repairDate = targetedRepairDate(),
                          let workout = healthService.workouts.min(by: {
                              abs($0.startDate.timeIntervalSince(repairDate))
                                  < abs($1.startDate.timeIntervalSince(repairDate))
                          }),
                          abs(workout.startDate.timeIntervalSince(repairDate)) <= 5 * 60,
                          settingsStore.isReady {
                    await syncCoordinator.sync(
                        workout: workout,
                        settings: settingsStore.settings,
                        token: settingsStore.token,
                        healthService: healthService,
                        syncedStore: syncedStore
                    )
                }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Workout")
                        .font(.title2.bold())
                    Text(repositoryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(healthService.workouts.count)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text("runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                StatusItem(
                    title: "Health",
                    value: healthService.authorizationState.title,
                    systemImage: healthService.authorizationState.systemImage,
                    color: healthService.authorizationState.color
                )

                Divider()
                    .frame(height: 36)
                    .padding(.horizontal, 16)

                StatusItem(
                    title: "GitHub",
                    value: settingsStore.isReady ? "Ready" : "Setup needed",
                    systemImage: settingsStore.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    color: settingsStore.isReady ? .green : .orange
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var syncControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Sync")
                        .font(.headline)
                    Text("Compare Health with the Action cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if healthService.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Button(action: syncAllMissing) {
                HStack {
                    if syncCoordinator.isSyncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(syncCoordinator.isSyncing ? "Syncing..." : "Sync Missing Runs")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
            .disabled(
                syncCoordinator.isSyncing ||
                    healthService.isLoading ||
                    healthService.workouts.isEmpty ||
                    !settingsStore.isReady
            )

            Button {
                showingRouteRepairConfirmation = true
            } label: {
                Label("Repair All Routes", systemImage: "map.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.orange)
            .disabled(
                syncCoordinator.isSyncing ||
                    healthService.isLoading ||
                    healthService.workouts.isEmpty ||
                    !settingsStore.isReady
            )

            HStack(spacing: 12) {
                Button {
                    Task {
                        await healthService.authorizeAndLoad()
                    }
                } label: {
                    Label("Health", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .disabled(healthService.isLoading || syncCoordinator.isSyncing)

                Button {
                    Task {
                        await healthService.loadRecentRunningWorkouts()
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .disabled(healthService.isLoading || syncCoordinator.isSyncing)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
    }

    private var repositoryName: String {
        guard settingsStore.isReady else {
            return "Connect a GitHub repository"
        }
        return "\(settingsStore.settings.owner)/\(settingsStore.settings.repository)"
    }

    private func syncAllMissing() {
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

    private func syncWorkout(_ workout: WorkoutSummary) {
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

    private func repairAllRoutes() {
        Task {
            await syncCoordinator.repairAllRoutes(
                workouts: healthService.workouts,
                settings: settingsStore.settings,
                token: settingsStore.token,
                healthService: healthService,
                syncedStore: syncedStore
            )
        }
    }

    private func targetedRepairDate() -> Date? {
        let prefix = "--repair-workout-start="
        guard let value = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: String(value.dropFirst(prefix.count)))
    }
}

private struct StatusItem: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncMessage: View {
    let message: String
    let isError: Bool
    let isSyncing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            } else {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? .red : .green)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(isError ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            isError ? Color.red.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

private extension HealthAuthorizationState {
    var title: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .authorized:
            "Ready"
        case .unavailable:
            "Unavailable"
        case .failed:
            "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .authorized:
            "heart.circle.fill"
        case .notDetermined:
            "heart.circle"
        case .unavailable, .failed:
            "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .authorized:
            .red
        case .notDetermined:
            .secondary
        case .unavailable, .failed:
            .orange
        }
    }
}
