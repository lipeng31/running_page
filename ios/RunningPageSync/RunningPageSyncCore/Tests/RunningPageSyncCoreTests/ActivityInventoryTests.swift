import XCTest
@testable import RunningPageSyncCore

final class ActivityInventoryTests: XCTestCase {
    func testParsesCachedActivitiesWithUTCAndFractionalDuration() throws {
        let data = Data(
            """
            [
              {
                "distance": 10535.746417,
                "moving_time": "0:56:12.996665",
                "start_date": "2026-07-12 21:25:10"
              },
              {
                "distance": 19770.36,
                "moving_time": "1:39:14",
                "start_date": "2026-07-13 21:12:58+00:00"
              }
            ]
            """.utf8
        )

        let activities = try ActivityInventoryParser.parse(data)

        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].distanceMeters, 10535.746417, accuracy: 0.001)
        XCTAssertEqual(activities[0].durationSeconds, 3372.996665, accuracy: 0.001)
        XCTAssertEqual(activities[0].startDate.timeIntervalSince1970, 1_783_891_510)
        XCTAssertEqual(activities[1].durationSeconds, 5954)
    }

    func testFindsOnlyWorkoutsMissingFromCache() {
        let existingStart = Date(timeIntervalSince1970: 1_783_891_510)
        let existing = workout(
            id: "existing",
            startDate: existingStart,
            distance: 10_400,
            duration: 3_400
        )
        let missing = workout(
            id: "missing",
            startDate: existingStart.addingTimeInterval(86_400),
            distance: 8_000,
            duration: 2_700
        )
        let cached = CachedActivity(
            startDate: existingStart.addingTimeInterval(30),
            distanceMeters: 10_535,
            durationSeconds: 3_372
        )

        let result = ActivityMatcher.missingWorkouts(
            [existing, missing],
            cachedActivities: [cached]
        )

        XCTAssertEqual(result.map(\.id), ["missing"])
    }

    private func workout(
        id: String,
        startDate: Date,
        distance: Double,
        duration: TimeInterval
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            name: "Run",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            distanceMeters: distance,
            durationSeconds: duration,
            hasRoute: true
        )
    }
}
