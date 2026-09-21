import SwiftUI

/// Appearance settings: the theme mode (Light / Dark / System) and the shadcn
/// theme preset — the same two knobs the web client's Appearance page offers
/// (`src/components/settings/appearance-settings.tsx`), with the same 12 presets
/// in the same order.
///
/// Both are device-local preferences held in `AppearanceStore`, injected into the
/// environment by `RootView`. Changing either recolors the whole app live: mode
/// via `.preferredColorScheme`, preset via the `\.webTheme` trait bridge.
///
/// This screen's own themed bits resolve their colors *explicitly* (see
/// ``resolvedPrimary``) rather than through `WebTheme`, because the bridged trait
/// doesn't cross into a separately-presented hosting controller — the iPad
/// Settings sheet — where the swatches would otherwise stay stuck on the
/// previously active preset.
struct AppearanceSettingsView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    /// The selected preset's `--primary`, resolved from the store plus the
    /// standard color-scheme trait (which *does* propagate into sheets).
    private var resolvedPrimary: Color { appearance.themeColor.primary(dark: isDark) }
    private var resolvedOnPrimary: Color { appearance.themeColor.primaryForeground(dark: isDark) }

    var body: some View {
        ZStack {
            CodegBackground()
            ScrollView {
                VStack(spacing: WebTheme.Layout.sectionSpacing) {
                    modeSection
                    themeColorSection
                    previewSection
                }
                .padding(.horizontal, WebTheme.Layout.screenHMargin)
                .padding(.top, WebTheme.Layout.screenTopInset)
                .padding(.bottom, WebTheme.Layout.screenBottomInset)
            }
            .scrollContentBackground(.hidden)
        }
        .screenTitle("Appearance", compact: horizontalSizeClass == .compact)
    }

    // MARK: - Theme mode

    private var modeSection: some View {
        EditorSection(
            title: "Theme",
            footer: "“System” follows your device's Light / Dark setting."
        ) {
            ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                if index > 0 { InsetDivider(leading: SettingsRowMetrics.dividerInset) }
                SelectableRow(symbol: mode.symbol, title: mode.titleKey,
                              isSelected: appearance.mode == mode, tint: resolvedPrimary) {
                    appearance.mode = mode
                }
            }
        }
    }

    // MARK: - Theme color

    /// The web's grid: a small round swatch plus the preset's name, three or four
    /// to a row. Deliberately not the app's old 54pt swatch circles — a theme
    /// preset recolors chrome, not a brand, so it gets a chip, not a hero.
    private var themeColorSection: some View {
        EditorSection(
            title: "Theme Color",
            footer: "The shadcn preset the web client uses. Grayscale presets keep the UI monochrome; the colored ones tint buttons, selection, and active marks."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: WebTheme.Space.two)],
                spacing: WebTheme.Space.two
            ) {
                ForEach(WebThemeColor.allCases) { preset in
                    swatch(preset)
                }
            }
            .padding(WebTheme.Space.four)
        }
    }

    private func swatch(_ preset: WebThemeColor) -> some View {
        let isSelected = appearance.themeColor == preset
        return Button {
            appearance.themeColor = preset
        } label: {
            HStack(spacing: WebTheme.Space.two) {
                Circle()
                    .fill(preset.primary(dark: isDark))
                    .frame(width: WebTheme.Size.icon, height: WebTheme.Size.icon)
                    .webBorder(cornerRadius: WebTheme.Radius.full, color: WebTheme.cardRing)
                Text(preset.titleKey)
                    .webText(.xs, .medium)
                    .foregroundStyle(isSelected ? WebTheme.foreground : WebTheme.mutedForeground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WebTheme.Space.two)
            .frame(height: WebTheme.Size.controlSmall)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(WebTheme.muted)
                }
            }
            .overlay {
                if isSelected {
                    Capsule(style: .continuous)
                        .strokeBorder(resolvedPrimary.opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(WebTheme.Motion.chrome, value: isSelected)
    }

    // MARK: - Live preview

    /// A sample of the components the preset actually affects. Colors are the
    /// explicitly resolved ones (see ``resolvedPrimary``) so this section is
    /// correct inside the iPad Settings sheet too.
    private var previewSection: some View {
        EditorSection(title: "Preview") {
            VStack(alignment: .leading, spacing: WebTheme.Space.three) {
                HStack(spacing: WebTheme.Space.two) {
                    FilterChip(title: "Selected", systemImage: "checkmark",
                               isSelected: true, tint: resolvedPrimary,
                               onTint: resolvedOnPrimary) {}
                    FilterChip(title: "Idle", isSelected: false) {}
                    Spacer(minLength: 0)
                }
                FlatPrimaryButton(title: "Primary Action", systemImage: "sparkles",
                                  tint: resolvedPrimary, onTint: resolvedOnPrimary) {}
                HStack(spacing: WebTheme.Space.two) {
                    Circle()
                        .fill(resolvedPrimary)
                        .frame(width: 10, height: 10)
                    Text("Primary text & icons")
                        .webText(.sm, .medium)
                        .foregroundStyle(resolvedPrimary)
                    Spacer(minLength: 0)
                }
            }
            .padding(WebTheme.Space.four)
        }
    }
}
