import SwiftUI

/// First-launch screen shown while no server is saved: the value proposition
/// plus a single call to action that opens the (reused) server editor. Replaces
/// landing on an empty server list.
struct OnboardingView: View {
    let store: ServerStore
    /// Called after the first server is saved, so the caller can select it.
    let onComplete: (ServerProfile) -> Void

    @State private var showEditor = false

    var body: some View {
        ZStack {
            CodegBackground()
            VStack(spacing: 0) {
                Spacer()

                LucideIcon(sf: "chevron.left.forwardslash.chevron.right", size: 34)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 84, height: 84)
                    .background(WebTheme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                    .hairlineBorder(Theme.Radius.xl, color: Theme.accent.opacity(0.3))
                    .padding(.bottom, 24)

                Text("Codeg")
                    .font(WebTheme.sans(24, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your coding agents, in your pocket.")
                    .font(WebTheme.sans(14, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 14) {
                    bullet(icon: "waveform", title: "Watch tasks live",
                           detail: "Replies, tool runs, and edits stream in as they happen.")
                    bullet(icon: "bubble.left.and.text.bubble.right", title: "Steer from anywhere",
                           detail: "Reply to a running agent without going back to your desk.")
                    bullet(icon: "plus.circle", title: "Start new work",
                           detail: "Kick off tasks in any folder with your preferred agent.")
                }
                .padding(.top, 32)
                .padding(.horizontal, 8)

                Spacer()

                PrimaryGlassButton(title: "Add Your Server", systemImage: "plus") {
                    showEditor = true
                }
                Text("Codeg connects to a codeg server you run — usually on your dev machine.")
                    .font(WebTheme.sans(12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .sheet(isPresented: $showEditor) {
            ServerEditorSheet(store: store) { profile in
                onComplete(profile)
            }
        }
    }

    private func bullet(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(sf: icon, size: 14)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WebTheme.sans(14, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(WebTheme.sans(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
