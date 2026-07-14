import XCTest
@testable import RunningPageSyncCore

final class GitHubClientTests: XCTestCase {
    func testBuildsUploadContentsRequest() throws {
        let settings = GitHubSettings(
            owner: "octo",
            repository: "run",
            branch: "master",
            workflowFileName: "run_data_sync.yml"
        )
        let request = try GitHubClient().makeUploadRequest(
            settings: settings,
            token: "secret-token",
            path: "GPX_OUT/2026-09-03-apple-workout.gpx",
            content: Data("hello".utf8),
            message: "Add Apple Workout GPX"
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octo/run/contents/GPX_OUT/2026-09-03-apple-workout.gpx"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?["message"] as? String, "Add Apple Workout GPX")
        XCTAssertEqual(object?["branch"] as? String, "master")
        XCTAssertEqual(object?["content"] as? String, Data("hello".utf8).base64EncodedString())
    }

    func testBuildsWorkflowDispatchRequest() throws {
        let settings = GitHubSettings(
            owner: "octo",
            repository: "run",
            branch: "master",
            workflowFileName: "run_data_sync.yml"
        )
        let request = try GitHubClient().makeDispatchRequest(
            settings: settings,
            token: "secret-token"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octo/run/actions/workflows/run_data_sync.yml/dispatches"
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let inputs = object?["inputs"] as? [String: String]
        XCTAssertEqual(object?["ref"] as? String, "master")
        XCTAssertEqual(inputs?["run_type"], "only_gpx")
    }

    func testTrimsTokenBeforeBuildingAuthorizationHeader() throws {
        let settings = GitHubSettings(
            owner: "octo",
            repository: "run",
            branch: "master",
            workflowFileName: "run_data_sync.yml"
        )

        let request = try GitHubClient().makeDispatchRequest(
            settings: settings,
            token: "  secret-token\n"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testRejectsIncompleteSettings() {
        let settings = GitHubSettings(
            owner: "",
            repository: "run",
            branch: "master",
            workflowFileName: "run_data_sync.yml"
        )

        XCTAssertThrowsError(
            try GitHubClient().makeDispatchRequest(settings: settings, token: "secret")
        ) { error in
            XCTAssertEqual(error as? WorkoutSyncError, .incompleteSettings)
        }
    }
}
