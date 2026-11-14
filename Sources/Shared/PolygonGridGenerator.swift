import Foundation

enum PolygonGridGenerator {
    private struct Candidate {
        var row: Int
        var column: Int
        var point: MapPoint
    }

    static func generate(outline: MapOutline, values: [Int64]) -> [SavingsCell] {
        let count = values.count
        guard count > 0, outline.area > 0, outline.width > 0, outline.height > 0 else { return [] }

        var pitch = sqrt(outline.area / Double(count)) * 0.94
        let smallestDimension = min(outline.width, outline.height)
        pitch = min(pitch, smallestDimension)
        var candidates: [Candidate] = []

        for _ in 0..<80 {
            candidates = gridCandidates(outline: outline, pitch: pitch)
            if candidates.count >= count { break }
            pitch *= 0.86
            if pitch < smallestDimension / 2_000 { break }
        }

        if candidates.count < count {
            candidates = fallbackCandidates(outline: outline, count: count)
        }

        let chosen = evenlySample(candidates, count: count)
        let sortedValues = values.sorted(by: >)
        let maximumValue = max(1, sortedValues.first ?? 1)
        return zip(chosen, sortedValues).map { candidate, value in
            let side = pitch * sqrt(Double(value) / Double(maximumValue))
            return SavingsCell(x: candidate.point.x, y: candidate.point.y, side: side, valueMinorUnits: value)
        }
    }

    private static func gridCandidates(outline: MapOutline, pitch: Double) -> [Candidate] {
        guard pitch > 0 else { return [] }
        let rows = max(1, Int(floor((outline.height - pitch) / pitch)) + 1)
        guard rows <= 100_000 else { return [] }
        var result: [Candidate] = []
        let half = pitch / 2
        for row in 0..<rows {
            let y = half + Double(row) * pitch
            let scanlineSets = [y - half + 0.000_000_001, y, y + half - 0.000_000_001]
                .map { scanlineIntervals(outline: outline, y: $0) }
            let safeIntervals = intersect(scanlineSets)
            var column = 0
            for interval in safeIntervals {
                let firstCenter = interval.lower + half
                let lastCenter = interval.upper - half
                guard firstCenter <= lastCenter else { continue }
                let count = Int(floor((lastCenter - firstCenter) / pitch)) + 1
                for offset in 0..<count {
                    let x = firstCenter + Double(offset) * pitch
                    let center = MapPoint(x: x, y: y)
                    guard isWholeSquareInside(center, side: pitch, outline: outline) else { continue }
                    result.append(Candidate(row: row, column: column, point: center))
                    column += 1
                }
                column += 1
            }
        }
        return result
    }

    private static func scanlineIntervals(outline: MapOutline, y: Double) -> [(lower: Double, upper: Double)] {
        var crossings: [Double] = []
        for ring in outline.rings where ring.points.count >= 3 {
            var previous = ring.points[ring.points.count - 1]
            for current in ring.points {
                if (current.y > y) != (previous.y > y) {
                    let x = current.x + (y - current.y) * (previous.x - current.x) / (previous.y - current.y)
                    crossings.append(x)
                }
                previous = current
            }
        }
        crossings.sort()
        guard crossings.count >= 2 else { return [] }
        return stride(from: 0, to: crossings.count - 1, by: 2).compactMap { index in
            let lower = crossings[index]
            let upper = crossings[index + 1]
            return upper > lower ? (lower, upper) : nil
        }
    }

    private static func intersect(_ intervalSets: [[(lower: Double, upper: Double)]]) -> [(lower: Double, upper: Double)] {
        guard var result = intervalSets.first else { return [] }
        for set in intervalSets.dropFirst() {
            var next: [(lower: Double, upper: Double)] = []
            for left in result {
                for right in set {
                    let lower = max(left.lower, right.lower)
                    let upper = min(left.upper, right.upper)
                    if upper > lower { next.append((lower, upper)) }
                }
            }
            result = next
            if result.isEmpty { break }
        }
        return result
    }

    private static func isWholeSquareInside(_ center: MapPoint, side: Double, outline: MapOutline) -> Bool {
        let half = side / 2
        let checks = [
            MapPoint(x: center.x - half, y: center.y - half),
            MapPoint(x: center.x, y: center.y - half),
            MapPoint(x: center.x + half, y: center.y - half),
            MapPoint(x: center.x - half, y: center.y),
            center,
            MapPoint(x: center.x + half, y: center.y),
            MapPoint(x: center.x - half, y: center.y + half),
            MapPoint(x: center.x, y: center.y + half),
            MapPoint(x: center.x + half, y: center.y + half)
        ]
        return checks.allSatisfy(outline.contains)
    }

    private static func evenlySample(_ candidates: [Candidate], count: Int) -> [Candidate] {
        guard candidates.count > count else { return candidates }
        let groupedRows = Dictionary(grouping: candidates, by: \.row)
        let rows = groupedRows.keys.sorted().compactMap { row in
            groupedRows[row].map { (row, $0.sorted { $0.column < $1.column }) }
        }
        let total = Double(candidates.count)
        var allocations: [(row: Int, cells: [Candidate], amount: Int, fraction: Double)] = rows.map { row, cells in
            let exact = Double(count) * Double(cells.count) / total
            let base = min(cells.count, Int(exact.rounded(.down)))
            return (row, cells, base, exact - Double(base))
        }
        var remaining = count - allocations.reduce(0) { $0 + $1.amount }
        for index in allocations.indices.sorted(by: { allocations[$0].fraction > allocations[$1].fraction }) where remaining > 0 {
            if allocations[index].amount < allocations[index].cells.count {
                allocations[index].amount += 1
                remaining -= 1
            }
        }
        if remaining > 0 {
            for index in allocations.indices where remaining > 0 {
                let room = allocations[index].cells.count - allocations[index].amount
                let addition = min(room, remaining)
                allocations[index].amount += addition
                remaining -= addition
            }
        }

        var selected: [Candidate] = []
        for row in allocations {
            guard row.amount > 0 else { continue }
            let sorted = row.cells.sorted { $0.column < $1.column }
            if row.amount == sorted.count {
                selected.append(contentsOf: sorted)
            } else {
                for index in 0..<row.amount {
                    let sourceIndex = min(sorted.count - 1, Int((Double(index) + 0.5) * Double(sorted.count) / Double(row.amount)))
                    selected.append(sorted[sourceIndex])
                }
            }
        }
        return Array(selected.prefix(count)).sorted { lhs, rhs in
            lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
        }
    }

    private static func fallbackCandidates(outline: MapOutline, count: Int) -> [Candidate] {
        let minDimension = min(outline.width, outline.height)
        let floorPitch = max(minDimension / 2_000, 0.000_001)
        var pitch = max(floorPitch, sqrt(outline.area / Double(max(count, 1))) * 0.45)
        var best: [Candidate] = []
        for _ in 0..<14 {
            let result = gridCandidates(outline: outline, pitch: pitch)
            if result.count >= count { return result }
            if result.count > best.count { best = result }
            guard pitch > floorPitch else { break }
            pitch = max(floorPitch, pitch * 0.7)
        }
        return best
    }
}
