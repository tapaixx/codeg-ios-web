import SwiftUI

/// A masked secret entry with a reveal toggle — used for every agent API key /
/// token (claude/codex/gemini/cline/opencode/openclaw). Mirrors the web's
/// password inputs with a show/hide eye. The value is held in-memory only and
/// sent straight to the dedicated endpoints; it is never persisted on device.
struct SecretField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)? = nil

    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .font(.mono(13))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .textContentType(.password)
            .onChange(of: text) { _, _ in onCommit?() }

            if !text.isEmpty {
                Button {
                    revealed.toggle()
                } label: {
                    LucideIcon(revealed ? .eyeOff : .eye, size: WebTheme.Size.icon)
                        .foregroundStyle(WebTheme.mutedForeground)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Hide" : "Show")
            }
        }
    }
}
