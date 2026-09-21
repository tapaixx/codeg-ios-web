import SwiftUI

/// The web client's component vocabulary, ported to SwiftUI.
///
/// Each type here is a transcription of a specific shadcn component as this
/// project styles it — `src/components/ui/button.tsx`, `badge.tsx`, `card.tsx`,
/// and the sidebar row in `src/components/layout/sidebar.tsx`. Geometry is kept
/// literal (1 CSS px = 1 pt) because the geometry *is* the recognizable part:
/// 36pt pill buttons, 20pt pill badges, 16pt-radius cards outlined by a 1px ring
/// instead of a shadow, 31pt pill rows on a 2pt rail.
///
/// Where the web relies on hover, iOS gets a press state instead: the web's
/// `active:translate-y-px` nudge is ported literally, which is what makes these
/// feel like the same buttons.

// MARK: - Button

/// `buttonVariants` from `src/components/ui/button.tsx`.
struct WebButtonStyle: ButtonStyle {

    enum Variant {
        /// `bg-primary text-primary-foreground` — the one solid fill.
        case primary
        /// `border-border bg-input/30` — the default *chrome* button on the web.
        case outline
        /// `bg-secondary text-secondary-foreground`.
        case secondary
        /// Transparent until pressed.
        case ghost
        /// `bg-destructive/10 text-destructive` — never a solid red fill.
        case destructive
        /// Text-only, underlined on press.
        case link
    }

    enum Size {
        case xs      // h-6  px-2.5 text-xs
        case small   // h-8  px-3
        case medium  // h-9  px-3   (the web's default)
        case large   // h-10 px-4
        case icon    // 36×36
        case iconSmall // 32×32
        case iconTiny  // 24×24

        var height: CGFloat {
            switch self {
            case .xs, .iconTiny: WebTheme.Size.controlTiny
            case .small, .iconSmall: WebTheme.Size.controlSmall
            case .medium, .icon: WebTheme.Size.control
            case .large: WebTheme.Size.controlLarge
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .xs: 10
            case .small, .medium: 12
            case .large: 16
            case .icon, .iconSmall, .iconTiny: 0
            }
        }

        var isSquare: Bool {
            switch self {
            case .icon, .iconSmall, .iconTiny: true
            default: false
            }
        }

        var textStyle: WebTheme.TextStyle {
            switch self {
            case .xs, .iconTiny: WebTheme.TextStyle.xs.weight(.medium)
            default: WebTheme.TextStyle.sm.weight(.medium)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .xs, .iconTiny: WebTheme.Size.iconSmall
            default: WebTheme.Size.icon
            }
        }
    }

    var variant: Variant = .primary
    var size: Size = .medium
    /// Stretch to the container's width — the sheet-footer call-to-action shape.
    var fullWidth: Bool = false
    /// Overrides for the `--primary` pair. Normally left nil so the button reads
    /// the active preset through the theme trait; pass explicitly resolved colors
    /// where that trait can't reach (the Appearance preview, rendered inside the
    /// iPad Settings sheet).
    var tint: Color? = nil
    var onTint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        WebButtonBody(
            configuration: configuration,
            variant: variant,
            size: size,
            fullWidth: fullWidth,
            tint: tint ?? WebTheme.primary,
            onTint: onTint ?? WebTheme.primaryForeground
        )
    }
}

