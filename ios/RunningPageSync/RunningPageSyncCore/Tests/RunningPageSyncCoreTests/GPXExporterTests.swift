import XCTest
@testable import RunningPageSyncCore

final class GPXExporterTests: XCTestCase {
    func testExportsWorkoutRouteAsEscapedGPX() throws {
        let workout = WorkoutSummary(
            id: "workout-1",
            name: "Morning <Run>",
            startDate: Date(timeIntervalSince1970: 1_788_422_400),
            endDate: Date(timeIntervalSince1970: 1_788_426_000),
            distanceMeters: 10_000,
            durationSeconds: 3_600,
            hasRoute: true
        )
        let locations = [
            RouteLocation(
                latitude: 38.8895,
                longitude: -77.0353,
                altitude: 12.5,
                timestamp: Date(timeIntervalSince1970: 1_788_422_400)
            ),
            RouteLocation(
                latitude: 38.8896,
                longitude: -77.0354,
                altitude: 13.25,
                timestamp: Date(timeIntervalSince1970: 1_788_422_410)
            )
        ]

        let gpx = try GPXExporter().export(workout: workout, locations: locations)

        XCTAssertTrue(gpx.contains(#"<gpx version="1.1" creator="RunningPageSync""#))
        XCTAssertTrue(gpx.contains("<name>Morning &lt;Run&gt;</name>"))
        XCTAssertTrue(gpx.contains(#"<trkpt lat="38.8895000" lon="-77.0353000">"#))
        XCTAssertTrue(gpx.contains("<ele>12.50</ele>"))
        XCTAssertTrue(gpx.contains("<time>2026-09-03T08:00:00Z</time>"))
        XCTAssertTrue(gpx.contains(#"<trkpt lat="38.8896000" lon="-77.0354000">"#))
    }

    func testRejectsEmptyRoute() {
        let workout = WorkoutSummary(
            id: "workout-2",
            name: "Empty",
            startDate: Date(timeIntervalSince1970: 1_788_422_400),
            endDate: Date(timeIntervalSince1970: 1_788_426_000),
            distanceMeters: 0,
            durationSeconds: 0,
            hasRoute: false
        )

        XCTAssertThrowsError(try GPXExporter().export(workout: workout, locations: [])) { error in
            XCTAssertEqual(error as? WorkoutSyncError, .noRoute)
        }
    }
}
