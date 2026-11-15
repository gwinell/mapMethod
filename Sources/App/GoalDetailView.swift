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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                CurrencyPickerButton(selection: currencyBinding, compact: true)
            }
        }
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
                .padding(8)
                .background(MapMethodPalette.quietSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                    Text("Нажмите на целую клетку, когда отложите её сумму.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Text("Смена валюты не пересчитывает сумму по обменному курсу.")
                    .font(.caption)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(CurrencyAmount.format(document.savedMinorUnits, currencyCode: document.currencyCode))
                    .font(.system(size: 32, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                Text("\(Int(document.progress * 100))%")
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: document.progress)
                .tint(MapMethodPalette.accent)
            HStack {
                Text("из \(CurrencyAmount.format(document.targetMinorUnits, currencyCode: document.currencyCode))")
                Spacer()
                Text("\(document.cells.filter { $0.filledAt != nil }.count) из \(document.cells.count) клеток")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.18), value: document.savedMinorUnits)
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
                    HStack(spacing: 12) {
                        Image(systemName: event.isFilled ? "plus.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(event.isFilled ? MapMethodPalette.accent : Color.secondary)
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
        .background(MapMethodPalette.surface, in: RoundedRectangle(cornerRadius: 16))
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
        withAnimation(.easeOut(duration: 0.18)) {
            goal.update(cells: cells, events: events, at: now)
            try? modelContext.save()
        }
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { goal.currencyCode },
            set: { newCode in
                guard newCode != goal.currencyCode,
                      let current = goal.document else { return }
                goal.update(document: current.changingCurrency(to: newCode))
                try? modelContext.save()
            }
        )
    }
}
