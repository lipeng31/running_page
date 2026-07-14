import RunningPageSyncCore
import SwiftUI

struct WorkoutListView: View {
    let workouts: [WorkoutSummary]
    let syncedStore: SyncedWorkoutStore
    let isSyncing: Bool
    let sync: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Runs")
                    .font(.title3.bold())
                Spacer()
                if workouts.count > 30 {
                    Text("Latest 30")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if workouts.isEmpty {
                ContentUnavailableView(
                    "No Runs Loaded",
                    systemImage: "figure.run",
                    description: Text("Grant Health access or pull down to reload.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(workouts.prefix(30)) { workout in
                        WorkoutRow(
                            workout: workout,
                            isSynced: syncedStore.isSynced(workout.id),
                            isSyncing: isSyncing,
                            sync: sync
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 24)
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary
    let isSynced: Bool
    let isSyncing: Bool
    let sync: (WorkoutSummary) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(workout.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Label(distanceText, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label(durationText, systemImage: "timer")
                    Text(workout.startDate.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            VStack(spacing: 8) {
                if isSynced {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Synced")
                }

                Button {
                    sync(workout)
                } label: {
                    Label(isSynced ? "Sync again" : "Sync workout", systemImage: "arrow.up.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .disabled(isSyncing)
                .accessibilityLabel(isSynced ? "Sync again" : "Sync workout")
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var distanceText: String {
        Measurement(value: workout.distanceMeters, unit: UnitLength.meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: workout.durationSeconds) ?? "-"
    }
}
