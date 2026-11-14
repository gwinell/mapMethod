import Foundation
import SwiftData

struct MapPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct MapRing: Codable, Hashable {
    var points: [MapPoint]
    var isHole: Bool
}

struct MapOutline: Codable, Hashable {
    var rings: [MapRing]
    /// The outline is projected into a coordinate system whose longer side is 1.
    var width: Double
    var height: Double
    var sourceName: String
    var source: String

    var area: Double {
        rings.reduce(0) { total, ring in
            let value = abs(Self.signedArea(ring.points))
            return total + (ring.isHole ? -value : value)
        }
    }

    func contains(_ point: MapPoint) -> Bool {
        let inOuter = rings.contains { !$0.isHole && Self.contains(point, in: $0.points) }
        guard inOuter else { return false }
        return !rings.contains { $0.isHole && Self.contains(point, in: $0.points) }
    }

    private static func contains(_ point: MapPoint, in polygon: [MapPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            let crosses = (current.y > point.y) != (previous.y > point.y)
            if crosses {
                let crossingX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < crossingX { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }

    static func signedArea(_ points: [MapPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return sum / 2
    }

    static func fromGeographicRings(_ rings: [(points: [GeoCoordinate], isHole: Bool)], name: String) -> MapOutline? {
        let validRings = rings.filter { $0.points.count >= 3 }
        let allPoints = validRings.flatMap(\.points)
        guard !allPoints.isEmpty else { return nil }

        let meanLatitude = allPoints.map(\.latitude).reduce(0, +) / Double(allPoints.count)
        let longitudeScale = max(0.05, cos(meanLatitude * .pi / 180))
        let projected = validRings.map { ring in
            (ring: ring, points: ring.points.map { MapPoint(x: $0.longitude * longitudeScale, y: -$0.latitude) })
        }
        let minX = projected.flatMap { $0.points.map(\.x) }.min() ?? 0
        let maxX = projected.flatMap { $0.points.map(\.x) }.max() ?? 1
        let minY = projected.flatMap { $0.points.map(\.y) }.min() ?? 0
        let maxY = projected.flatMap { $0.points.map(\.y) }.max() ?? 1
        let rawWidth = max(maxX - minX, 0.000_001)
        let rawHeight = max(maxY - minY, 0.000_001)
        let scale = 1 / max(rawWidth, rawHeight)
        let normalized = projected.map { item in
            MapRing(
                points: item.points.map { MapPoint(x: ($0.x - minX) * scale, y: ($0.y - minY) * scale) },
                isHole: item.ring.isHole
            )
        }
        return MapOutline(
            rings: normalized,
            width: rawWidth * scale,
            height: rawHeight * scale,
            sourceName: name,
            source: "OpenStreetMap"
        )
    }

    static func fromDrawing(points: [MapPoint], canvasAspectRatio: Double) -> MapOutline? {
        guard points.count >= 3 else { return nil }
        let aspect = max(canvasAspectRatio, 0.1)
        let scaled = points.map { MapPoint(x: $0.x * aspect, y: $0.y) }
        let minX = scaled.map(\.x).min() ?? 0
        let maxX = scaled.map(\.x).max() ?? 1
        let minY = scaled.map(\.y).min() ?? 0
        let maxY = scaled.map(\.y).max() ?? 1
        let rawWidth = max(maxX - minX, 0.000_001)
        let rawHeight = max(maxY - minY, 0.000_001)
        let scale = 1 / max(rawWidth, rawHeight)
        let normalized = scaled.map { MapPoint(x: ($0.x - minX) * scale, y: ($0.y - minY) * scale) }
        return MapOutline(
            rings: [MapRing(points: normalized, isHole: false)],
            width: rawWidth * scale,
            height: rawHeight * scale,
            sourceName: "Мой контур",
            source: "Нарисовано"
        )
    }
}

struct GeoCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

struct SavingsCell: Codable, Hashable, Identifiable {
    var id: String
    var x: Double
    var y: Double
    var side: Double
    var valueMinorUnits: Int64
    var filledAt: Date?

    init(id: String = UUID().uuidString, x: Double, y: Double, side: Double = 0.02, valueMinorUnits: Int64, filledAt: Date? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.side = side
        self.valueMinorUnits = valueMinorUnits
        self.filledAt = filledAt
    }
}

struct ContributionEvent: Codable, Hashable, Identifiable {
    var id: String
    var cellID: String
    var valueMinorUnits: Int64
    var isFilled: Bool
    var happenedAt: Date

    init(cellID: String, valueMinorUnits: Int64, isFilled: Bool, happenedAt: Date = .now) {
        self.id = UUID().uuidString
        self.cellID = cellID
        self.valueMinorUnits = valueMinorUnits
        self.isFilled = isFilled
        self.happenedAt = happenedAt
    }
}

struct SavingsGoalDocument: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var targetMinorUnits: Int64
    var baseCellMinorUnits: Int64
    var currencyCode: String
    var outline: MapOutline
    var cells: [SavingsCell]
    var events: [ContributionEvent]
    var createdAt: Date
    var updatedAt: Date

    var savedMinorUnits: Int64 {
        cells.reduce(0) { $0 + ($1.filledAt == nil ? 0 : $1.valueMinorUnits) }
    }

    var progress: Double {
        guard targetMinorUnits > 0 else { return 0 }
        return min(1, Double(savedMinorUnits) / Double(targetMinorUnits))
    }
}

@Model
final class SavingsGoal {
    var id: String = UUID().uuidString
    var title: String = ""
    var targetMinorUnits: Int64 = 0
    var baseCellMinorUnits: Int64 = 0
    var currencyCode: String = "USD"
    var outlineJSON: String = ""
    var cellsJSON: String = "[]"
    var eventsJSON: String = "[]"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(document: SavingsGoalDocument) {
        self.id = document.id
        self.title = document.title
        self.targetMinorUnits = document.targetMinorUnits
        self.baseCellMinorUnits = document.baseCellMinorUnits
        self.currencyCode = document.currencyCode
        self.outlineJSON = Self.encode(document.outline) ?? ""
        self.cellsJSON = Self.encode(document.cells) ?? "[]"
        self.eventsJSON = Self.encode(document.events) ?? "[]"
        self.createdAt = document.createdAt
        self.updatedAt = document.updatedAt
    }

    var document: SavingsGoalDocument? {
        guard let outline = Self.decode(MapOutline.self, from: outlineJSON),
              let cells = Self.decode([SavingsCell].self, from: cellsJSON),
              let events = Self.decode([ContributionEvent].self, from: eventsJSON) else { return nil }
        return SavingsGoalDocument(
            id: id,
            title: title,
            targetMinorUnits: targetMinorUnits,
            baseCellMinorUnits: baseCellMinorUnits,
            currencyCode: currencyCode,
            outline: outline,
            cells: cells,
            events: events,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(cells: [SavingsCell], events: [ContributionEvent], at date: Date = .now) {
        cellsJSON = Self.encode(cells) ?? "[]"
        eventsJSON = Self.encode(events) ?? "[]"
        updatedAt = date
    }

    private static func encode<Value: Encodable>(_ value: Value) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from string: String) -> Value? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum CurrencyAmount {
    static func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }

    static func factor(for currencyCode: String) -> Int64 {
        Int64(pow(10.0, Double(fractionDigits(for: currencyCode))))
    }

    static func parse(_ input: String, currencyCode: String) -> Int64? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else { return nil }
        var scaled = amount * Decimal(factor(for: currencyCode))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func format(_ minorUnits: Int64, currencyCode: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        let amount = Decimal(minorUnits) / Decimal(factor(for: currencyCode))
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(minorUnits) \(currencyCode)"
    }

    static func suggestedBaseCellValue(target: Int64, currencyCode: String) -> Int64 {
        guard target > 1 else { return max(1, target) }
        let unit = factor(for: currencyCode)
        let desired = max(unit, target / 40)
        var candidates: [Int64] = []
        var power = unit
        while power <= target, power > 0 {
            for coefficient: Int64 in [1, 2, 5] where power <= Int64.max / coefficient {
                let value = coefficient * power
                if value <= target { candidates.append(value) }
            }
            if power > Int64.max / 10 { break }
            power *= 10
        }
        return candidates.min(by: { abs($0 - desired) < abs($1 - desired) }) ?? desired
    }
}

enum DenominationPlanner {
    static func cellValues(target: Int64, baseCell: Int64, currencyCode: String) -> [Int64] {
        guard target > 0, baseCell > 0 else { return [] }
        let base = min(baseCell, target)
        let baseCount = Int(target / base)
        let remainder = target % base
        guard baseCount < 4_000 else { return [] }

        var values = Array(repeating: base, count: baseCount)
        var remaining = remainder
        var denominations: Set<Int64> = [1]
        let unit = CurrencyAmount.factor(for: currencyCode)
        var power = unit
        while power < base, power > 0 {
            for coefficient: Int64 in [1, 2, 5] where power <= Int64.max / coefficient {
                let value = coefficient * power
                if value < base { denominations.insert(value) }
            }
            if power > Int64.max / 10 { break }
            power *= 10
        }

        for denomination in denominations.sorted(by: >) where denomination < base {
            let count = Int(remaining / denomination)
            guard values.count + count <= 4_000 else { return [] }
            if count > 0 { values.append(contentsOf: repeatElement(denomination, count: count)) }
            remaining %= denomination
        }
        if remaining > 0 {
            guard values.count + Int(remaining) <= 4_000 else { return [] }
            values.append(contentsOf: repeatElement(1, count: Int(remaining)))
        }
        return values
    }
}
