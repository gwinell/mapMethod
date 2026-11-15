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
    @State private var currencyCode = CurrencyOption.defaultCode
    @State private var isSearching = false
    @State private var isLoadingOutline = false
    @State private var errorMessage: String?
    @State private var baseCellManuallyEdited = false

    private let searchService = PlaceSearchService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
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
            .onChange(of: currencyCode) { _, _ in
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
#if os(macOS)
        .frame(minWidth: 520, minHeight: 700)
#endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Карта для вашей цели")
                .font(.largeTitle.weight(.medium))
            Text("Выберите контур, валюту и сумму. Приложение разложит цель на клетки.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                selectEarth()
            } label: {
                Label("Вся Земля", systemImage: "globe.europe.africa")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
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
                                    .foregroundStyle(MapMethodPalette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name).font(.body.weight(.medium))
                                    if !result.subtitle.isEmpty {
                                            Text(result.subtitle).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedPlace?.id == result.id && isLoadingOutline {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if result.id != searchResults.last?.id { Divider() }
                    }
                }
                .padding(12)
                .background(MapMethodPalette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Поиск мест использует Apple Maps. Контуры предоставлены OpenStreetMap contributors (ODbL).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FreehandOutlineEditor(points: $drawnPoints, canvasAspectRatio: $drawingAspectRatio)
            HStack {
                Text("Обведите территорию одним движением")
                    .font(.footnote)
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
                .frame(width: 140, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? value.sourceName : title)
                    .font(.title3.weight(.medium))
                Text(value.source)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if mode == .search && isLoadingOutline {
                    Label("Загружаю контур…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLoadingOutline { ProgressView() }
        }
        .padding(12)
        .background(MapMethodPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var goalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Цель накопления").font(.title3.weight(.medium))
                Spacer()
                CurrencyPickerButton(selection: $currencyCode)
            }
            TextField("Название карты", text: Binding(
                get: { title },
                set: { title = $0; titleManuallyEdited = true }
            ))
                .textFieldStyle(.roundedBorder)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    amountField("Сумма цели · \(currencyCode)", text: $targetText)
                    amountField("Основная клетка · \(currencyCode)", text: baseCellBinding)
                }
                VStack(spacing: 12) {
                    amountField("Сумма цели · \(currencyCode)", text: $targetText)
                    amountField("Основная клетка · \(currencyCode)", text: baseCellBinding)
                }
            }
            Text("Валюта задаётся отдельно для каждой карты. Основной номинал приложение предложит автоматически.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var baseCellBinding: Binding<String> {
        Binding(
            get: { baseCellText },
            set: { baseCellText = $0; baseCellManuallyEdited = true }
        )
    }

    private func amountField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.body).foregroundStyle(.secondary)
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
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3.square")
                        .foregroundStyle(MapMethodPalette.accent)
                    Text(values.isEmpty ? "Слишком много клеток. Увеличьте номинал." : "Будет создано клеток: \(values.count)")
                    Spacer()
                    if !values.isEmpty {
                        Text(CurrencyAmount.format(values.reduce(0, +), currencyCode: currencyCode))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.body)
                .padding(12)
                .background(MapMethodPalette.quietSurface, in: RoundedRectangle(cornerRadius: 12))
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
