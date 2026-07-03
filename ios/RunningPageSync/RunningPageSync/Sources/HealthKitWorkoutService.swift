import CoreLocation
import HealthKit
import RunningPageSyncCore

enum HealthAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case unavailable
    case failed(String)
}

@MainActor
final class HealthKitWorkoutService: ObservableObject {
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var authorizationState: HealthAuthorizationState = .notDetermined

    private let healthStore = HKHealthStore()
    private var workoutByID: [String: HKWorkout] = [:]

    func authorizeAndLoad() async {
        do {
            try await requestAuthorization()
            try await loadRecentRunningWorkouts(limit: 30)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            throw WorkoutSyncError.healthKitUnavailable
        }

        let readTypes: Set<HKObjectType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

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
        do {
            try await loadRecentRunningWorkouts(limit: 30)
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
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                durationSeconds: workout.duration,
                hasRoute: true
            )
        }
        authorizationState = .authorized
    }

    func loadRouteLocations(for workout: WorkoutSummary) async throws -> [RouteLocation] {
        guard let hkWorkout = workoutByID[workout.id] else {
            throw WorkoutSyncError.noRoute
        }

        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: hkWorkout)
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

        var output: [RouteLocation] = []
        for route in routes {
            let points = try await readLocations(from: route)
            output.append(contentsOf: points)
        }
        guard !output.isEmpty else {
            throw WorkoutSyncError.noRoute
        }
        return output.sorted { $0.timestamp < $1.timestamp }
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
                            timestamp: location.timestamp
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

    private func workoutName(for workout: HKWorkout) -> String {
        if let name = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
           !name.isEmpty {
            return name
        }
        return "Apple Workout Run"
    }
}
