import AppKit
import SwiftUI

/// Shared neutral surfaces adapt to the system appearance.
enum LauncherAppearance {
    private static func adaptive(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        })
    }

    static let sidebar = adaptive(0.95, 0.12)
    static let canvas = adaptive(0.985, 0.15)
    static let card = adaptive(1, 0.19)
    static let subtle = adaptive(0.95, 0.24)
    static let border = Color.primary.opacity(0.07)
    static let accent = Color(nsColor: .linkColor)
    static let strong = adaptive(0.16, 0.90)
    static let onStrong = adaptive(1, 0.12)
    static let running = Color(red: 0.26, green: 0.57, blue: 0.39)
    static let avatars: [Color] = [
        Color(red: 0.40, green: 0.46, blue: 0.55),
        Color(red: 0.45, green: 0.43, blue: 0.58),
        Color(red: 0.55, green: 0.45, blue: 0.34),
        Color(red: 0.37, green: 0.50, blue: 0.51)
    ]
}

struct LauncherButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, prominent ? 15 : 12)
            .frame(minHeight: 32)
            .foregroundStyle(prominent ? LauncherAppearance.onStrong : Color.primary)
            .background(prominent ? LauncherAppearance.strong : LauncherAppearance.subtle,
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
