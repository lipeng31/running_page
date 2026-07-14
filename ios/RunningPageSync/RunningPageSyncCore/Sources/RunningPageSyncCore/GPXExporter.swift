import Foundation

public struct GPXExporter {
    private let heartRateName = "heart_rate"

    public init() {}

    public func export(
        workout: WorkoutSummary,
        locations: [RouteLocation]
    ) throws -> String {
        try export(
            workout: workout,
            data: WorkoutExportData(locations: locations)
        )
    }

    public func export(
        workout: WorkoutSummary,
        data: WorkoutExportData
    ) throws -> String {
        guard !data.locations.isEmpty
            || workout.distanceMeters > 0
            || workout.durationSeconds > 0
            || !data.metrics.isEmpty else {
            throw WorkoutSyncError.noRoute
        }

        let heartRate = data.metrics.first { $0.name == heartRateName }
        let heartRateSamples = (heartRate?.samples ?? []).sorted {
            $0.startDate < $1.startDate
        }
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(
            #"<gpx version="1.1" creator="RunningPageSync" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" xmlns:rps="https://github.com/lipeng31/running_page/xmlschemas/WorkoutExtension/v1">"#
        )
        lines.append("  <metadata>")
        lines.append("    <time>\(format(workout.startDate))</time>")
        lines.append("  </metadata>")
        appendWorkoutExtensions(
            to: &lines,
            workout: workout,
            data: data,
            heartRate: heartRate
        )
        lines.append("  <trk>")
        lines.append("    <name>\(escapeXML(workout.name))</name>")
        lines.append("    <type>running</type>")
        if !data.locations.isEmpty {
            lines.append("    <trkseg>")
            for location in data.locations {
                appendTrackPoint(
                    to: &lines,
                    location: location,
                    heartRate: nearestSampleValue(
                        at: location.timestamp,
                        sortedSamples: heartRateSamples
                    )
                )
            }
            lines.append("    </trkseg>")
        }
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    private func appendWorkoutExtensions(
        to lines: inout [String],
        workout: WorkoutSummary,
        data: WorkoutExportData,
        heartRate: WorkoutMetric?
    ) {
        let elapsedTime = max(0, workout.endDate.timeIntervalSince(workout.startDate))
        let averageSpeed = workout.durationSeconds > 0
            ? workout.distanceMeters / workout.durationSeconds
            : 0

        lines.append("  <extensions>")
        lines.append("    <rps:workout_id>\(escapeXML(workout.id))</rps:workout_id>")
        lines.append("    <rps:start_time>\(format(workout.startDate))</rps:start_time>")
        lines.append("    <rps:end_time>\(format(workout.endDate))</rps:end_time>")
        lines.append("    <rps:distance>\(number(workout.distanceMeters))</rps:distance>")
        lines.append("    <rps:moving_time>\(number(workout.durationSeconds))</rps:moving_time>")
        lines.append("    <rps:elapsed_time>\(number(elapsedTime))</rps:elapsed_time>")
        lines.append("    <rps:average_speed>\(number(averageSpeed))</rps:average_speed>")
        if let averageHeartRate = heartRate?.averageValue {
            lines.append("    <rps:average_hr>\(number(averageHeartRate))</rps:average_hr>")
        }
        appendMetadata(to: &lines, entries: data.metadata, indent: "    ")
        appendEvents(to: &lines, events: data.events)
        appendMetrics(to: &lines, metrics: data.metrics)
        lines.append("  </extensions>")
    }

    private func appendMetadata(
        to lines: inout [String],
        entries: [WorkoutMetadataEntry],
        indent: String
    ) {
        guard !entries.isEmpty else {
            return
        }
        lines.append("\(indent)<rps:metadata>")
        for entry in entries.sorted(by: { $0.key < $1.key }) {
            lines.append(
                "\(indent)  <rps:item key=\"\(escapeXML(entry.key))\">\(escapeXML(entry.value))</rps:item>"
            )
        }
        lines.append("\(indent)</rps:metadata>")
    }

    private func appendEvents(
        to lines: inout [String],
        events: [WorkoutEventRecord]
    ) {
        guard !events.isEmpty else {
            return
        }
        lines.append("    <rps:events>")
        for event in events {
            let attributes = [
                "type=\"\(event.type)\"",
                "start=\"\(format(event.startDate))\"",
                "end=\"\(format(event.endDate))\""
            ].joined(separator: " ")
            if event.metadata.isEmpty {
                lines.append("      <rps:event \(attributes) />")
            } else {
                lines.append("      <rps:event \(attributes)>")
                appendMetadata(to: &lines, entries: event.metadata, indent: "        ")
                lines.append("      </rps:event>")
            }
        }
        lines.append("    </rps:events>")
    }

    private func appendMetrics(
        to lines: inout [String],
        metrics: [WorkoutMetric]
    ) {
        guard !metrics.isEmpty else {
            return
        }
        lines.append("    <rps:metrics>")
        for metric in metrics.sorted(by: { $0.name < $1.name }) {
            lines.append(
                "      <rps:metric identifier=\"\(escapeXML(metric.identifier))\" name=\"\(escapeXML(metric.name))\" unit=\"\(escapeXML(metric.unit))\">"
            )
            appendMetricSummary(to: &lines, metric: metric)
            for sample in metric.samples.sorted(by: { $0.startDate < $1.startDate }) {
                appendMetricSample(to: &lines, sample: sample)
            }
            lines.append("      </rps:metric>")
        }
        lines.append("    </rps:metrics>")
    }

    private func appendMetricSummary(
        to lines: inout [String],
        metric: WorkoutMetric
    ) {
        var attributes: [String] = []
        if let value = metric.averageValue {
            attributes.append("average=\"\(number(value))\"")
        }
        if let value = metric.minimumValue {
            attributes.append("minimum=\"\(number(value))\"")
        }
        if let value = metric.maximumValue {
            attributes.append("maximum=\"\(number(value))\"")
        }
        if let value = metric.totalValue {
            attributes.append("total=\"\(number(value))\"")
        }
        if !attributes.isEmpty {
            lines.append("        <rps:summary \(attributes.joined(separator: " ")) />")
        }
    }

    private func appendMetricSample(
        to lines: inout [String],
        sample: WorkoutMetricSample
    ) {
        var attributes = [
            "start=\"\(format(sample.startDate))\"",
            "end=\"\(format(sample.endDate))\"",
            "value=\"\(number(sample.value))\""
        ]
        if let source = sample.source {
            attributes.append("source=\"\(escapeXML(source))\"")
        }
        if sample.metadata.isEmpty {
            lines.append("        <rps:sample \(attributes.joined(separator: " ")) />")
        } else {
            lines.append("        <rps:sample \(attributes.joined(separator: " "))>")
            appendMetadata(to: &lines, entries: sample.metadata, indent: "          ")
            lines.append("        </rps:sample>")
        }
    }

    private func appendTrackPoint(
        to lines: inout [String],
        location: RouteLocation,
        heartRate: Double?
    ) {
        lines.append(
            String(
                format: #"      <trkpt lat="%.7f" lon="%.7f">"#,
                locale: Locale(identifier: "en_US_POSIX"),
                location.latitude,
                location.longitude
            )
        )
        lines.append("        <ele>\(fixed(location.altitude, decimals: 2))</ele>")
        lines.append("        <time>\(format(location.timestamp))</time>")

        let hasLocationDetails = location.horizontalAccuracy != nil
            || location.verticalAccuracy != nil
            || location.speed != nil
            || location.speedAccuracy != nil
            || location.course != nil
            || location.courseAccuracy != nil
            || location.ellipsoidalAltitude != nil
        if heartRate != nil || hasLocationDetails {
            lines.append("        <extensions>")
            if let heartRate {
                lines.append("          <gpxtpx:TrackPointExtension>")
                lines.append("            <gpxtpx:hr>\(Int(heartRate.rounded()))</gpxtpx:hr>")
                lines.append("          </gpxtpx:TrackPointExtension>")
            }
            if hasLocationDetails {
                lines.append("          <rps:LocationExtension>")
                appendOptionalLocationValue(
                    to: &lines,
                    name: "horizontal_accuracy",
                    value: location.horizontalAccuracy
                )
                appendOptionalLocationValue(
                    to: &lines,
                    name: "vertical_accuracy",
                    value: location.verticalAccuracy
                )
                appendOptionalLocationValue(to: &lines, name: "speed", value: location.speed)
                appendOptionalLocationValue(
                    to: &lines,
                    name: "speed_accuracy",
                    value: location.speedAccuracy
                )
                appendOptionalLocationValue(to: &lines, name: "course", value: location.course)
                appendOptionalLocationValue(
                    to: &lines,
                    name: "course_accuracy",
                    value: location.courseAccuracy
                )
                appendOptionalLocationValue(
                    to: &lines,
                    name: "ellipsoidal_altitude",
                    value: location.ellipsoidalAltitude
                )
                lines.append("          </rps:LocationExtension>")
            }
            lines.append("        </extensions>")
        }
        lines.append("      </trkpt>")
    }

    private func appendOptionalLocationValue(
        to lines: inout [String],
        name: String,
        value: Double?
    ) {
        guard let value, value >= 0 else {
            return
        }
        lines.append("            <rps:\(name)>\(number(value))</rps:\(name)>")
    }

    private func nearestSampleValue(
        at date: Date,
        sortedSamples: [WorkoutMetricSample]
    ) -> Double? {
        guard !sortedSamples.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = sortedSamples.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if sortedSamples[middle].startDate < date {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let candidateIndices = [lowerBound - 1, lowerBound]
        let candidate = candidateIndices
            .filter { sortedSamples.indices.contains($0) }
            .map { sortedSamples[$0] }
            .min { sampleDistance(from: date, to: $0) < sampleDistance(from: date, to: $1) }

        guard let candidate,
              sampleDistance(from: date, to: candidate) <= 30 else {
            return nil
        }
        return candidate.value
    }

    private func sampleDistance(
        from date: Date,
        to sample: WorkoutMetricSample
    ) -> TimeInterval {
        if date < sample.startDate {
            return sample.startDate.timeIntervalSince(date)
        }
        if date > sample.endDate {
            return date.timeIntervalSince(sample.endDate)
        }
        return 0
    }

    private func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func number(_ value: Double) -> String {
        fixed(value, decimals: 6)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func fixed(_ value: Double, decimals: Int) -> String {
        String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            decimals,
            value
        )
    }

    private func escapeXML(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
