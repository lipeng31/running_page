import Foundation

public enum RouteLocationSelector {
    public static func select(
        segments: [[RouteLocation]],
        expectedDistanceMeters: Double
    ) -> [RouteLocation] {
        let candidates = segments
            .map { $0.sorted { $0.timestamp < $1.timestamp } }
            .filter { !$0.isEmpty }

        guard candidates.count > 1 else {
            return candidates.first ?? []
        }

        var components: [[Int]] = []
        var visited = Set<Int>()

        for startIndex in candidates.indices where !visited.contains(startIndex) {
            var component: [Int] = []
            var pending = [startIndex]
            visited.insert(startIndex)

            while let current = pending.popLast() {
                component.append(current)
                for other in candidates.indices where !visited.contains(other) {
                    if substantiallyOverlaps(candidates[current], candidates[other]) {
                        visited.insert(other)
                        pending.append(other)
                    }
                }
            }
            components.append(component)
        }

        let selected = components.compactMap { component -> [RouteLocation]? in
            component
                .map { candidates[$0] }
                .min {
                    quality(of: $0, expectedDistanceMeters: expectedDistanceMeters)
                        < quality(of: $1, expectedDistanceMeters: expectedDistanceMeters)
                }
        }

        return selected
            .flatMap { $0 }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func substantiallyOverlaps(
        _ lhs: [RouteLocation],
        _ rhs: [RouteLocation]
    ) -> Bool {
        guard let lhsStart = lhs.first?.timestamp,
              let lhsEnd = lhs.last?.timestamp,
              let rhsStart = rhs.first?.timestamp,
              let rhsEnd = rhs.last?.timestamp else {
            return false
        }

        let overlapStart = max(lhsStart, rhsStart)
        let overlapEnd = min(lhsEnd, rhsEnd)
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        guard overlap > 5 else {
            return false
        }

        let shorterDuration = min(
            lhsEnd.timeIntervalSince(lhsStart),
            rhsEnd.timeIntervalSince(rhsStart)
        )
        return shorterDuration <= 0 || overlap / shorterDuration >= 0.25
    }

    private static func quality(
        of locations: [RouteLocation],
        expectedDistanceMeters: Double
    ) -> RouteQuality {
        let steps = zip(locations, locations.dropFirst()).map { previous, current in
            let distance = haversineDistance(from: previous, to: current)
            let duration = current.timestamp.timeIntervalSince(previous.timestamp)
            let implausible = distance > 100 && (duration <= 0 || distance / duration > 15)
            return (distance: distance, implausible: implausible)
        }
        let routeDistance = steps.reduce(0.0) { $0 + $1.distance }
        let implausibleFraction = steps.isEmpty
            ? 0
            : Double(steps.filter { $0.implausible }.count) / Double(steps.count)
        let distanceError = expectedDistanceMeters > 0
            ? abs(routeDistance - expectedDistanceMeters) / expectedDistanceMeters
            : 0
        let duration = max(
            0,
            (locations.last?.timestamp ?? .distantPast)
                .timeIntervalSince(locations.first?.timestamp ?? .distantPast)
        )
        let validAccuracies = locations.compactMap(\.horizontalAccuracy).filter { $0 >= 0 }
        let averageAccuracy = validAccuracies.isEmpty
            ? Double.greatestFiniteMagnitude
            : validAccuracies.reduce(0, +) / Double(validAccuracies.count)

        return RouteQuality(
            implausibleFraction: implausibleFraction,
            distanceError: distanceError,
            negativeDuration: -duration,
            averageAccuracy: averageAccuracy,
            negativePointCount: -locations.count
        )
    }

    private static func haversineDistance(
        from lhs: RouteLocation,
        to rhs: RouteLocation
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lhsLatitude = lhs.latitude * .pi / 180
        let rhsLatitude = rhs.latitude * .pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let value = pow(sin(latitudeDelta / 2), 2)
            + cos(lhsLatitude) * cos(rhsLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 2 * earthRadius * asin(min(1, sqrt(value)))
    }
}

private struct RouteQuality: Comparable {
    let implausibleFraction: Double
    let distanceError: Double
    let negativeDuration: TimeInterval
    let averageAccuracy: Double
    let negativePointCount: Int

    static func < (lhs: RouteQuality, rhs: RouteQuality) -> Bool {
        if lhs.implausibleFraction != rhs.implausibleFraction {
            return lhs.implausibleFraction < rhs.implausibleFraction
        }
        if lhs.distanceError != rhs.distanceError {
            return lhs.distanceError < rhs.distanceError
        }
        if lhs.negativeDuration != rhs.negativeDuration {
            return lhs.negativeDuration < rhs.negativeDuration
        }
        if lhs.averageAccuracy != rhs.averageAccuracy {
            return lhs.averageAccuracy < rhs.averageAccuracy
        }
        return lhs.negativePointCount < rhs.negativePointCount
    }
}