/// Split out so it can read `\.isEnabled`: a custom `ButtonStyle` gets no
/// automatic dimming when the button is disabled.
private struct WebButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: WebButtonStyle.Variant
    let size: WebButtonStyle.Size
    let fullWidth: Bool
    let tint: Color
    let onTint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .webText(size.textStyle)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .underline(variant == .link && configuration.isPressed)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(width: size.isSquare ? size.height : nil, height: size.height)
            .background {
                if let fill {
                    Capsule(style: .continuous).fill(fill)
                }
            }
            .overlay {
                if variant == .outline {
                    Capsule(style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
            // `active:not-aria-[haspopup]:translate-y-px` — the web's press nudge.
            .offset(y: configuration.isPressed ? 1 : 0)
            // `disabled:opacity-50`
            .opacity(isEnabled ? 1 : 0.5)
            .animation(WebTheme.Motion.press, value: configuration.isPressed)
    }

    /// Pressed states mirror the web's `hover:` step, which is the only feedback
    /// tier a pointer UI has and the closest analogue to a touch-down.
    private var fill: Color? {
        let pressed = configuration.isPressed
        switch variant {
        case .primary: return pressed ? tint.opacity(0.80) : tint
        case .secondary: return pressed ? WebTheme.secondary.opacity(0.80) : WebTheme.secondary
        case .outline: return pressed ? WebTheme.input.opacity(0.50) : WebTheme.inputSoft
        case .ghost: return pressed ? WebTheme.muted : .clear
        case .destructive: return WebTheme.destructive.opacity(pressed ? 0.20 : 0.10)
        case .link: return nil
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: onTint
        case .secondary: WebTheme.secondaryForeground
        case .outline, .ghost: WebTheme.foreground
        case .destructive: WebTheme.destructive
        case .link: tint
        }
    }
}

extension ButtonStyle where Self == WebButtonStyle {
    /// `.buttonStyle(.web(.outline, .small))`
    static func web(
        _ variant: WebButtonStyle.Variant = .primary,
        _ size: WebButtonStyle.Size = .medium,
        fullWidth: Bool = false,
        tint: Color? = nil,
        onTint: Color? = nil
    ) -> WebButtonStyle {
        WebButtonStyle(
            variant: variant, size: size, fullWidth: fullWidth,
            tint: tint, onTint: onTint
        )
    }
}

// MARK: - Badge

/// `badgeVariants` from `src/components/ui/badge.tsx`: a 20pt pill, 12pt medium
/// text, 12pt icon.
struct WebBadge: View {
    enum Variant { case primary, secondary, outline, destructive, ghost, tinted }

    let text: String
    var icon: Lucide? = nil
    var variant: Variant = .secondary
    /// Fill and text color for `.tinted` — status badges, folder colors, agent
    /// hues. Every other variant ignores it.
    var tint: Color = WebTheme.primary

    var body: some View {
        HStack(spacing: WebTheme.Space.one) {
            if let icon {
                LucideIcon(icon, size: WebTheme.Size.iconSmall)
            }
            Text(verbatim: text)
                .webText(.xs, .medium)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, variant == .outline ? 7 : 8)
        .frame(height: WebTheme.Size.badge)
        .background {
            Capsule(style: .continuous).fill(fill)
        }
        .overlay {
            if variant == .outline {
                Capsule(style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1)
            }
        }
        .fixedSize()
    }

    private var fill: Color {
        switch variant {
        case .primary: WebTheme.primary
        case .secondary: WebTheme.secondary
        case .outline: WebTheme.inputSoft
        case .destructive: WebTheme.destructiveSoft
        case .ghost: .clear
        case .tinted: tint.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: WebTheme.primaryForeground
        case .secondary: WebTheme.secondaryForeground
        case .outline: WebTheme.foreground
        case .destructive: WebTheme.destructive
        case .ghost: WebTheme.mutedForeground
        case .tinted: tint
        }
    }
}

// MARK: - Card

/// `src/components/ui/card.tsx`: `bg-card` + `rounded-2xl` +
/// `ring-1 ring-foreground/10`. No shadow — the ring *is* the elevation, which
/// is the single biggest visual difference from the app's previous Liquid Glass
/// plates.
struct WebCard<Content: View>: View {
    /// The web's `data-size`: `default` is py-6/px-6, `sm` py-4/px-4. `sm` is the
    /// iOS default — 24pt of padding eats a phone's width.
    enum Size { case regular, small, none }

    var size: Size = .small
    var cornerRadius: CGFloat = WebTheme.Radius.xl2
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .webCardSurface(cornerRadius: cornerRadius)
    }

    private var contentPadding: CGFloat {
        switch size {
        case .regular: WebTheme.Space.six
        case .small: WebTheme.Space.four
        case .none: 0
        }
    }
}

