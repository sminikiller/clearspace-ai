import Foundation

/// Periodo trascorso lontano dal luogo abituale, ricostruito da date e posizioni delle foto.
struct Trip: Identifiable, Hashable, Sendable {
    let id: UUID
    var start: Date
    var end: Date
    var itemIDs: [UUID]
    var latitude: Double
    var longitude: Double
    var bytes: Int64
    var distanceFromHomeKm: Double

    var dayCount: Int {
        max(1, Int((end.timeIntervalSince(start) / 86_400).rounded(.up)))
    }
}

/// Modalità viaggio: raggruppa i contenuti per periodo e posizione, quando la posizione è disponibile.
/// Tutto il calcolo avviene sul dispositivo.
enum TripDetector {

    static func distanceKm(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        let earthRadius = 6_371.0
        let phi1 = latitude1 * Double.pi / 180
        let phi2 = latitude2 * Double.pi / 180
        let deltaPhi = (latitude2 - latitude1) * Double.pi / 180
        let deltaLambda = (longitude2 - longitude1) * Double.pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// Luogo abituale: la zona (cella di circa 20 km) in cui è stata scattata la maggior parte delle foto.
    static func homeLocation(of items: [IndexedItem]) -> (latitude: Double, longitude: Double)? {
        struct Cell {
            var count = 0
            var latitudeSum = 0.0
            var longitudeSum = 0.0
        }
        var cells: [String: Cell] = [:]
        for item in items {
            guard let latitude = item.latitude, let longitude = item.longitude else { continue }
            let key = "\(Int((latitude * 5).rounded())):\(Int((longitude * 5).rounded()))"
            var cell = cells[key] ?? Cell()
            cell.count += 1
            cell.latitudeSum += latitude
            cell.longitudeSum += longitude
            cells[key] = cell
        }
        guard let best = cells.values.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        return (best.latitudeSum / Double(best.count), best.longitudeSum / Double(best.count))
    }

    static func detect(
        items: [IndexedItem],
        minimumItems: Int = 12,
        minimumDistanceKm: Double = 60,
        maximumGap: TimeInterval = 3 * 86_400
    ) -> [Trip] {
        guard let home = homeLocation(of: items) else { return [] }

        let dated = items
            .filter { $0.createdAt != nil }
            .sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }

        struct Run {
            var start: Date
            var end: Date
            var count = 0
            var latitudeSum = 0.0
            var longitudeSum = 0.0
            var maxDistance = 0.0
        }

        var runs: [Run] = []
        var current: Run?

        for item in dated {
            guard let date = item.createdAt, let latitude = item.latitude, let longitude = item.longitude else {
                continue
            }
            let distance = distanceKm(
                latitude1: home.latitude, longitude1: home.longitude,
                latitude2: latitude, longitude2: longitude
            )
            let isAway = distance >= minimumDistanceKm

            if isAway {
                if var run = current, date.timeIntervalSince(run.end) <= maximumGap {
                    run.end = date
                    run.count += 1
                    run.latitudeSum += latitude
                    run.longitudeSum += longitude
                    run.maxDistance = max(run.maxDistance, distance)
                    current = run
                } else {
                    if let finished = current { runs.append(finished) }
                    var run = Run(start: date, end: date)
                    run.count = 1
                    run.latitudeSum = latitude
                    run.longitudeSum = longitude
                    run.maxDistance = distance
                    current = run
                }
            } else if let finished = current {
                // Una foto scattata nella zona abituale chiude il viaggio in corso.
                runs.append(finished)
                current = nil
            }
        }
        if let finished = current { runs.append(finished) }

        var trips: [Trip] = []
        for run in runs where run.count >= minimumItems {
            // Nel viaggio rientrano tutti i contenuti del periodo, anche quelli senza posizione.
            let members = dated.filter { item in
                guard let date = item.createdAt else { return false }
                return date >= run.start && date <= run.end
            }
            trips.append(Trip(
                id: UUID(),
                start: run.start,
                end: run.end,
                itemIDs: members.map { $0.id },
                latitude: run.latitudeSum / Double(run.count),
                longitude: run.longitudeSum / Double(run.count),
                bytes: members.reduce(0) { $0 + $1.bytes },
                distanceFromHomeKm: run.maxDistance
            ))
        }
        return trips.sorted { $0.start > $1.start }
    }
}
