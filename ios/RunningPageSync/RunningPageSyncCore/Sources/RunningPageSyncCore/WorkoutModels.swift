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
    public let horizontalAccuracy: Double?
    public let verticalAccuracy: Double?
    public let speed: Double?
    public let speedAccuracy: Double?
    public let course: Double?
    public let courseAccuracy: Double?
    public let ellipsoidalAltitude: Double?

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        speedAccuracy: Double? = nil,
        course: Double? = nil,
        courseAccuracy: Double? = nil,
        ellipsoidalAltitude: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
        self.courseAccuracy = courseAccuracy
        self.ellipsoidalAltitude = ellipsoidalAltitude
    }
}

public struct WorkoutMetadataEntry: Hashable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct WorkoutMetricSample: Hashable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let value: Double
    public let source: String?
    public let metadata: [WorkoutMetadataEntry]

    public init(
        startDate: Date,
        endDate: Date,
        value: Double,
        source: String? = nil,
        metadata: [WorkoutMetadataEntry] = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.source = source
        self.metadata = metadata
    }
}

public struct WorkoutMetric: Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let unit: String
    public let samples: [WorkoutMetricSample]
    public let averageValue: Double?
    public let minimumValue: Double?
    public let maximumValue: Double?
    public let totalValue: Double?

    public init(
        identifier: String,
        name: String,
        unit: String,
        samples: [WorkoutMetricSample],
        averageValue: Double? = nil,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        totalValue: Double? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.unit = unit
        self.samples = samples
        self.averageValue = averageValue
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.totalValue = totalValue
    }
}

public struct WorkoutEventRecord: Hashable, Sendable {
    public let type: Int
    public let startDate: Date
    public let endDate: Date
    public let metadata: [WorkoutMetadataEntry]

    public init(
        type: Int,
        startDate: Date,
        endDate: Date,
        metadata: [WorkoutMetadataEntry] = []
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }
}

public struct WorkoutExportData: Sendable {
    public let locations: [RouteLocation]
    public let metrics: [WorkoutMetric]
    public let metadata: [WorkoutMetadataEntry]
    public let events: [WorkoutEventRecord]

    public init(
        locations: [RouteLocation],
        metrics: [WorkoutMetric] = [],
        metadata: [WorkoutMetadataEntry] = [],
        events: [WorkoutEventRecord] = []
    ) {
        self.locations = locations
        self.metrics = metrics
        self.metadata = metadata
        self.events = events
    }
}

public enum WorkoutSyncError: Error, Equatable, LocalizedError {
    case healthKitUnavailable
    case authorizationDenied
    case noRoute
    case incompleteSettings
    case missingToken
    case activityInventoryUnavailable
    case invalidArchiveEntry
    case archiveTooLarge
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
        case .activityInventoryUnavailable:
            "The current running page activity inventory could not be loaded."
        case .invalidArchiveEntry:
            "The GPX archive contains an invalid file name."
        case .archiveTooLarge:
            "The GPX archive is too large to upload."
        case let .invalidGitHubResponse(statusCode):
            "GitHub request failed with status \(statusCode)."
        }
    }
}