extension View {
    /// The Card surface on its own — for views that own their padding.
    func webCardSurface(cornerRadius: CGFloat = WebTheme.Radius.xl2) -> some View {
        self
            .background(
                WebTheme.card,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WebTheme.cardRing, lineWidth: 1)
            }
    }

    /// A floating surface — toasts, jump buttons, popovers: `bg-popover` with a
    /// 1px border, in whatever shape the call site floats in. The web's floating
    /// elements are opaque and bordered, never translucent; that is the direct
    /// replacement for a Liquid Glass plate, which needed a busy backdrop to
    /// read as anything at all.
    func webPopoverSurface<S: InsettableShape>(_ shape: S) -> some View {
        background(WebTheme.popover, in: shape)
            .overlay { shape.strokeBorder(WebTheme.border, lineWidth: 1) }
    }

    /// A muted inset surface — `bg-muted` panels, code blocks, nested groups.
    func webMutedSurface(cornerRadius: CGFloat = WebTheme.Radius.xl) -> some View {
        background(
            WebTheme.muted,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// A 1px hairline border in the `--border` token.
    func webBorder(cornerRadius: CGFloat, color: Color = WebTheme.border) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        }
    }
}

// MARK: - Rows

/// The sidebar row shape shared by conversations and nav items
/// (`sidebar-conversation-card.tsx`, `sidebar.tsx`): a full pill, 31–32pt tall,
/// transparent at rest, `bg-sidebar-primary/8` when selected. No border, no
/// shadow, no card — the list reads as text on a wash.
struct WebRowStyle: ButtonStyle {
    var isSelected: Bool = false
    var height: CGFloat? = 31

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule(style: .continuous).fill(background(pressed: configuration.isPressed))
            }
            .contentShape(Capsule(style: .continuous))
            .animation(WebTheme.Motion.press, value: configuration.isPressed)
    }

    private func background(pressed: Bool) -> Color {
        if isSelected { return WebTheme.sidebarPrimary.opacity(0.08) }
        return pressed ? WebTheme.sidebarAccent : .clear
    }
}

extension ButtonStyle where Self == WebRowStyle {
    static func webRow(selected: Bool = false, height: CGFloat? = 31) -> WebRowStyle {
        WebRowStyle(isSelected: selected, height: height)
    }
}

/// A press response for rows that are *not* pill-shaped (settings rows, cards
/// acting as buttons): no shape change, just the web's short color/nudge beat.
struct WebPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.70 : 1)
            .animation(WebTheme.Motion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The conversation list's signature: a 2pt vertical rail running the full row
/// height with the agent glyph centered on it, and a status dot notched into the
/// glyph's corner. Ported from the `--conv-rail-axis` construction in
/// `sidebar-conversation-card.tsx`.
struct WebRailMarker<Marker: View>: View {
    /// Distance from the row's leading edge to the rail's center axis
    /// (`--conv-rail-axis`, 0.875rem at depth 0).
    var axis: CGFloat = 14
    /// Nesting depth — a sub-session indents one step per level, with its
    /// ancestors' rails continuing behind it.
    var depth: Int = 0
    var glyphSize: CGFloat = 12
    var showsRail: Bool = true
    @ViewBuilder var marker: () -> Marker

    /// One indent step (`CONV_RAIL_DEPTH_STEP`).
    static var depthStep: CGFloat { 14 }

    private var ownAxis: CGFloat { axis + CGFloat(depth) * Self.depthStep }

    var body: some View {
        ZStack(alignment: .leading) {
            if showsRail {
                // Ancestor rails stay continuous behind a nested row.
                ForEach(Array(0..<max(depth, 0)), id: \.self) { level in
                    rail.offset(x: axis + CGFloat(level) * Self.depthStep)
                }
                rail.offset(x: ownAxis)
            }
            marker()
                .frame(width: glyphSize, height: glyphSize)
                .offset(x: ownAxis - glyphSize / 2)
        }
        .frame(width: ownAxis + glyphSize / 2)
    }

    private var rail: some View {
        Rectangle()
            .fill(WebTheme.sidebarBorder)
            .frame(width: 2)
            .offset(x: -1)
    }
}

/// `conversation-status-dot.tsx`: a filled dot ringed in the row's own
/// background so it reads as notched out of the glyph beneath it.
struct WebStatusDot: View {
    let color: Color
    var size: CGFloat = 6
    var ringColor: Color = WebTheme.sidebar

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(ringColor, lineWidth: 2)
                    .padding(-1)
            }
    }
}

