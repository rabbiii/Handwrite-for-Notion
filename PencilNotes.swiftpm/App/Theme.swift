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
    func notebookGlassButtons() -> some View { modifier(NotebookGlassButtons()) }
    func notebookSidebarGlass() -> some View { modifier(NotebookSidebarGlass()) }
    func notebookBackgroundExtension() -> some View { modifier(NotebookBackgroundExtension()) }
}

private struct NotebookSidebarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .containerBackground(for: .navigation) {
                    Color.clear
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
                        .ignoresSafeArea()
                }
                .containerBackground(Color.clear, for: .navigationSplitView)
        } else if #available(iOS 18.0, *) {
            content
                .containerBackground(.ultraThinMaterial, for: .navigation)
                .containerBackground(Color.clear, for: .navigationSplitView)
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

private struct NotebookBackgroundExtension: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

private struct NotebookGlassButtons: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(MaterialGlassButtonStyle())
        }
    }
}

private struct MaterialGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.15), lineWidth: 0.5))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
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
