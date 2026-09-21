import SwiftUI

/// Centered empty state with an optional primary action.
///
/// The web's empty states are quiet: a muted glyph, a `text-base` line, a
/// `text-sm` explanation, and — if there's something to do — one outline button.
/// The accent-filled 60pt tile this used to lead with was the app's own
/// invention; on a flat surface it reads as a badge for a screen that has
/// nothing in it.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: WebTheme.Space.three) {
            LucideIcon(sf: icon, size: 28)
                .foregroundStyle(WebTheme.mutedForeground.opacity(0.7))
                .padding(.bottom, WebTheme.Space.half)
            Text(title)
                .webText(.base, .semibold)
                .foregroundStyle(WebTheme.foreground)
            if let message {
                Text(message)
                    .webText(.sm)
                    .foregroundStyle(WebTheme.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.web(.outline, .small))
                    .padding(.top, WebTheme.Space.one)
            }
        }
        .frame(maxWidth: 320)
        .padding(32)
    }
}

/// Centered progress indicator with a caption.
struct LoadingView: View {
    var label: LocalizedStringKey = "Loading…"

    var body: some View {
        VStack(spacing: WebTheme.Space.three) {
            ProgressView()
                .controlSize(.regular)
                .tint(WebTheme.mutedForeground)
            Text(label)
                .webText(.sm)
                .foregroundStyle(WebTheme.mutedForeground)
        }
        .padding(32)
    }
}

/// A compact, dismissible error strip shown above a still-populated list when a
/// refresh fails, so stale rows stay visible but the failure isn't silent.
/// The web's destructive treatment: a `bg-destructive/10` fill with
/// `text-destructive` content — never a solid red bar.
struct RefreshErrorBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WebTheme.Space.two) {
            LucideIcon(.triangleAlert, size: 14)
                .foregroundStyle(WebTheme.destructive)

            Text(verbatim: message)
                .webText(.xs)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: retry)
                .buttonStyle(.web(.ghost, .xs))

            Button(action: dismiss) {
                LucideIcon(.x, size: 14)
                    .foregroundStyle(WebTheme.mutedForeground)
            }
            .buttonStyle(.web(.ghost, .iconTiny))
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, WebTheme.Space.three)
        .padding(.vertical, WebTheme.Space.two)
        .background(
            WebTheme.destructiveSoft,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
        .webBorder(cornerRadius: Theme.Radius.md, color: WebTheme.destructive.opacity(0.25))
    }
}

/// Inline error card with a retry affordance.
struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: WebTheme.Space.three) {
            LucideIcon(.triangleAlert, size: 28)
                .foregroundStyle(WebTheme.destructive)
            Text("Something went wrong")
                .webText(.base, .semibold)
                .foregroundStyle(WebTheme.foreground)
            Text(verbatim: message)
                .webText(.sm)
                .foregroundStyle(WebTheme.mutedForeground)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.web(.outline, .small))
                    .padding(.top, WebTheme.Space.one)
            }
        }
        .frame(maxWidth: 340)
        .padding(28)
    }
}
