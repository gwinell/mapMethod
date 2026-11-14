import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.updatedAt, order: .reverse) private var goals: [SavingsGoal]
    @State private var showingCreate = false

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if goals.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(goals) { goal in
                                NavigationLink {
                                    GoalDetailView(goal: goal)
                                } label: {
                                    GoalCard(goal: goal)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(goal)
                                    } label: {
                                        Label("Удалить карту", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    syncNote
                }
                .frame(maxWidth: 1_000, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color.primary.opacity(0.025))
            .navigationTitle("MapMethod")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Новая карта", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
            .sheet(isPresented: $showingCreate) { CreateGoalView() }
            .onAppear(perform: refreshWidgets)
            .onChange(of: goals.map(\.updatedAt)) { _, _ in refreshWidgets() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Собирайте карту вместе с накоплениями.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Выбирайте места, ставьте цель и отмечайте клетки по мере того, как откладываете деньги.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Ваша первая карта ждёт")
                .font(.title3.weight(.semibold))
            Text("Найдите город или нарисуйте собственный контур.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Создать карту", systemImage: "plus") { showingCreate = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 45)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var syncNote: some View {
        Label("Карты синхронизируются через iCloud, если вы вошли в один Apple Account на обоих устройствах.", systemImage: "icloud")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
    }

    private func refreshWidgets() {
        let snapshots = goals.compactMap(\.document).map { document in
            WidgetGoalSnapshot(
                id: document.id,
                title: document.title,
                targetMinorUnits: document.targetMinorUnits,
                savedMinorUnits: document.savedMinorUnits,
                currencyCode: document.currencyCode,
                outline: WidgetMapOutline(
                    rings: document.outline.rings.map { ring in
                        WidgetMapRing(points: ring.points.map { WidgetMapPoint(x: $0.x, y: $0.y) }, isHole: ring.isHole)
                    },
                    width: document.outline.width,
                    height: document.outline.height,
                    sourceName: document.outline.sourceName,
                    source: document.outline.source
                ),
                cells: document.cells.map {
                    WidgetCell(id: $0.id, x: $0.x, y: $0.y, side: $0.side, valueMinorUnits: $0.valueMinorUnits, isFilled: $0.filledAt != nil)
                },
                updatedAt: document.updatedAt
            )
        }
        WidgetSnapshotStore.save(snapshots)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func delete(_ goal: SavingsGoal) {
        modelContext.delete(goal)
        try? modelContext.save()
    }
}

private struct GoalCard: View {
    var goal: SavingsGoal
    private var document: SavingsGoalDocument? { goal.document }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(goal.document?.outline.sourceName ?? "Карта накоплений")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 5)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let document {
                ZStack {
                    OutlinePreview(outline: document.outline)
                    MiniatureCells(document: document)
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(CurrencyAmount.format(document.savedMinorUnits, currencyCode: document.currencyCode))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Spacer()
                        Text("\(Int(document.progress * 100))%")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: document.progress).tint(Color.accentColor)
                    Text("цель \(CurrencyAmount.format(document.targetMinorUnits, currencyCode: document.currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(17)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }
}

private struct MiniatureCells: View {
    var document: SavingsGoalDocument

    var body: some View {
        GeometryReader { geometry in
            let projection = MiniProjection(outline: document.outline, size: geometry.size)
            Canvas { context, _ in
                for cell in document.cells {
                    let rect = projection.rect(for: cell)
                    guard rect.width > 1 else { continue }
                    let radius = min(rect.width * 0.22, 5)
                    let path = Path(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), cornerSize: CGSize(width: radius, height: radius))
                    context.fill(path, with: .color(cell.filledAt == nil ? Color.primary.opacity(0.16) : Color.accentColor))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MiniProjection {
    var outline: MapOutline
    var size: CGSize

    private var scale: CGFloat { min(size.width / CGFloat(outline.width), size.height / CGFloat(outline.height)) }
    private var origin: CGPoint {
        CGPoint(x: (size.width - CGFloat(outline.width) * scale) / 2, y: (size.height - CGFloat(outline.height) * scale) / 2)
    }

    func rect(for cell: SavingsCell) -> CGRect {
        let center = CGPoint(x: origin.x + CGFloat(cell.x) * scale, y: origin.y + CGFloat(cell.y) * scale)
        let side = CGFloat(cell.side) * scale
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}
