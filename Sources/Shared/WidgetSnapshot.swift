import Foundation

struct WidgetCell: Codable, Hashable, Identifiable {
    var id: String
    var x: Double
    var y: Double
    var side: Double
    var valueMinorUnits: Int64
    var isFilled: Bool
}

struct WidgetMapPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct WidgetMapRing: Codable, Hashable {
    var points: [WidgetMapPoint]
    var isHole: Bool
}

struct WidgetMapOutline: Codable, Hashable {
    var rings: [WidgetMapRing]
    var width: Double
    var height: Double
    var sourceName: String
    var source: String
}

struct WidgetGoalSnapshot: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var targetMinorUnits: Int64
    var savedMinorUnits: Int64
    var currencyCode: String
    var outline: WidgetMapOutline
    var cells: [WidgetCell]
    var updatedAt: Date

    var progress: Double {
        guard targetMinorUnits > 0 else { return 0 }
        return min(1, Double(savedMinorUnits) / Double(targetMinorUnits))
    }

}

enum WidgetSnapshotStore {
    static let appGroup = "group.com.gwinell.mapmethod"
    private static let key = "widget.goal.snapshots"

    static func save(_ goals: [WidgetGoalSnapshot]) {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }

    static func load() -> [WidgetGoalSnapshot] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
              let goals = try? JSONDecoder().decode([WidgetGoalSnapshot].self, from: data) else { return [] }
        return goals.sorted { $0.updatedAt > $1.updatedAt }
    }
}
