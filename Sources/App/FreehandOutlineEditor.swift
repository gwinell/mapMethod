import SwiftUI

struct FreehandOutlineEditor: View {
    @Binding var points: [MapPoint]
    @Binding var canvasAspectRatio: Double
    @State private var lastPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                Canvas { context, size in
                    if points.count > 1 {
                        var path = Path()
                        path.move(to: pixel(points[0], in: size))
                        for point in points.dropFirst() { path.addLine(to: pixel(point, in: size)) }
                        if points.count > 2 { path.closeSubpath() }
                        context.fill(path, with: .color(Color.accentColor.opacity(0.14)))
                        context.stroke(path, with: .color(Color.accentColor), lineWidth: 2.5)
                    }
                    for point in points {
                        let center = pixel(point, in: size)
                        let dot = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: dot), with: .color(Color.accentColor))
                    }
                }
                if points.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "scribble.variable").font(.system(size: 27, weight: .light))
                        Text("Нарисуйте контур одним движением")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location
                        if let lastPoint {
                            let dx = point.x - lastPoint.x
                            let dy = point.y - lastPoint.y
                            guard dx * dx + dy * dy > 20 else { return }
                        }
                        points.append(MapPoint(
                            x: min(1, max(0, point.x / max(geometry.size.width, 1))),
                            y: min(1, max(0, point.y / max(geometry.size.height, 1)))
                        ))
                        lastPoint = point
                        canvasAspectRatio = Double(geometry.size.width / max(geometry.size.height, 1))
                    }
                    .onEnded { _ in lastPoint = nil }
            )
            .onAppear { canvasAspectRatio = Double(geometry.size.width / max(geometry.size.height, 1)) }
            .onChange(of: geometry.size) { _, size in
                canvasAspectRatio = Double(size.width / max(size.height, 1))
            }
        }
        .frame(height: 270)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func pixel(_ point: MapPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}
