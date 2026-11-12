import SwiftUI
import UIKit

enum NotebookTheme {
    static let ink = Color.primary
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 25.0 / 255, alpha: 1) : UIColor(white: 1, alpha: 1)
    })
    static let secondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    })
}

struct FloatingGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

extension View {
    func floatingGlass() -> some View { modifier(FloatingGlass()) }
}
