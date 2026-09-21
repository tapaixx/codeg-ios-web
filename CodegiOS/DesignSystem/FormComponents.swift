import SwiftUI

/// A titled section grouping related fields, with an optional footer — the
/// direct port of the web's settings section:
///
/// ```html
/// <section className="rounded-xl border bg-card p-4 space-y-4">
///   <div className="flex items-center gap-2">
///     <Icon className="h-4 w-4 text-muted-foreground" />
///     <h2 className="text-sm font-semibold">…</h2>
///   </div>
///   <p className="text-xs text-muted-foreground leading-5">…</p>
/// ```
///
/// Two differences from the markup, both deliberate: the title stays *above* the
/// card (the app's rows bring their own 16pt padding, so a padded section would
/// double up), and it is no longer uppercased — that was an iOS grouped-list
/// convention the web doesn't share.
struct EditorSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    /// Render the group without the card's ring (``FlatCard``). Retained for the
    /// call sites that pass it; both variants are flat now, so the difference is
    /// down to one hairline.
    var flat: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WebTheme.Space.two) {
            Text(title)
                .webText(.xs, .medium)
                .foregroundStyle(WebTheme.mutedForeground)
                .padding(.leading, WebTheme.Space.one)

            if flat {
                FlatCard(cornerRadius: Theme.Radius.md, padding: 0) {
                    VStack(spacing: 0) { content() }
                }
            } else {
                GlassCard(cornerRadius: Theme.Radius.md, padding: 0) {
                    VStack(spacing: 0) { content() }
                }
            }

            if let footer {
                Text(footer)
                    .webText(.xs)
                    .foregroundStyle(WebTheme.mutedForeground)
                    .padding(.leading, WebTheme.Space.one)
                    .padding(.top, 1)
            }
        }
    }
}

/// A labeled field row: a small label above the editable control
/// (`text-xs font-medium text-muted-foreground` + the control, `space-y-2`).
struct FieldRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WebTheme.Space.onePointFive) {
            Text(label)
                .webText(.xs, .medium)
                .foregroundStyle(WebTheme.mutedForeground)
            content()
                .webText(.sm)
                .foregroundStyle(WebTheme.foreground)
                .tint(WebTheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dropdown (select box)

/// The shared dropdown chrome, cut to `src/components/ui/select.tsx`'s trigger:
/// a bordered control showing the current value with a trailing
/// `chevrons-up-down` glyph in `--muted-foreground`. Tapping opens `menu`; pass
/// a `Picker` with `.pickerStyle(.inline)` as the content.
struct SelectBox<MenuContent: View>: View {
    private let label: Text
    private let isPlaceholder: Bool
    @ViewBuilder var menu: () -> MenuContent

    /// String display. Fixed labels (e.g. "Low") localize via a runtime catalog
    /// lookup; dynamic values (provider/model names) fall back to the key. An
    /// empty `display` shows `placeholder` (or "—") in the muted color.
    init(display: String, placeholder: String = "", @ViewBuilder menu: @escaping () -> MenuContent) {
        let empty = display.isEmpty
        self.isPlaceholder = empty
        self.label = Text(LocalizedStringKey(stringLiteral: empty ? (placeholder.isEmpty ? "—" : placeholder) : display))
        self.menu = menu
    }

    /// `LocalizedStringKey` display, for labels with format arguments (e.g.
    /// "System default (%@)") that a `stringLiteral` lookup would flatten.
    init(display: LocalizedStringKey, @ViewBuilder menu: @escaping () -> MenuContent) {
        self.isPlaceholder = false
        self.label = Text(display)
        self.menu = menu
    }

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: WebTheme.Space.two) {
                label
                    .webText(.sm)
                    .foregroundStyle(isPlaceholder ? WebTheme.mutedForeground : WebTheme.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: WebTheme.Space.two)
                LucideIcon(.chevronsUpDown, size: 14)
                    .foregroundStyle(WebTheme.mutedForeground)
            }
            .padding(.horizontal, WebTheme.Space.three)
            .frame(minHeight: WebTheme.Size.control)
            .frame(maxWidth: .infinity)
            .background(
                WebTheme.inputSoft,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .webBorder(cornerRadius: Theme.Radius.md)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }
}

/// One choice in a ``SelectField``. `id == value` so a list of options is
/// `ForEach`-able without a separate identifier.
struct SelectOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// A flat single-select dropdown bound to `selection`. Renders the selected
/// option's label in a ``SelectBox``; `placeholder` shows when nothing matches.
/// For grouped menus use ``SelectBox`` directly.
struct SelectField<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SelectOption<Value>]
    var placeholder: String = ""

    private var currentLabel: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        SelectBox(display: currentLabel, placeholder: placeholder) {
            Picker("", selection: $selection) {
                ForEach(options) { Text(LocalizedStringKey(stringLiteral: $0.label)).tag($0.value) }
            }
            .pickerStyle(.inline)
        }
    }
}
