import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum MapMethodPalette {
    static let accent: Color = {
#if os(iOS)
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.94, green: 0.62, blue: 0.43, alpha: 1)
            }
            return UIColor(red: 0.56, green: 0.23, blue: 0.13, alpha: 1)
        })
#elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor(red: 0.94, green: 0.62, blue: 0.43, alpha: 1)
            }
            return NSColor(red: 0.56, green: 0.23, blue: 0.13, alpha: 1)
        })
#else
        Color.brown
#endif
    }()

    static let surface = Color.primary.opacity(0.035)
    static let quietSurface = Color.primary.opacity(0.025)
    static let hairline = Color.primary.opacity(0.08)
    static let emptyCell = Color.primary.opacity(0.12)
}
