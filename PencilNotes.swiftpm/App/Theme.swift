import SwiftUI
import UIKit

enum NotebookTheme {
    static let canvasBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 12.0 / 255, green: 12.0 / 255, blue: 16.0 / 255, alpha: 1) : .white
    }
    static let ink = Color.primary
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 25.0 / 255, green: 25.0 / 255, blue: 25.0 / 255, alpha: 1) : UIColor(white: 1, alpha: 1)
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

struct PressFeedback: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
