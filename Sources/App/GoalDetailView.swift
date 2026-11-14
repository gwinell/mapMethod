import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: SavingsGoal

    private var document: SavingsGoalDocument? { goal.document }

    var body: some View {
        Group {
            if let document {
                detail(document)
            } else {
                ContentUnavailableView("Не удалось открыть карту", systemImage: "map", description: Text("Данные карты повреждены или недоступны."))
            }
        }
        .navigationTitle(goal.title)
        .frame(minWidth: 420, minHeight: 560)
    }

    private func detail(_ document: SavingsGoalDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                progressHeader(document)
                SavingsMapView(
                    outline: document.outline,
                    cells: document.cells,
                    currencyCode: document.currencyCode,
                    onToggleCell: { cell in toggle(cell, in: document) }
                )
                .frame(height: 390)
                .padding(10)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 10) {
                    Image(systemName: "hand.tap")
                    Text("Нажмите на целую клетку, когда отложите её сумму.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                history(document)
                attribution(document.outline)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func progressHeader(_ document: SavingsGoalDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(CurrencyAmount.format(document.savedMinorUnits, currencyCode: document.currencyCode))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
                Text("\(Int(document.progress * 100))%")
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: document.progress)
                .tint(Color.accentColor)
                .scaleEffect(x: 1, y: 1.45, anchor: .center)
            HStack {
                Text("из \(CurrencyAmount.format(document.targetMinorUnits, currencyCode: document.currencyCode))")
                Spacer()
                Text("\(document.cells.filter { $0.filledAt != nil }.count) из \(document.cells.count) клеток")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: document.savedMinorUnits)
    }

    private func history(_ document: SavingsGoalDocument) -> some View {
        let recent = Array(document.events.sorted { $0.happenedAt > $1.happenedAt }.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История").font(.headline)
                Spacer()
                Text("Для будущего таймлапса")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if recent.isEmpty {
                Text("Отмеченные клетки и даты появятся здесь.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.isFilled ? "plus.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(event.isFilled ? Color.accentColor : Color.secondary)
                        Text(event.isFilled ? "Клетка заполнена" : "Отметка отменена")
                        Spacer()
                        Text(CurrencyAmount.format(event.valueMinorUnits, currencyCode: document.currencyCode))
                            .monospacedDigit()
                        Text(event.happenedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func attribution(_ outline: MapOutline) -> some View {
        if outline.source == "OpenStreetMap" {
            Text("Контуры © OpenStreetMap contributors · ODbL")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func toggle(_ cell: SavingsCell, in document: SavingsGoalDocument) {
        guard let index = document.cells.firstIndex(where: { $0.id == cell.id }) else { return }
        var cells = document.cells
        let isFilling = cells[index].filledAt == nil
        let now = Date.now
        cells[index].filledAt = isFilling ? now : nil
        var events = document.events
        events.append(ContributionEvent(cellID: cell.id, valueMinorUnits: cell.valueMinorUnits, isFilled: isFilling, happenedAt: now))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.64)) {
            goal.update(cells: cells, events: events, at: now)
            try? modelContext.save()
        }
    }
}
