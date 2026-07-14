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
    public init() {}

    public func makeUploadRequest(
        settings: GitHubSettings,
        token: String,
        path: String,
        content: Data,
        message: String
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)

        let cleanPath = path.split(separator: "/").map(String.init).joined(separator: "/")
        let url = try apiURL(
            settings: settings,
            path: "contents/\(cleanPath)"
        )

        let body = UploadBody(
            message: message,
            content: content.base64EncodedString(),
            branch: settings.branch.trimmed
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = headers(token: token)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func makeDispatchRequest(
        settings: GitHubSettings,
        token: String
    ) throws -> URLRequest {
        try validate(settings: settings, token: token)

        let url = try apiURL(
            settings: settings,
            path: "actions/workflows/\(settings.workflowFileName.trimmed)/dispatches"
        )
        let body = DispatchBody(
            ref: settings.branch.trimmed,
            inputs: ["run_type": "only_gpx"]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers(token: token)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func uploadGPX(
        settings: GitHubSettings,
        token: String,
        path: String,
        content: Data,
        message: String
    ) async throws {
        let request = try makeUploadRequest(
            settings: settings,
            token: token,
            path: path,
            content: content,
            message: message
        )
        try await send(request: request, validStatusCodes: 200...201)
    }

    public func dispatchWorkflow(
        settings: GitHubSettings,
        token: String
    ) async throws {
        let request = try makeDispatchRequest(settings: settings, token: token)
        try await send(request: request, validStatusCodes: 204...204)
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

    private func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token.trimmed)",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
    }

    private func send(
        request: URLRequest,
        validStatusCodes: ClosedRange<Int>
    ) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkoutSyncError.invalidGitHubResponse(statusCode: -1)
        }
        guard validStatusCodes.contains(httpResponse.statusCode) else {
            throw WorkoutSyncError.invalidGitHubResponse(statusCode: httpResponse.statusCode)
        }
    }
}

private struct UploadBody: Encodable {
    let message: String
    let content: String
    let branch: String
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
