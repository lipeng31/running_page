import RunningPageSyncCore
import SwiftUI

struct WorkoutListView: View {
    let workouts: [WorkoutSummary]
    let syncedStore: SyncedWorkoutStore
    let isSyncing: Bool
    let sync: (WorkoutSummary) -> Void

    var body: some View {
        Section("Recent Runs") {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No Runs Loaded",
                    systemImage: "figure.run",
                    description: Text("Authorize Health access, then reload workouts.")
                )
            } else {
                ForEach(workouts) { workout in
                    WorkoutRow(
                        workout: workout,
                        isSynced: syncedStore.isSynced(workout.id),
                        isSyncing: isSyncing,
                        sync: sync
                    )
                }
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary
    let isSynced: Bool
    let isSyncing: Bool
    let sync: (WorkoutSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(workout.name)
                        .font(.headline)
                    Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSynced {
                    Label("Synced", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                }
            }

            HStack(spacing: 16) {
                Label(distanceText, systemImage: "map")
                Label(durationText, systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(isSynced ? "Sync Again" : "Sync") {
                sync(workout)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
        }
        .padding(.vertical, 6)
    }

    private var distanceText: String {
        Measurement(value: workout.distanceMeters, unit: UnitLength.meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: workout.durationSeconds) ?? "-"
    }
}
