import XCTest
@testable import RunningPageSyncCore

final class GitHubClientTests: XCTestCase {
    private let settings = GitHubSettings(
        owner: "octo",
        repository: "run",
        branch: "master",
        workflowFileName: "run_data_sync.yml"
    )

    func testBuildsListReleasesRequest() throws {
        let request = try GitHubClient().makeListReleasesRequest(
            settings: settings,
            token: "secret-token"
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octo/run/releases?per_page=100"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testBuildsDraftInboxReleaseRequest() throws {
        let request = try GitHubClient().makeCreateInboxReleaseRequest(
            settings: settings,
            token: "secret-token"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/octo/run/releases")

        let body = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?["tag_name"] as? String, GitHubClient.inboxTag)
        XCTAssertEqual(object?["target_commitish"] as? String, "master")
        XCTAssertEqual(object?["draft"] as? Bool, true)
        XCTAssertEqual(object?["prerelease"] as? Bool, false)
    }

    func testBuildsReleaseAssetUploadRequest() throws {
        let archive = Data("zip-data".utf8)
        let request = try GitHubClient().makeUploadReleaseAssetRequest(
            settings: settings,
            token: "secret-token",
            releaseID: 42,
            fileName: "apple-workouts-123.zip",
            archive: archive
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://uploads.github.com/repos/octo/run/releases/42/assets?name=apple-workouts-123.zip"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/zip")
        XCTAssertEqual(request.httpBody, archive)
    }

    func testBuildsWorkflowDispatchRequestWithReleaseAsset() throws {
        let request = try GitHubClient().makeDispatchRequest(
            settings: settings,
            token: "secret-token",
            releaseAssetID: 987
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
        XCTAssertEqual(inputs?["release_asset_id"], "987")
    }

    func testBuildsFullRepairDispatchRequestWithReleaseAssets() throws {
        let request = try GitHubClient().makeDispatchRequest(
            settings: settings,
            token: "secret-token",
            releaseAssetIDs: [101, 202, 303]
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let inputs = object?["inputs"] as? [String: String]
        XCTAssertEqual(inputs?["run_type"], "only_gpx")
        XCTAssertNil(inputs?["release_asset_id"])
        XCTAssertEqual(inputs?["release_asset_ids"], "101,202,303")
    }

    func testTrimsTokenBeforeBuildingAuthorizationHeader() throws {
        let request = try GitHubClient().makeDispatchRequest(
            settings: settings,
            token: "  secret-token\n",
            releaseAssetID: 1
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testRejectsIncompleteSettings() {
        let incompleteSettings = GitHubSettings(
            owner: "",
            repository: "run",
            branch: "master",
            workflowFileName: "run_data_sync.yml"
        )

        XCTAssertThrowsError(
            try GitHubClient().makeDispatchRequest(
                settings: incompleteSettings,
                token: "secret",
                releaseAssetID: 1
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutSyncError, .incompleteSettings)
        }
    }
}
