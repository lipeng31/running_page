import CoreLocation
import Foundation
import HealthKit
import RunningPageSyncCore

enum HealthAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case unavailable
    case failed(String)
}

private struct HealthMetricDefinition {
    let type: HKQuantityType
    let name: String
    let unitName: String
    let unit: HKUnit
}

@MainActor
final class HealthKitWorkoutService: ObservableObject {
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var authorizationState: HealthAuthorizationState = .notDetermined
    @Published private(set) var isLoading = false

    private let healthStore = HKHealthStore()
    private var workoutByID: [String: HKWorkout] = [:]

    func authorizeAndLoad() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await requestAuthorization()
            try await loadRecentRunningWorkouts(limit: HKObjectQueryNoLimit)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            throw WorkoutSyncError.healthKitUnavailable
        }

        var readTypes: Set<HKObjectType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        readTypes.formUnion(metricDefinitions.map(\.type))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard success else {
                    continuation.resume(throwing: WorkoutSyncError.authorizationDenied)
                    return
                }
                continuation.resume()
            }
        }

        authorizationState = .authorized
    }

    func loadRecentRunningWorkouts() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await loadRecentRunningWorkouts(limit: HKObjectQueryNoLimit)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func loadRecentRunningWorkouts(limit: Int) async throws {
        let sampleType = HKWorkoutType.workoutType()
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }

        let hkWorkouts = samples.compactMap { $0 as? HKWorkout }
        workoutByID = Dictionary(uniqueKeysWithValues: hkWorkouts.map { ($0.uuid.uuidString, $0) })
        workouts = hkWorkouts.map { workout in
            WorkoutSummary(
                id: workout.uuid.uuidString,
                name: workoutName(for: workout),
                startDate: workout.startDate,
                endDate: workout.endDate,
                distanceMeters: distance(for: workout),
                durationSeconds: workout.duration,
                hasRoute: true
            )
        }
        authorizationState = .authorized
    }

    func loadWorkoutData(for workout: WorkoutSummary) async throws -> WorkoutExportData {
        guard let hkWorkout = workoutByID[workout.id] else {
            throw WorkoutSyncError.noRoute
        }

        return WorkoutExportData(
            locations: (try? await loadRouteLocations(for: hkWorkout)) ?? [],
            metrics: await loadMetrics(for: hkWorkout),
            metadata: workoutMetadata(for: hkWorkout),
            events: workoutEvents(for: hkWorkout)
        )
    }

    func loadRouteRepairData(for workout: WorkoutSummary) async throws -> WorkoutExportData {
        guard let hkWorkout = workoutByID[workout.id] else {
            throw WorkoutSyncError.noRoute
        }
        let locations = try await loadRouteLocations(for: hkWorkout)
        return WorkoutExportData(
            locations: locations,
            metadata: workoutMetadata(for: hkWorkout),
            events: workoutEvents(for: hkWorkout)
        )
    }

    private func loadRouteLocations(for workout: HKWorkout) async throws -> [RouteLocation] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.compactMap { $0 as? HKWorkoutRoute } ?? [])
            }
            healthStore.execute(query)
        }

        var routeSegments: [[RouteLocation]] = []
        for route in routes {
            routeSegments.append(try await readLocations(from: route))
        }
        let output = RouteLocationSelector.select(
            segments: routeSegments,
            expectedDistanceMeters: distance(for: workout)
        )
        guard !output.isEmpty else {
            throw WorkoutSyncError.noRoute
        }
        return output
    }

    private func readLocations(from route: HKWorkoutRoute) async throws -> [RouteLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [RouteLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let locations {
                    collected.append(contentsOf: locations.map { location in
                        RouteLocation(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            altitude: location.altitude,
                            timestamp: location.timestamp,
                            horizontalAccuracy: location.horizontalAccuracy,
                            verticalAccuracy: location.verticalAccuracy,
                            speed: location.speed,
                            speedAccuracy: location.speedAccuracy,
                            course: location.course,
                            courseAccuracy: location.courseAccuracy,
                            ellipsoidalAltitude: location.ellipsoidalAltitude
                        )
                    })
                }
                if done {
                    continuation.resume(returning: collected)
                }
            }
            healthStore.execute(query)
        }
    }

    private func loadMetrics(for workout: HKWorkout) async -> [WorkoutMetric] {
        var output: [WorkoutMetric] = []
        for definition in metricDefinitions {
            let samples = (try? await loadQuantitySamples(
                type: definition.type,
                workout: workout
            )) ?? []
            let statistics = workout.statistics(for: definition.type)
            guard statistics != nil || !samples.isEmpty else {
                continue
            }
            output.append(
                workoutMetric(
                    definition: definition,
                    samples: samples,
                    statistics: statistics
                )
            )
        }
        return output
    }

    private func loadQuantitySamples(
        type: HKQuantityType,
        workout: HKWorkout
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
        return samples.compactMap { $0 as? HKQuantitySample }
    }

    private func workoutMetric(
        definition: HealthMetricDefinition,
        samples: [HKQuantitySample],
        statistics: HKStatistics?
    ) -> WorkoutMetric {
        let values = samples.map { $0.quantity.doubleValue(for: definition.unit) }
        let metricSamples = samples.map { sample in
            WorkoutMetricSample(
                startDate: sample.startDate,
                endDate: sample.endDate,
                value: sample.quantity.doubleValue(for: definition.unit),
                source: sample.sourceRevision.source.name,
                metadata: metadataEntries(from: sample.metadata)
            )
        }

        let isCumulative = definition.type.aggregationStyle == .cumulative
        let average = isCumulative
            ? nil
            : statistics?.averageQuantity()?.doubleValue(for: definition.unit)
                ?? average(of: values)
        let minimum = isCumulative
            ? nil
            : statistics?.minimumQuantity()?.doubleValue(for: definition.unit)
                ?? values.min()
        let maximum = isCumulative
            ? nil
            : statistics?.maximumQuantity()?.doubleValue(for: definition.unit)
                ?? values.max()
        let total = isCumulative
            ? statistics?.sumQuantity()?.doubleValue(for: definition.unit)
                ?? values.reduce(0, +)
            : nil

        return WorkoutMetric(
            identifier: definition.type.identifier,
            name: definition.name,
            unit: definition.unitName,
            samples: metricSamples,
            averageValue: average,
            minimumValue: minimum,
            maximumValue: maximum,
            totalValue: total
        )
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func workoutMetadata(for workout: HKWorkout) -> [WorkoutMetadataEntry] {
        var entries = metadataEntries(from: workout.metadata)
        let source = workout.sourceRevision
        entries.append(contentsOf: [
            WorkoutMetadataEntry(key: "source.name", value: source.source.name),
            WorkoutMetadataEntry(
                key: "source.bundle_identifier",
                value: source.source.bundleIdentifier
            ),
            WorkoutMetadataEntry(
                key: "workout.activity_type",
                value: String(workout.workoutActivityType.rawValue)
            )
        ])
        appendMetadata(&entries, key: "source.version", value: source.version)
        appendMetadata(&entries, key: "source.product_type", value: source.productType)
        let operatingSystem = source.operatingSystemVersion
        entries.append(
            WorkoutMetadataEntry(
                key: "source.operating_system",
                value: "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)"
            )
        )

        if let device = workout.device {
            appendMetadata(&entries, key: "device.name", value: device.name)
            appendMetadata(&entries, key: "device.manufacturer", value: device.manufacturer)
            appendMetadata(&entries, key: "device.model", value: device.model)
            appendMetadata(&entries, key: "device.hardware_version", value: device.hardwareVersion)
            appendMetadata(&entries, key: "device.firmware_version", value: device.firmwareVersion)
            appendMetadata(&entries, key: "device.software_version", value: device.softwareVersion)
            appendMetadata(&entries, key: "device.local_identifier", value: device.localIdentifier)
            appendMetadata(&entries, key: "device.udi_identifier", value: device.udiDeviceIdentifier)
        }
        return entries
    }

    private func workoutEvents(for workout: HKWorkout) -> [WorkoutEventRecord] {
        (workout.workoutEvents ?? []).map { event in
            WorkoutEventRecord(
                type: event.type.rawValue,
                startDate: event.dateInterval.start,
                endDate: event.dateInterval.end,
                metadata: metadataEntries(from: event.metadata)
            )
        }
    }

    private func metadataEntries(from metadata: [String: Any]?) -> [WorkoutMetadataEntry] {
        (metadata ?? [:]).map { key, value in
            WorkoutMetadataEntry(key: key, value: metadataValue(value))
        }
    }

    private func metadataValue(_ value: Any) -> String {
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        return String(describing: value)
    }

    private func appendMetadata(
        _ entries: inout [WorkoutMetadataEntry],
        key: String,
        value: String?
    ) {
        guard let value, !value.isEmpty else {
            return
        }
        entries.append(WorkoutMetadataEntry(key: key, value: value))
    }

    private func distance(for workout: HKWorkout) -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            return 0
        }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
    }

    private var metricDefinitions: [HealthMetricDefinition] {
        var definitions = [
            metric(.heartRate, name: "heart_rate", unitName: "bpm", unit: heartRateUnit),
            metric(
                .activeEnergyBurned,
                name: "active_energy",
                unitName: "kcal",
                unit: .kilocalorie()
            ),
            metric(
                .basalEnergyBurned,
                name: "basal_energy",
                unitName: "kcal",
                unit: .kilocalorie()
            ),
            metric(
                .distanceWalkingRunning,
                name: "distance_walking_running",
                unitName: "m",
                unit: .meter()
            ),
            metric(.stepCount, name: "step_count", unitName: "count", unit: .count()),
            metric(
                .flightsClimbed,
                name: "flights_climbed",
                unitName: "count",
                unit: .count()
            ),
            metric(.runningPower, name: "running_power", unitName: "W", unit: .watt()),
            metric(
                .runningSpeed,
                name: "running_speed",
                unitName: "m/s",
                unit: .meter().unitDivided(by: .second())
            ),
            metric(
                .runningGroundContactTime,
                name: "running_ground_contact_time",
                unitName: "ms",
                unit: .secondUnit(with: .milli)
            ),
            metric(
                .runningStrideLength,
                name: "running_stride_length",
                unitName: "m",
                unit: .meter()
            ),
            metric(
                .runningVerticalOscillation,
                name: "running_vertical_oscillation",
                unitName: "cm",
                unit: .meterUnit(with: .centi)
            ),
            metric(
                .physicalEffort,
                name: "physical_effort",
                unitName: "kcal/(kg*hr)",
                unit: HKUnit(from: "kcal/(kg*hr)")
            ),
            metric(
                .heartRateRecoveryOneMinute,
                name: "heart_rate_recovery_one_minute",
                unitName: "bpm",
                unit: heartRateUnit
            ),
            metric(
                .vo2Max,
                name: "vo2_max",
                unitName: "ml/(kg*min)",
                unit: HKUnit(from: "ml/(kg*min)")
            )
        ]
        if #available(iOS 18.0, *) {
            definitions.append(
                metric(
                    .estimatedWorkoutEffortScore,
                    name: "estimated_workout_effort_score",
                    unitName: "effort_score",
                    unit: .appleEffortScore()
                )
            )
            definitions.append(
                metric(
                    .workoutEffortScore,
                    name: "workout_effort_score",
                    unitName: "effort_score",
                    unit: .appleEffortScore()
                )
            )
        }
        return definitions
    }

    private var heartRateUnit: HKUnit {
        .count().unitDivided(by: .minute())
    }

    private func metric(
        _ identifier: HKQuantityTypeIdentifier,
        name: String,
        unitName: String,
        unit: HKUnit
    ) -> HealthMetricDefinition {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            preconditionFailure("Unsupported HealthKit metric: \(identifier.rawValue)")
        }
        return HealthMetricDefinition(type: type, name: name, unitName: unitName, unit: unit)
    }

    private func workoutName(for workout: HKWorkout) -> String {
        if let name = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
           !name.isEmpty {
            return name
        }
        return "Apple Workout Run"
    }
}