// MARK: - Inputs

/// `src/components/ui/input.tsx`: 36pt tall, `bg-input/30`, 1px border,
/// `rounded-4xl`; focused it takes `border-ring` plus the 3pt `ring-ring/50`
/// halo, which is the web's most distinctive focus treatment.
struct WebTextFieldStyle: ViewModifier {
    var isFocused: Bool = false
    var height: CGFloat? = WebTheme.Size.control
    var cornerRadius: CGFloat? = nil

    /// Pill by default (`rounded-4xl`); the multi-line variant passes a radius.
    private var radius: CGFloat { cornerRadius ?? WebTheme.Radius.xl4 }

    func body(content: Content) -> some View {
        content
            .webText(.sm)
            .foregroundStyle(WebTheme.foreground)
            .tint(WebTheme.primary)
            .padding(.horizontal, WebTheme.Space.three)
            .frame(height: height)
            .background(
                WebTheme.inputSoft,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isFocused ? WebTheme.ring : WebTheme.border, lineWidth: 1)
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .strokeBorder(WebTheme.focusRing, lineWidth: 3)
                        .padding(-3)
                }
            }
            .animation(WebTheme.Motion.chrome, value: isFocused)
    }
}

extension View {
    /// Style a `TextField` / `SecureField` as the web's input.
    func webInput(isFocused: Bool = false, height: CGFloat? = WebTheme.Size.control) -> some View {
        modifier(WebTextFieldStyle(isFocused: isFocused, height: height))
    }

    /// Multi-line variant (composer, notes): a rounded rectangle rather than a
    /// pill, and no fixed height.
    func webTextArea(isFocused: Bool = false) -> some View {
        modifier(
            WebTextFieldStyle(
                isFocused: isFocused,
                height: nil,
                cornerRadius: WebTheme.Radius.xl2
            )
        )
    }
}

/// `src/components/ui/switch.tsx` — 1.15rem × 2rem track, `bg-primary` when on.
struct WebSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: WebTheme.Space.three) {
                configuration.label
                    .webText(.sm)
                    .foregroundStyle(WebTheme.foreground)
                Spacer(minLength: WebTheme.Space.two)
                track(isOn: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .animation(WebTheme.Motion.chrome, value: configuration.isOn)
    }

    private func track(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isOn ? WebTheme.primary : WebTheme.input)
            .frame(width: 32, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? WebTheme.primaryForeground : WebTheme.background)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
    }
}

extension ToggleStyle where Self == WebSwitchStyle {
    static var web: WebSwitchStyle { WebSwitchStyle() }
}

// MARK: - Tabs, chips, separators

/// One tab in ``WebTabs``.
struct WebTabItem<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var icon: Lucide? = nil

    var id: Value { value }
}

