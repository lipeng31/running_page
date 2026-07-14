import Foundation

public struct CachedActivity: Hashable, Sendable {
    public let startDate: Date
    public let distanceMeters: Double
    public let durationSeconds: TimeInterval

    public init(
        startDate: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval
    ) {
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

public struct ActivityInventoryClient: Sendable {
    public init() {}

    public func fetch(settings: GitHubSettings) async throws -> [CachedActivity] {
        let owner = settings.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = settings.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty,
              !repository.isEmpty,
              let baseURL = URL(string: "https://\(owner).github.io/\(repository)/") else {
            throw WorkoutSyncError.incompleteSettings
        }

        let manifestData = try await fetchData(
            from: baseURL.appending(path: ".vite/manifest.json")
        )
        let manifest = try JSONDecoder().decode(
            [String: ManifestEntry].self,
            from: manifestData
        )
        guard let activityFile = manifest["src/static/activities.json"]?.file else {
            throw WorkoutSyncError.activityInventoryUnavailable
        }

        let activityData = try await fetchData(from: baseURL.appending(path: activityFile))
        return try ActivityInventoryParser.parse(activityData)
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WorkoutSyncError.activityInventoryUnavailable
        }
        return data
    }
}

public enum ActivityMatcher {
    public static func missingWorkouts(
        _ workouts: [WorkoutSummary],
        cachedActivities: [CachedActivity]
    ) -> [WorkoutSummary] {
        workouts.filter { workout in
            !cachedActivities.contains { cached in
                matches(workout: workout, cached: cached)
            }
        }
    }

    private static func matches(
        workout: WorkoutSummary,
        cached: CachedActivity
    ) -> Bool {
        let startDifference = abs(
            workout.startDate.timeIntervalSince(cached.startDate)
        )
        guard startDifference <= 5 * 60 else {
            return false
        }

        if workout.distanceMeters > 100, cached.distanceMeters > 100 {
            let distanceTolerance = max(500, workout.distanceMeters * 0.08)
            return abs(workout.distanceMeters - cached.distanceMeters) <= distanceTolerance
        }

        let durationTolerance = max(180, workout.durationSeconds * 0.10)
        return abs(workout.durationSeconds - cached.durationSeconds) <= durationTolerance
    }
}

enum ActivityInventoryParser {
    static func parse(_ data: Data) throws -> [CachedActivity] {
        let payloads = try JSONDecoder().decode([ActivityPayload].self, from: data)
        return payloads.compactMap { payload in
            guard let startDate = parseDate(payload.startDate) else {
                return nil
            }
            return CachedActivity(
                startDate: startDate,
                distanceMeters: payload.distance,
                durationSeconds: parseDuration(payload.movingTime)
            )
        }
    }

    private static func parseDate(_ rawValue: String) -> Date? {
        var normalized = rawValue.replacingOccurrences(of: " ", with: "T")
        let timezoneSuffix = normalized.dropFirst(min(10, normalized.count))
        if !normalized.hasSuffix("Z"),
           !timezoneSuffix.contains("+"),
           !timezoneSuffix.contains("-") {
            normalized += "Z"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    private static func parseDuration(_ rawValue: String) -> TimeInterval {
        let dayParts = rawValue.components(separatedBy: " day, ")
        let daySeconds: Double
        let clockValue: String
        if dayParts.count == 2, let days = Double(dayParts[0]) {
            daySeconds = days * 86_400
            clockValue = dayParts[1]
        } else {
            daySeconds = 0
            clockValue = rawValue
        }

        let clockParts = clockValue.split(separator: ":").compactMap { Double($0) }
        guard clockParts.count == 3 else {
            return daySeconds
        }
        return daySeconds + clockParts[0] * 3_600 + clockParts[1] * 60 + clockParts[2]
    }
}

private struct ManifestEntry: Decodable {
    let file: String
}

private struct ActivityPayload: Decodable {
    let distance: Double
    let movingTime: String
    let startDate: String

    enum CodingKeys: String, CodingKey {
        case distance
        case movingTime = "moving_time"
        case startDate = "start_date"
    }
}
