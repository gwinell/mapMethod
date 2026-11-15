import SwiftUI

struct SavingsMapView: View {
    var outline: MapOutline
    var cells: [SavingsCell]
    var currencyCode: String
    var onToggleCell: (SavingsCell) -> Void
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var pan = CGSize.zero
    @State private var panAtGestureStart = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let projection = MapProjection(outline: outline, size: geometry.size, inset: 10)
            ZStack(alignment: .topLeading) {
                outlinePath(projection: projection)
                    .fill(Color.primary.opacity(0.025), style: FillStyle(eoFill: true))
                outlinePath(projection: projection)
                    .stroke(Color.primary.opacity(0.09), style: StrokeStyle(lineWidth: 1, lineJoin: .round))

                ForEach(cells) { cell in
                    let rect = projection.rect(for: cell)
                    Button {
                        onToggleCell(cell)
                    } label: {
                        MapTile(isFilled: cell.filledAt != nil, side: rect.width)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(22, rect.width), height: max(22, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityLabel(CurrencyAmount.format(cell.valueMinorUnits, currencyCode: currencyCode))
                    .accessibilityHint(cell.filledAt == nil ? "Отметить накопление" : "Отменить отметку")
                }

                if zoom > 1 || abs(pan.width) > 1 || abs(pan.height) > 1 {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            zoom = 1
                            zoomAtGestureStart = 1
                            pan = .zero
                            panAtGestureStart = .zero
                        }
                    } label: {
                        Label("Сбросить масштаб", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(zoom, anchor: .center)
            .offset(pan)
            .clipped()
            .gesture(
                MagnificationGesture()
                    .onChanged { value in zoom = min(6, max(1, zoomAtGestureStart * value)) }
                    .onEnded { _ in zoomAtGestureStart = zoom }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        pan = CGSize(width: panAtGestureStart.width + value.translation.width, height: panAtGestureStart.height + value.translation.height)
                    }
                    .onEnded { _ in panAtGestureStart = pan }
            )
        }
        .frame(minHeight: 280)
    }

    private func outlinePath(projection: MapProjection) -> Path {
        var path = Path()
        for ring in outline.rings {
            guard let first = ring.points.first else { continue }
            path.move(to: projection.point(for: first))
            for point in ring.points.dropFirst() { path.addLine(to: projection.point(for: point)) }
            path.closeSubpath()
        }
        return path
    }
}

private struct MapTile: View {
    var isFilled: Bool
    var side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: min(max(side * 0.2, 2), 12), style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: min(max(side * 0.2, 2), 12), style: .continuous)
                    .strokeBorder(Color.primary.opacity(isFilled ? 0.08 : 0.06), lineWidth: 0.8)
            }
            .frame(width: max(4, side - 1.5), height: max(4, side - 1.5))
            .scaleEffect(isFilled ? 1 : 0.97)
            .rotation3DEffect(.degrees(isFilled ? -2 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .animation(.easeOut(duration: 0.18), value: isFilled)
    }

    private var fill: Color {
        isFilled ? MapMethodPalette.accent : MapMethodPalette.emptyCell
    }
}

private struct MapProjection {
    var outline: MapOutline
    var size: CGSize
    var inset: CGFloat

    private var scale: CGFloat {
        min(
            max(1, size.width - inset * 2) / max(0.000_001, outline.width),
            max(1, size.height - inset * 2) / max(0.000_001, outline.height)
        )
    }

    private var origin: CGPoint {
        CGPoint(
            x: (size.width - CGFloat(outline.width) * scale) / 2,
            y: (size.height - CGFloat(outline.height) * scale) / 2
        )
    }

    func point(for point: MapPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale)
    }

    func rect(for cell: SavingsCell) -> CGRect {
        let center = point(for: MapPoint(x: cell.x, y: cell.y))
        let side = CGFloat(cell.side) * scale
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}

struct OutlinePreview: View {
    var outline: MapOutline

    var body: some View {
        GeometryReader { geometry in
            let projection = MapProjection(outline: outline, size: geometry.size, inset: 12)
            Canvas { context, _ in
                var path = Path()
                for ring in outline.rings {
                    guard let first = ring.points.first else { continue }
                    path.move(to: projection.point(for: first))
                    for point in ring.points.dropFirst() { path.addLine(to: projection.point(for: point)) }
                    path.closeSubpath()
                }
                context.fill(path, with: .color(MapMethodPalette.accent.opacity(0.12)), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(MapMethodPalette.accent.opacity(0.7)), lineWidth: 1.5)
            }
        }
    }
}
