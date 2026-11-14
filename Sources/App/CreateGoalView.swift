import SwiftUI
import SwiftData

struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private enum OutlineMode: String, CaseIterable, Identifiable {
        case search = "Найти место"
        case draw = "Нарисовать"
        var id: String { rawValue }
    }

    @State private var mode: OutlineMode = .search
    @State private var searchText = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var selectedPlace: PlaceSearchResult?
    @State private var outline: MapOutline?
    @State private var drawnPoints: [MapPoint] = []
    @State private var drawingAspectRatio = 1.3
    @State private var title = ""
    @State private var targetText = "100000"
    @State private var baseCellText = ""
    @State private var titleManuallyEdited = false
    @State private var currencyCode = Locale.current.currency?.identifier ?? "USD"
    @State private var isSearching = false
    @State private var isLoadingOutline = false
    @State private var errorMessage: String?
    @State private var baseCellManuallyEdited = false

    private let searchService = PlaceSearchService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    Picker("Источник контура", selection: $mode) {
                        ForEach(OutlineMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if mode == .search {
                        searchSection
                    } else {
                        drawSection
                    }

                    if let outline {
                        selectedOutline(outline)
                    }

                    goalSettings
                    if outline != nil { denominationSummary }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Новая карта")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { createGoal() }
                        .disabled(!canCreate)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear(perform: updateSuggestedBaseCell)
            .onChange(of: targetText) { _, _ in
                errorMessage = nil
                if !baseCellManuallyEdited { updateSuggestedBaseCell() }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .draw {
                    selectedPlace = nil
                    outline = MapOutline.fromDrawing(points: drawnPoints, canvasAspectRatio: drawingAspectRatio)
                } else if selectedPlace == nil {
                    outline = nil
                }
            }
        }
        .frame(minWidth: 420, minHeight: 620)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Накопления, которые видно")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Выберите контур и сумму цели. Приложение превратит её в карту клеток.")
                .foregroundStyle(.secondary)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectEarth()
            } label: {
                Label("Вся Земля", systemImage: "globe.europe.africa")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                TextField("Город, район или страна", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await searchPlaces() } }
                Button {
                    Task { await searchPlaces() }
                } label: {
                    if isSearching { ProgressView().controlSize(.small) }
                    else { Label("Поиск", systemImage: "magnifyingglass") }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button {
                            Task { await choose(result) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).fontWeight(.medium)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedPlace?.id == result.id && isLoadingOutline {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if result.id != searchResults.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Поиск мест использует Apple Maps. Контуры предоставлены OpenStreetMap contributors (ODbL).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FreehandOutlineEditor(points: $drawnPoints, canvasAspectRatio: $drawingAspectRatio)
            HStack {
                Text("Обведите территорию одним движением.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Очистить", systemImage: "eraser") {
                    drawnPoints.removeAll()
                    outline = nil
                }
                .disabled(drawnPoints.isEmpty)
            }
            .onChange(of: drawnPoints) { _, points in
                outline = MapOutline.fromDrawing(points: points, canvasAspectRatio: drawingAspectRatio)
                if !titleManuallyEdited { title = "Мой контур" }
            }
            .onChange(of: drawingAspectRatio) { _, ratio in
                outline = MapOutline.fromDrawing(points: drawnPoints, canvasAspectRatio: ratio)
            }
        }
    }

    private func selectedOutline(_ value: MapOutline) -> some View {
        HStack(spacing: 16) {
            OutlinePreview(outline: value)
                .frame(width: 120, height: 90)
            VStack(alignment: .leading, spacing: 5) {
                Text(title.isEmpty ? value.sourceName : title)
                    .font(.headline)
                Text(value.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if mode == .search && isLoadingOutline {
                    Label("Загружаю контур…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLoadingOutline { ProgressView() }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }

    private var goalSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Цель накопления").font(.headline)
            TextField("Название карты", text: Binding(
                get: { title },
                set: { title = $0; titleManuallyEdited = true }
            ))
                .textFieldStyle(.roundedBorder)
            HStack(alignment: .top, spacing: 12) {
                amountField("Сумма цели", text: $targetText)
                amountField("Основная клетка (\(currencyCode))", text: Binding(
                    get: { baseCellText },
                    set: { baseCellText = $0; baseCellManuallyEdited = true }
                ))
            }
            Text("Номинал основной клетки предложен автоматически. Остаток приложение разложит на меньшие клетки.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func amountField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            TextField("0", text: text)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var denominationSummary: some View {
        Group {
            if let target = parsedTarget, let base = parsedBase {
                let values = DenominationPlanner.cellValues(target: target, baseCell: base, currencyCode: currencyCode)
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3.square")
                        .foregroundStyle(Color.accentColor)
                    Text(values.isEmpty ? "Слишком много клеток. Увеличьте номинал." : "Будет создано клеток: \(values.count)")
                    Spacer()
                    if !values.isEmpty {
                        Text(CurrencyAmount.format(values.reduce(0, +), currencyCode: currencyCode))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(12)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var parsedTarget: Int64? { CurrencyAmount.parse(targetText, currencyCode: currencyCode) }
    private var parsedBase: Int64? { CurrencyAmount.parse(baseCellText, currencyCode: currencyCode) }

    private var canCreate: Bool {
        guard let outline, outline.area > 0,
              let target = parsedTarget, let base = parsedBase,
              !DenominationPlanner.cellValues(target: target, baseCell: base, currencyCode: currencyCode).isEmpty else { return false }
        return !isLoadingOutline
    }

    private func searchPlaces() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            searchResults = try await searchService.search(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
            if searchResults.isEmpty { errorMessage = "Ничего не найдено. Попробуйте другое название." }
        } catch {
            errorMessage = "Не удалось выполнить поиск. Проверьте подключение и попробуйте ещё раз."
        }
    }

    private func choose(_ result: PlaceSearchResult) async {
        selectedPlace = result
        isLoadingOutline = true
        errorMessage = nil
        do {
            let value = try await OverpassBoundaryService.shared.outline(for: result)
            outline = value
            if !titleManuallyEdited { title = value.sourceName }
        } catch {
            outline = nil
            errorMessage = error.localizedDescription
        }
        isLoadingOutline = false
    }

    private func selectEarth() {
        guard let url = Bundle.main.url(forResource: "world-outline", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let world = try? JSONDecoder().decode(MapOutline.self, from: data) else {
            errorMessage = "Не удалось загрузить контур Земли."
            return
        }
        selectedPlace = nil
        outline = world
        errorMessage = nil
        if !titleManuallyEdited { title = world.sourceName }
    }

    private func updateSuggestedBaseCell() {
        guard let target = parsedTarget else { return }
        let factor = CurrencyAmount.factor(for: currencyCode)
        let suggested = CurrencyAmount.suggestedBaseCellValue(target: target, currencyCode: currencyCode)
        let majorValue = Decimal(suggested) / Decimal(factor)
        baseCellText = NSDecimalNumber(decimal: majorValue).stringValue
    }

    private func createGoal() {
        guard let outline, let target = parsedTarget, let base = parsedBase else { return }
        let values = DenominationPlanner.cellValues(target: target, baseCell: base, currencyCode: currencyCode)
        let cells = PolygonGridGenerator.generate(outline: outline, values: values)
        guard cells.count == values.count else {
            errorMessage = "Не удалось разместить клетки внутри контура. Нарисуйте контур чуть крупнее или увеличьте номинал."
            return
        }
        let now = Date.now
        let document = SavingsGoalDocument(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? outline.sourceName : title,
            targetMinorUnits: target,
            baseCellMinorUnits: base,
            currencyCode: currencyCode,
            outline: outline,
            cells: cells,
            events: [],
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(SavingsGoal(document: document))
        dismiss()
    }
}
