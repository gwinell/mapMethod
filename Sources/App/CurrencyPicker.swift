import Foundation
import SwiftUI

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String

    var id: String { code }

    static let all: [CurrencyOption] = {
        let current = Locale.current.currency?.identifier
        let codes = Set(Locale.commonISOCurrencyCodes + [current].compactMap { $0 })
        return codes.compactMap { code in
            guard code != "XXX",
                  let name = Locale.current.localizedString(forCurrencyCode: code) else { return nil }
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale.current
            formatter.currencyCode = code
            return CurrencyOption(code: code, name: name, symbol: formatter.currencySymbol ?? code)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static var defaultCode: String {
        let local = Locale.current.currency?.identifier ?? "USD"
        return all.contains(where: { $0.code == local }) ? local : "USD"
    }
}

struct CurrencyPickerButton: View {
    @Binding var selection: String
    var compact = false

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(selection)
                    .font(.title3.weight(.medium).monospacedDigit())
                if !compact {
                    Text(symbol)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MapMethodPalette.quietSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MapMethodPalette.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Валюта: \(selection)")
        .help("Смена валюты не пересчитывает сумму по курсу")
        .sheet(isPresented: $isPresented) {
            CurrencySelectionSheet(selection: $selection)
        }
    }

    private var symbol: String {
        CurrencyOption.all.first(where: { $0.code == selection })?.symbol ?? selection
    }
}

private struct CurrencySelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var searchText = ""

    private var filteredCurrencies: [CurrencyOption] {
        guard !searchText.isEmpty else { return CurrencyOption.all }
        return CurrencyOption.all.filter {
            $0.code.localizedStandardContains(searchText) ||
            $0.name.localizedStandardContains(searchText) ||
            $0.symbol.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCurrencies) { currency in
                Button {
                    selection = currency.code
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currency.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("\(currency.code) · \(currency.symbol)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == currency.code {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.medium))
                                .foregroundStyle(MapMethodPalette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Найти валюту")
            .navigationTitle("Валюта")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 340, minHeight: 420)
#endif
    }
}
