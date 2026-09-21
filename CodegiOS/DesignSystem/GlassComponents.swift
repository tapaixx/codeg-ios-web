import SwiftUI

/// The app's container and button primitives, re-cut to the web client's
/// surfaces.
///
/// The names are unchanged — `GlassCard`, `PrimaryGlassButton`, … — because
/// ~70 call sites use them and renaming would be churn with no visual payoff.
/// What changed is what they draw: a Liquid Glass plate with a hairline and a
/// floating shadow becomes `bg-card` with a 1px ring, and a `.glassProminent`
/// button becomes the web's solid `bg-primary` pill. See
/// `docs/web-style-port.md` for the full mapping.

/// `src/components/ui/card.tsx` — `bg-card` + `rounded-2xl` +
/// `ring-1 ring-foreground/10`. No glass, no shadow.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .webCardSurface(cornerRadius: cornerRadius)
    }
}

/// A card without the ring — the web's `rounded-xl border bg-card` section, used
/// where a group sits directly on the page rather than floating over content.
/// Visually a half-step quieter than ``GlassCard``; both are flat.
struct FlatCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Radius.lg
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                WebTheme.card,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .webBorder(cornerRadius: cornerRadius)
    }
}

/// A compact action pill — the folder git tabs' Pull / Push / Commit buttons.
/// `prominent` is the web's `default` button variant (solid `bg-primary`);
/// otherwise it's the `outline` variant, which is what the web uses for the
/// toolbar actions alongside it.
struct AccentPillButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WebTheme.Space.onePointFive) {
                if let systemImage {
                    LucideIcon(sf: systemImage, size: WebTheme.Size.icon)
                }
                Text(title)
            }
        }
        .buttonStyle(.web(prominent ? .primary : .outline, .small))
    }
}

/// A tappable row in a list (servers, sessions). The web's rows are pills that
/// are transparent at rest and take a `bg-sidebar-primary/8` wash when selected
/// — no border, no card, no glass.
struct GlassRow<Content: View>: View {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = Theme.Radius.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, WebTheme.Space.three)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(WebTheme.sidebarPrimary.opacity(0.08))
                }
            }
    }
}

/// Press feedback for list / option rows, so a tap visibly registers.
///
/// A dim rather than a background fill: these rows live inside cards of several
/// different radii, and a fill drawn by the *style* can't know the row's shape,
/// so it would square off a rounded card's corners on touch. Rows that want the
/// web's `hover:bg-sidebar-accent` wash use ``WebRowStyle``, which owns its pill
/// shape. The web's short 120ms beat is matched; the old scale-down is gone —
/// nothing in the web UI scales on press.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(WebTheme.Motion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A small filter/selection chip. The web fills the selected chip with
/// `bg-primary` and leaves the rest on `bg-muted`; `tint` / `onTint` are kept in
/// the signature for the call sites that resolve colors explicitly (the
/// Appearance preview, which renders inside a sheet the theme trait can't reach).
struct FilterChip: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let isSelected: Bool
    var tint: Color = WebTheme.primary
    var onTint: Color = WebTheme.primaryForeground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WebTheme.Space.one) {
                if let systemImage {
                    LucideIcon(sf: systemImage, size: WebTheme.Size.iconSmall)
                }
                Text(title)
                    .webText(.xs, .medium)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? onTint : WebTheme.mutedForeground)
            .padding(.horizontal, WebTheme.Space.two)
            .frame(height: WebTheme.Size.controlTiny)
            .background {
                Capsule(style: .continuous).fill(isSelected ? tint : WebTheme.muted)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(WebTheme.Motion.chrome, value: isSelected)
    }
}

extension View {
    /// Compact: render `title` as a big, left-aligned bar item on the SAME row as
    /// the trailing toolbar buttons (inline mode, so there's no separate
    /// large-title band above it). Regular (iPad split): keep the standard system
    /// navigation title.
    @ViewBuilder
    func screenTitle(_ title: LocalizedStringKey, compact: Bool) -> some View {
        if compact {
            self
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
        } else {
            self.navigationTitle(title)
        }
    }
}

/// The full-width primary call-to-action at the foot of a sheet: the web's
/// `default` button variant stretched, at the larger `h-10` size so it still
/// reads as the screen's main action on a phone.
struct FlatPrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isLoading: Bool = false
    var tint: Color = WebTheme.primary
    var onTint: Color = WebTheme.primaryForeground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WebTheme.Space.two) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(onTint)
                } else if let systemImage {
                    LucideIcon(sf: systemImage, size: WebTheme.Size.icon)
                }
                Text(title)
            }
        }
        .buttonStyle(.web(.primary, .large, fullWidth: true, tint: tint, onTint: onTint))
        .disabled(isLoading)
    }
}

/// Alias of ``FlatPrimaryButton`` — the app had a glass and a flat primary
/// button; the web has one. Kept so both call-site names keep compiling.
struct PrimaryGlassButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isLoading: Bool = false
    var tint: Color = WebTheme.primary
    var onTint: Color = WebTheme.primaryForeground
    let action: () -> Void

    var body: some View {
        FlatPrimaryButton(
            title: title,
            systemImage: systemImage,
            isLoading: isLoading,
            tint: tint,
            onTint: onTint,
            action: action
        )
    }
}
