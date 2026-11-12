import SwiftUI
import MessageUI
import UIKit

enum CreatorLinks {
    static let github = URL(string: "https://github.com/rabbiii/Handwrite-for-Notion")!
    static let patreon = URL(string: "https://www.patreon.com/MorsalinIslam")!
    static let email = "mar.rabbi40@gmail.com"
    static let feedback = URL(string: "mailto:mar.rabbi40@gmail.com?subject=PencilNotes%20feedback")!
}

struct BrandIcon: View {
    enum Brand { case github, patreon }
    let brand: Brand

    var body: some View {
        Image(brand == .github ? "GitHubMark" : "PatreonMark")
            .resizable().scaledToFit().frame(width: 22, height: 22)
            .foregroundStyle(brand == .github ? Color.primary : Color(red: 1, green: 0.26, blue: 0.3))
            .accessibilityHidden(true)
    }
}

struct SupportShortcut: View {
    var body: some View {
        Link(destination: CreatorLinks.patreon) {
            HStack(spacing: 6) {
                BrandIcon(brand: .patreon)
                Text("Support").font(.subheadline.weight(.medium))
            }
        }
        .accessibilityLabel("Support PencilNotes on Patreon")
        .accessibilityHint("Optional support helps fund development. Opens Patreon.")
    }
}

struct CreatorSignature: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var emoji = "❤️"
    // Five hearts, then a little science, engineering and space.
    static let emojis = ["❤️", "🧡", "💛", "💚", "💙", "🔬", "🧪", "🧬", "⚗️", "⚙️", "🛠️", "💻", "🖥️", "🤖", "🛰️", "🚀"]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("Made with")
                rotatingEmoji
                Text("by Morsalin Islam")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { Text("Made with"); rotatingEmoji }
                Text("by Morsalin Islam")
            }
        }
        .font(.title2.weight(.bold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made with love by Morsalin Islam")
        .task(id: !reduceMotion && scenePhase == .active) {
            guard !reduceMotion, scenePhase == .active else { emoji = "❤️"; return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 400_000_000) }
                catch { return }
                emoji = Self.emojis.filter { $0 != emoji }.randomElement() ?? "❤️"
            }
        }
    }

    private var rotatingEmoji: some View {
        Text(emoji).frame(width: 36).accessibilityHidden(true)
    }
}

struct FeedbackButton: View {
    @Environment(\.openURL) private var openURL
    @State private var composing = false
    @State private var showingAddress = false

    var body: some View {
        Button {
            if MFMailComposeViewController.canSendMail() { composing = true }
            else {
                openURL(CreatorLinks.feedback) { accepted in
                    if !accepted { showingAddress = true }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("✉️").accessibilityHidden(true)
                Text("Send feedback")
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }.foregroundStyle(Color.primary).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Email \(CreatorLinks.email)")
        .sheet(isPresented: $composing) { FeedbackComposer() }
        .alert("Send feedback by email", isPresented: $showingAddress) {
            Button("Copy email address") { UIPasteboard.general.string = CreatorLinks.email }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No email app could open. Write to \(CreatorLinks.email), or copy the address to use in webmail.")
        }
    }
}

private struct FeedbackComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([CreatorLinks.email])
        controller.setSubject("PencilNotes feedback")
        controller.mailComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) { dismiss() }
    }
}
