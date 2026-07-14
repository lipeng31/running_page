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

    func testExportsHealthMetricsMetadataEventsAndTrackPointHeartRate() throws {
        let startDate = Date(timeIntervalSince1970: 1_788_422_400)
        let workout = WorkoutSummary(
            id: "workout&1",
            name: "Morning Run",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_700),
            distanceMeters: 10_000,
            durationSeconds: 3_600,
            hasRoute: true
        )
        let heartRate = WorkoutMetric(
            identifier: "HKQuantityTypeIdentifierHeartRate",
            name: "heart_rate",
            unit: "bpm",
            samples: [
                WorkoutMetricSample(
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(5),
                    value: 151.6,
                    source: "Apple Watch",
                    metadata: [WorkoutMetadataEntry(key: "motion<context", value: "1")]
                )
            ],
            averageValue: 148.4,
            minimumValue: 92,
            maximumValue: 174
        )
        let power = WorkoutMetric(
            identifier: "HKQuantityTypeIdentifierRunningPower",
            name: "running_power",
            unit: "W",
            samples: [
                WorkoutMetricSample(
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(5),
                    value: 276.25
                )
            ],
            averageValue: 264.5,
            maximumValue: 310
        )
        let data = WorkoutExportData(
            locations: [
                RouteLocation(
                    latitude: 38.8895,
                    longitude: -77.0353,
                    altitude: 12.5,
                    timestamp: startDate,
                    horizontalAccuracy: 4.2,
                    verticalAccuracy: 3.1,
                    speed: 3.4,
                    course: 182.5
                )
            ],
            metrics: [power, heartRate],
            metadata: [WorkoutMetadataEntry(key: "device", value: "Watch & Phone")],
            events: [
                WorkoutEventRecord(
                    type: 3,
                    startDate: startDate.addingTimeInterval(600),
                    endDate: startDate.addingTimeInterval(620)
                )
            ]
        )

        let gpx = try GPXExporter().export(workout: workout, data: data)

        XCTAssertTrue(gpx.contains(#"xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1""#))
        XCTAssertTrue(gpx.contains("<rps:workout_id>workout&amp;1</rps:workout_id>"))
        XCTAssertTrue(gpx.contains("<rps:distance>10000</rps:distance>"))
        XCTAssertTrue(gpx.contains("<rps:moving_time>3600</rps:moving_time>"))
        XCTAssertTrue(gpx.contains("<rps:elapsed_time>3700</rps:elapsed_time>"))
        XCTAssertTrue(gpx.contains("<rps:average_hr>148.4</rps:average_hr>"))
        XCTAssertTrue(gpx.contains(#"<rps:item key="device">Watch &amp; Phone</rps:item>"#))
        XCTAssertTrue(gpx.contains(#"<rps:event type="3" start="2026-09-03T08:10:00Z" end="2026-09-03T08:10:20Z" />"#))
        XCTAssertTrue(gpx.contains(#"<rps:metric identifier="HKQuantityTypeIdentifierHeartRate" name="heart_rate" unit="bpm">"#))
        XCTAssertTrue(gpx.contains(#"<rps:summary average="148.4" minimum="92" maximum="174" />"#))
        XCTAssertTrue(gpx.contains(#"value="151.6" source="Apple Watch""#))
        XCTAssertTrue(gpx.contains(#"<rps:item key="motion&lt;context">1</rps:item>"#))
        XCTAssertTrue(gpx.contains("<gpxtpx:hr>152</gpxtpx:hr>"))
        XCTAssertTrue(gpx.contains("<rps:horizontal_accuracy>4.2</rps:horizontal_accuracy>"))
        XCTAssertTrue(gpx.contains("<rps:speed>3.4</rps:speed>"))
        XCTAssertTrue(gpx.contains(#"name="running_power" unit="W""#))
    }
}
