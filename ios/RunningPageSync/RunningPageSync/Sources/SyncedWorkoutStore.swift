import Foundation

@MainActor
final class SyncedWorkoutStore: ObservableObject {
    @Published private var syncedIDs: Set<String>
    private let defaults: UserDefaults
    private let key = "syncedWorkoutIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.syncedIDs = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isSynced(_ id: String) -> Bool {
        syncedIDs.contains(id)
    }

    func markSynced(_ id: String) {
        syncedIDs.insert(id)
        defaults.set(Array(syncedIDs).sorted(), forKey: key)
    }
}
