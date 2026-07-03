import Foundation

public struct GPXExporter {
    public init() {}

    public func export(
        workout: WorkoutSummary,
        locations: [RouteLocation]
    ) throws -> String {
        guard !locations.isEmpty else {
            throw WorkoutSyncError.noRoute
        }

        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<gpx version="1.1" creator="RunningPageSync" xmlns="http://www.topografix.com/GPX/1/1">"#)
        lines.append("  <metadata>")
        lines.append("    <time>\(format(workout.startDate))</time>")
        lines.append("  </metadata>")
        lines.append("  <trk>")
        lines.append("    <name>\(escapeXML(workout.name))</name>")
        lines.append("    <type>running</type>")
        lines.append("    <trkseg>")

        for location in locations {
            lines.append(
                String(
                    format: #"      <trkpt lat="%.7f" lon="%.7f">"#,
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.latitude,
                    location.longitude
                )
            )
            lines.append(
                String(
                    format: "        <ele>%.2f</ele>",
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.altitude
                )
            )
            lines.append("        <time>\(format(location.timestamp))</time>")
            lines.append("      </trkpt>")
        }

        lines.append("    </trkseg>")
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    private func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
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
