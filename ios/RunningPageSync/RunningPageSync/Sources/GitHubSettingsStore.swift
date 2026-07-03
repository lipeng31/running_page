import Foundation
import RunningPageSyncCore

@MainActor
final class GitHubSettingsStore: ObservableObject {
    @Published var settings: GitHubSettings
    @Published var token: String

    private let keychain = KeychainStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = GitHubSettings(
            owner: defaults.string(forKey: DefaultsKey.owner) ?? "",
            repository: defaults.string(forKey: DefaultsKey.repository) ?? "",
            branch: defaults.string(forKey: DefaultsKey.branch) ?? "master",
            workflowFileName: defaults.string(forKey: DefaultsKey.workflowFileName) ?? "run_data_sync.yml"
        )
        self.token = (try? keychain.loadToken()) ?? ""
    }

    var isReady: Bool {
        settings.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            settings.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            settings.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            settings.workflowFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func save() {
        defaults.set(settings.owner, forKey: DefaultsKey.owner)
        defaults.set(settings.repository, forKey: DefaultsKey.repository)
        defaults.set(settings.branch, forKey: DefaultsKey.branch)
        defaults.set(settings.workflowFileName, forKey: DefaultsKey.workflowFileName)
        try? keychain.saveToken(token)
    }

    func reload() {
        settings = GitHubSettings(
            owner: defaults.string(forKey: DefaultsKey.owner) ?? "",
            repository: defaults.string(forKey: DefaultsKey.repository) ?? "",
            branch: defaults.string(forKey: DefaultsKey.branch) ?? "master",
            workflowFileName: defaults.string(forKey: DefaultsKey.workflowFileName) ?? "run_data_sync.yml"
        )
        token = (try? keychain.loadToken()) ?? ""
    }
}

private enum DefaultsKey {
    static let owner = "github.owner"
    static let repository = "github.repository"
    static let branch = "github.branch"
    static let workflowFileName = "github.workflowFileName"
}
