import SwiftUI

/// Shared metrics for grouped Settings rows so the inset divider lines up under
/// the title, past the leading icon.
///
/// The leading glyph is now a bare 16pt Lucide icon rather than a 29pt
/// accent-filled rounded square: the web's settings rows put a
/// `size-4 text-muted-foreground` icon next to the label and nothing else. That
/// one change is most of why the ported Settings screens stop reading as iOS
/// grouped lists.
enum SettingsRowMetrics {
    /// Leading glyph box (`size-4`). Named `badgeSize` still — the call sites
    /// that lay out around it don't care that it stopped being a badge.
    static let badgeSize: CGFloat = WebTheme.Size.icon
    static let iconGap: CGFloat = 10
    static let hInset: CGFloat = 16
    static let vInset: CGFloat = 11
    /// Leading inset for the inter-row divider: aligns with the title text.
    static var dividerInset: CGFloat { hInset + badgeSize + iconGap }
}

/// The leading icon on a Settings row: a plain Lucide glyph in
/// `--muted-foreground`.
///
/// `tint` is kept in the signature (a few rows color their icon to signal
/// destructive or status meaning) but now defaults to muted rather than to the
/// accent, because the web tints these icons only for meaning.
struct SettingsIconBadge: View {
    let icon: String
    var tint: Color = WebTheme.mutedForeground

    var body: some View {
        LucideIcon(sf: icon, size: WebTheme.Size.icon)
            .foregroundStyle(tint)
            .frame(width: SettingsRowMetrics.badgeSize, height: SettingsRowMetrics.badgeSize)
    }
}

/// One row inside a grouped Settings section: leading icon, title, optional
/// trailing detail, chevron. Draws no surface of its own — the enclosing
/// ``EditorSection`` provides it and rows are separated by
/// ``SettingsRowDivider``. The whole row is hit-testable.
struct SettingsGroupedRowLabel: View {
    let icon: String
    var tint: Color = WebTheme.mutedForeground
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil

    var body: some View {
        HStack(spacing: SettingsRowMetrics.iconGap) {
            SettingsIconBadge(icon: icon, tint: tint)
            Text(title)
                .webText(.sm)
                .foregroundStyle(WebTheme.foreground)
            Spacer(minLength: WebTheme.Space.two)
            if let detail {
                Text(detail)
                    .webText(.sm)
                    .foregroundStyle(WebTheme.mutedForeground)
                    .lineLimit(1)
            }
            LucideIcon(.chevronRight, size: 14)
                .foregroundStyle(WebTheme.mutedForeground)
        }
        .padding(.horizontal, SettingsRowMetrics.hInset)
        .padding(.vertical, SettingsRowMetrics.vInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()) // whole-row hit area — fixes dead-zone taps
    }
}

/// A whole-row `NavigationLink` to a leaf Settings screen. Value-based, so the
/// same row serves taps and programmatic / deep-link navigation.
struct SettingsGroupedNavRow<Value: Hashable>: View {
    let icon: String
    var tint: Color = WebTheme.mutedForeground
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            SettingsGroupedRowLabel(icon: icon, tint: tint, title: title, detail: detail)
        }
        .buttonStyle(.plain)
    }
}

/// Inset hairline between grouped rows. A thin alias over ``InsetDivider`` at
/// the Settings row's title inset.
struct SettingsRowDivider: View {
    var body: some View {
        InsetDivider(leading: SettingsRowMetrics.dividerInset)
    }
}

/// A grouped-list single-choice row: leading glyph, title, and a trailing check
/// when selected. Shared by the Appearance (theme mode) and Language pickers.
struct SelectableRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let isSelected: Bool
    /// Tint for the leading glyph and the check. Defaults to the theme's
    /// `--primary`; callers rendering outside the theme trait's reach (the
    /// Appearance page inside the iPad Settings sheet) pass a resolved color.
    var tint: Color = WebTheme.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsRowMetrics.iconGap) {
                LucideIcon(sf: symbol, size: WebTheme.Size.icon)
                    .foregroundStyle(isSelected ? tint : WebTheme.mutedForeground)
                    .frame(width: SettingsRowMetrics.badgeSize)
                Text(title)
                    .webText(.sm)
                    .foregroundStyle(WebTheme.foreground)
                Spacer(minLength: WebTheme.Space.two)
                if isSelected {
                    LucideIcon(.check, size: WebTheme.Size.icon)
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, SettingsRowMetrics.hInset)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
    }
}

// MARK: - Generic grouped-list building blocks

/// A 1px `--border` separator whose leading inset can start under the row's
/// title (past a leading glyph). `leading: 0` draws edge-to-edge.
///
/// A plain rule now, not a `Divider` with an overlay: the web's separator is one
/// flat `bg-border` line at every density, and `Divider`'s built-in insets and
/// hairline thickness fought that.
struct InsetDivider: View {
    var leading: CGFloat = 0

    var body: some View {
        WebSeparator()
            .padding(.leading, leading)
    }
}

/// A content-agnostic borderless row for grouped lists. Draws no surface of its
/// own; the enclosing card provides the background and ``InsetDivider``s
/// separate rows. The whole row is hit-testable.
struct GroupedRow<Content: View>: View {
    var hInset: CGFloat = SettingsRowMetrics.hInset
    var vInset: CGFloat = 11
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, hInset)
            .padding(.vertical, vInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
