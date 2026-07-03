import Foundation

public struct WorkoutSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let startDate: Date
    public let endDate: Date
    public let distanceMeters: Double
    public let durationSeconds: TimeInterval
    public let hasRoute: Bool

    public init(
        id: String,
        name: String,
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        hasRoute: Bool
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.hasRoute = hasRoute
    }
}

public struct RouteLocation: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
    }
}

public enum WorkoutSyncError: Error, Equatable, LocalizedError {
    case healthKitUnavailable
    case authorizationDenied
    case noRoute
    case incompleteSettings
    case missingToken
    case invalidGitHubResponse(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            "HealthKit is not available on this device."
        case .authorizationDenied:
            "Health access was not granted."
        case .noRoute:
            "The selected workout does not contain route points."
        case .incompleteSettings:
            "GitHub settings are incomplete."
        case .missingToken:
            "GitHub token is missing."
        case let .invalidGitHubResponse(statusCode):
            "GitHub request failed with status \(statusCode)."
        }
    }
}
