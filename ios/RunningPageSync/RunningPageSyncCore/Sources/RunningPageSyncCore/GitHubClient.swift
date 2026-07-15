import Foundation

public struct GitHubSettings: Equatable, Sendable {
    public var owner: String
    public var repository: String
    public var branch: String
    public var workflowFileName: String

    public init(
        owner: String,
        repository: String,
        branch: String,
        workflowFileName: String
    ) {
        self.owner = owner
        self.repository = repository
        self.branch = branch
        self.workflowFileName = workflowFileName
    }

    public static let defaults = GitHubSettings(
        owner: "",
        repository: "",
        branch: "master",
        workflowFileName: "run_data_sync.yml"
    )

    var isComplete: Bool {
        !owner.trimmed.isEmpty &&
            !repository.trimmed.isEmpty &&
            !branch.trimmed.isEmpty &&
            !workflowFileName.trimmed.isEmpty
    }
}

public struct GitHubClient: Sendable {
    public static let inboxTag = "running-page-sync-inbox"

    public init() {}

    public func makeListReleasesRequest(
        settings: GitHubSettings,
        token: String
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)
        let baseURL = try apiURL(settings: settings, path: "releases")
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WorkoutSyncError.incompleteSettings
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        guard let url = components.url else {
            throw WorkoutSyncError.incompleteSettings
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers(token: token)
        return request
    }

    public func makeCreateInboxReleaseRequest(
        settings: GitHubSettings,
        token: String
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)
        let url = try apiURL(settings: settings, path: "releases")
        let body = CreateReleaseBody(
            tagName: Self.inboxTag,
            targetCommitish: settings.branch.trimmed,
            name: "RunningPage Sync Inbox",
            body: "Private temporary transfer area for Apple Workout GPX archives.",
            draft: true,
            prerelease: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers(token: token)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func makeUploadReleaseAssetRequest(
        settings: GitHubSettings,
        token: String,
        releaseID: Int,
        fileName: String,
        archive: Data
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)
        guard !fileName.isEmpty else {
            throw WorkoutSyncError.invalidArchiveEntry
        }
        let baseURL = try uploadsURL(
            settings: settings,
            path: "releases/\(releaseID)/assets"
        )
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WorkoutSyncError.incompleteSettings
        }
        components.queryItems = [URLQueryItem(name: "name", value: fileName)]
        guard let url = components.url else {
            throw WorkoutSyncError.incompleteSettings
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers(token: token, contentType: "application/zip")
        request.httpBody = archive
        return request
    }

    public func makeDispatchRequest(
        settings: GitHubSettings,
        token: String,
        releaseAssetID: Int
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)

        let url = try apiURL(
            settings: settings,
            path: "actions/workflows/\(settings.workflowFileName.trimmed)/dispatches"
        )
        let body = DispatchBody(
            ref: settings.branch.trimmed,
            inputs: [
                "run_type": "only_gpx",
                "release_asset_id": String(releaseAssetID)
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers(token: token)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func uploadGPXArchive(
        settings: GitHubSettings,
        token: String,
        fileName: String,
        archive: Data
    ) async throws -> Int {
        let release = try await inboxRelease(settings: settings, token: token)
        let request = try makeUploadReleaseAssetRequest(
            settings: settings,
            token: token,
            releaseID: release.id,
            fileName: fileName,
            archive: archive
        )
        let data = try await perform(request: request, validStatusCodes: [201])
        return try JSONDecoder().decode(ReleaseAssetResponse.self, from: data).id
    }

    public func dispatchWorkflow(
        settings: GitHubSettings,
        token: String,
        releaseAssetID: Int
    ) async throws {
        let request = try makeDispatchRequest(
            settings: settings,
            token: token,
            releaseAssetID: releaseAssetID
        )
        _ = try await perform(request: request, validStatusCodes: [204])
    }

    private func inboxRelease(
        settings: GitHubSettings,
        token: String
    ) async throws -> ReleaseResponse {
        if let release = try await findInboxRelease(settings: settings, token: token) {
            return release
        }

        let request = try makeCreateInboxReleaseRequest(settings: settings, token: token)
        do {
            let data = try await perform(request: request, validStatusCodes: [201])
            return try JSONDecoder().decode(ReleaseResponse.self, from: data)
        } catch WorkoutSyncError.invalidGitHubResponse(statusCode: 422) {
            if let release = try await findInboxRelease(settings: settings, token: token) {
                return release
            }
            throw WorkoutSyncError.invalidGitHubResponse(statusCode: 422)
        }
    }

    private func findInboxRelease(
        settings: GitHubSettings,
        token: String
    ) async throws -> ReleaseResponse? {
        let request = try makeListReleasesRequest(settings: settings, token: token)
        let data = try await perform(request: request, validStatusCodes: [200])
        return try JSONDecoder()
            .decode([ReleaseResponse].self, from: data)
            .first { $0.tagName == Self.inboxTag && $0.draft }
    }

    private func validate(settings: GitHubSettings, token: String) throws {
        guard settings.isComplete else {
            throw WorkoutSyncError.incompleteSettings
        }
        guard !token.trimmed.isEmpty else {
            throw WorkoutSyncError.missingToken
        }
    }

    private func apiURL(settings: GitHubSettings, path: String) throws -> URL {
        guard let url = URL(
            string: "https://api.github.com/repos/\(settings.owner.trimmed)/\(settings.repository.trimmed)/\(path)"
        ) else {
            throw WorkoutSyncError.incompleteSettings
        }
        return url
    }

    private func uploadsURL(settings: GitHubSettings, path: String) throws -> URL {
        guard let url = URL(
            string: "https://uploads.github.com/repos/\(settings.owner.trimmed)/\(settings.repository.trimmed)/\(path)"
        ) else {
            throw WorkoutSyncError.incompleteSettings
        }
        return url
    }

    private func headers(token: String, contentType: String = "application/json") -> [String: String] {
        [
            "Authorization": "Bearer \(token.trimmed)",
            "Accept": "application/vnd.github+json",
            "Content-Type": contentType,
            "X-GitHub-Api-Version": "2022-11-28"
        ]
    }

    private func perform(
        request: URLRequest,
        validStatusCodes: Set<Int>
    ) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkoutSyncError.invalidGitHubResponse(statusCode: -1)
        }
        guard validStatusCodes.contains(httpResponse.statusCode) else {
            throw WorkoutSyncError.invalidGitHubResponse(statusCode: httpResponse.statusCode)
        }
        return data
    }
}

private struct CreateReleaseBody: Encodable {
    let tagName: String
    let targetCommitish: String
    let name: String
    let body: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case name
        case body
        case draft
        case prerelease
    }
}

private struct ReleaseResponse: Decodable {
    let id: Int
    let tagName: String
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case draft
    }
}

private struct ReleaseAssetResponse: Decodable {
    let id: Int
}

private struct DispatchBody: Encodable {
    let ref: String
    let inputs: [String: String]
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