/// `src/components/ui/tabs.tsx`: a `bg-muted` pill track with the active tab
/// filled in `bg-background`.
struct WebTabs<Value: Hashable>: View {
    let items: [WebTabItem<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: WebTheme.Space.one) {
                        if let icon = item.icon {
                            LucideIcon(icon, size: WebTheme.Size.iconSmall)
                        }
                        Text(verbatim: item.label)
                            .webText(.xs, .medium)
                    }
                    .foregroundStyle(
                        selection == item.value ? WebTheme.foreground : WebTheme.mutedForeground
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background {
                        if selection == item.value {
                            Capsule(style: .continuous)
                                .fill(WebTheme.background)
                                .webBorder(cornerRadius: WebTheme.Radius.full, color: WebTheme.cardRing)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(WebTheme.muted, in: Capsule(style: .continuous))
        .animation(WebTheme.Motion.chrome, value: selection)
    }
}

/// A filter/selection chip — the badge shape made tappable, used by the session
/// list's folder filters.
struct WebChip: View {
    let title: String
    var icon: Lucide? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WebTheme.Space.one) {
                if let icon {
                    LucideIcon(icon, size: WebTheme.Size.iconSmall)
                }
                Text(verbatim: title)
                    .webText(.xs, .medium)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? WebTheme.primaryForeground : WebTheme.mutedForeground)
            .padding(.horizontal, WebTheme.Space.two)
            .frame(height: WebTheme.Size.controlTiny)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? WebTheme.primary : WebTheme.muted)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(WebTheme.Motion.chrome, value: isSelected)
    }
}

/// `src/components/ui/separator.tsx` — a 1px `--border` line.
struct WebSeparator: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(WebTheme.border)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

/// `src/components/ui/skeleton.tsx` — `bg-muted` with a slow pulse.
struct WebSkeleton: View {
    var width: CGFloat?
    var height: CGFloat = 14
    var cornerRadius: CGFloat = WebTheme.Radius.md
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(WebTheme.muted)
            .frame(width: width, height: height)
            .opacity(isPulsing ? 0.45 : 1)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

/// A sidebar section header — `sidebar-section-header.tsx`.
///
/// The label is `text-[0.875rem] font-normal` (14pt regular, the list's own
/// size) in `sidebar-foreground/50` — deliberately NOT `muted-foreground` and
/// not a smaller step. The web's own comment is explicit that an earlier "looks
/// a different size" complaint was pure contrast: same family, same size, just
/// lighter. A 32pt row at an 8pt inset, with an optional disclosure chevron
/// after the label (rotated a quarter turn when the section is open).
struct WebSectionHeader<Trailing: View>: View {
    let title: String
    var icon: Lucide? = nil
    /// `nil` draws no chevron. The web reveals it on hover when expanded but
    /// keeps it permanently visible under `[@media(hover:none)]` — which is
    /// every touch device, so it always shows here.
    var expanded: Bool? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: WebTheme.Space.onePointFive) {
            if let icon {
                LucideIcon(icon, size: WebTheme.Size.iconSmall)
            }
            Text(verbatim: title)
                .webText(.sm)
                .lineLimit(1)
                .truncationMode(.tail)
            if let expanded {
                LucideIcon(.chevronRight, size: WebTheme.Size.iconSmall)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .animation(WebTheme.Motion.expand, value: expanded)
            }
            Spacer(minLength: WebTheme.Space.two)
            trailing()
        }
        .foregroundStyle(WebTheme.sidebarForeground.opacity(0.5))
        .frame(height: WebTheme.Size.controlSmall)
        .padding(.horizontal, WebTheme.Space.two)
    }
}

extension WebSectionHeader where Trailing == EmptyView {
    init(title: String, icon: Lucide? = nil, expanded: Bool? = nil) {
        self.init(title: title, icon: icon, expanded: expanded) { EmptyView() }
    }
}

/// A count pill of the kind the sidebar puts at the end of a nav row
/// (`bg-primary/10 text-primary`, mono digits so it doesn't jitter as it ticks).
struct WebCountPill: View {
    let count: Int
    var tone: Tone = .neutral

    enum Tone { case neutral, alert }

    var body: some View {
        Text(verbatim: "\(count)")
            .font(WebTheme.mono(10, .medium))
            .monospacedDigit()
            .foregroundStyle(tone == .alert ? WebTheme.destructive : WebTheme.primary)
            .padding(.horizontal, WebTheme.Space.one)
            .frame(minWidth: 15, minHeight: 15)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        tone == .alert
                            ? WebTheme.destructive.opacity(0.15)
                            : WebTheme.primarySoft
                    )
            }
    }
}
