import SwiftUI
import WidgetKit

struct MapMethodWidgetEntry: TimelineEntry {
    var date: Date
    var goal: WidgetGoalSnapshot?
}

struct MapMethodWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MapMethodWidgetEntry {
        MapMethodWidgetEntry(date: .now, goal: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MapMethodWidgetEntry) -> Void) {
        completion(MapMethodWidgetEntry(date: .now, goal: WidgetSnapshotStore.load().first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MapMethodWidgetEntry>) -> Void) {
        let entry = MapMethodWidgetEntry(date: .now, goal: WidgetSnapshotStore.load().first)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 12, to: .now) ?? .now.addingTimeInterval(43_200)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct MapMethodWidget: Widget {
    let kind = "MapMethod.Progress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MapMethodWidgetProvider()) { entry in
            MapMethodWidgetView(goal: entry.goal)
                .containerBackground(MapMethodPalette.quietSurface, for: .widget)
        }
        .configurationDisplayName("Карта накоплений")
        .description("Показывает клеточную карту и прогресс цели.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct MapMethodWidgetBundle: WidgetBundle {
    var body: some Widget {
        MapMethodWidget()
    }
}

private struct MapMethodWidgetView: View {
    var goal: WidgetGoalSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let goal {
            content(goal)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Создайте карту в MapMethod")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(_ goal: WidgetGoalSnapshot) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text(goal.title).font(.subheadline.weight(.medium)).lineLimit(1)
                WidgetMapArtwork(goal: goal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                progress(goal)
            }
            .padding(4)
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                titleAndAmount(goal)
                WidgetMapArtwork(goal: goal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                progress(goal)
            }
            .padding(8)
        default:
            HStack(spacing: 16) {
                WidgetMapArtwork(goal: goal)
                    .frame(width: 110)
                VStack(alignment: .leading, spacing: 8) {
                    titleAndAmount(goal)
                    progress(goal)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    private func titleAndAmount(_ goal: WidgetGoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goal.title)
                .font(.title3.weight(.medium))
                .lineLimit(1)
                Text("\(WidgetCurrencyFormat.format(goal.savedMinorUnits, currencyCode: goal.currencyCode)) из \(WidgetCurrencyFormat.format(goal.targetMinorUnits, currencyCode: goal.currencyCode))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func progress(_ goal: WidgetGoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: goal.progress).tint(MapMethodPalette.accent)
            HStack {
                Text("\(Int(goal.progress * 100))%")
                Spacer()
                Text("\(goal.cells.filter(\.isFilled).count)/\(goal.cells.count) клеток")
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetMapArtwork: View {
    var goal: WidgetGoalSnapshot

    var body: some View {
        GeometryReader { geometry in
            let projection = WidgetProjection(outline: goal.outline, size: geometry.size)
            Canvas { context, _ in
                var silhouette = Path()
                for ring in goal.outline.rings {
                    guard let first = ring.points.first else { continue }
                    silhouette.move(to: projection.point(WidgetMapPoint(x: first.x, y: first.y)))
                    for point in ring.points.dropFirst() {
                        silhouette.addLine(to: projection.point(WidgetMapPoint(x: point.x, y: point.y)))
                    }
                    silhouette.closeSubpath()
                }
                context.fill(silhouette, with: .color(Color.primary.opacity(0.04)), style: FillStyle(eoFill: true))
                for cell in goal.cells {
                    let rect = projection.rect(for: cell)
                    guard rect.width > 1 else { continue }
                    let radius = min(rect.width * 0.2, 7)
                    let path = Path(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), cornerSize: CGSize(width: radius, height: radius))
                    context.fill(path, with: .color(cell.isFilled ? MapMethodPalette.accent : MapMethodPalette.emptyCell))
                }
            }
        }
    }
}

private struct WidgetProjection {
    var outline: WidgetMapOutline
    var size: CGSize

    private var scale: CGFloat {
        min(size.width / CGFloat(max(outline.width, 0.000_001)), size.height / CGFloat(max(outline.height, 0.000_001)))
    }
    private var origin: CGPoint {
        CGPoint(x: (size.width - CGFloat(outline.width) * scale) / 2, y: (size.height - CGFloat(outline.height) * scale) / 2)
    }

    func point(_ point: WidgetMapPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale)
    }

    func rect(for cell: WidgetCell) -> CGRect {
        let center = point(WidgetMapPoint(x: cell.x, y: cell.y))
        let side = CGFloat(cell.side) * scale
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}

private enum WidgetCurrencyFormat {
    static func format(_ minorUnits: Int64, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let digits = formatter.maximumFractionDigits
        let factor = Decimal(pow(10.0, Double(digits)))
        let value = Decimal(minorUnits) / factor
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(minorUnits) \(currencyCode)"
    }
}
