import SwiftUI
import PhotosUI

/// The pinned bottom compose bar, ported from the web's composer
/// (`src/components/chat/message-input.tsx`, the `codeg-composer-chrome` box).
///
/// One bordered box holds everything: attached-image thumbnails, then the
/// growing multiline field, then an action row *inside* the border — "+" on the
/// left, send (Stop while a turn streams) on the right. The "agent is working"
/// state is shown as a node at the tail of the transcript timeline (a thinking
/// tick, a running tool, a streaming reply) — not as a status line here.
///
/// The "+" owns the attachment pickers (Photo Library / Camera / Files) because
/// `PhotosPicker` / `.fileImporter` must be hosted on a view in the bar. (The
/// agent avatar lives in the session's navigation bar, not here.)
struct ComposeBar: View {
    @Binding var text: String
    let isInFlight: Bool
    let notice: String?
    let attachments: [Attachment]
    let canAttachMore: Bool
    let onAddAttachments: ([Attachment]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onNotice: (String) -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onDismissNotice: () -> Void
    /// Backs the "+" menu's text-insert pickers (quick messages / experts / commands).
    let insertModel: ComposeInsertModel

    @FocusState private var focused: Bool
    /// Bumped on each send tap to fire a light "sent" impact immediately (rather
    /// than waiting for the turn to start streaming).
    @State private var sendHaptic = 0
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var presentedInsert: ComposeInsertModel.Source?

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSend: Bool {
        (hasText || !attachments.isEmpty) && !isInFlight
    }
    private var remainingSlots: Int {
        max(0, AttachmentPrep.maxCount - attachments.count)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let notice {
                NoticeBanner(message: notice, onDismiss: onDismissNotice)
            }

            composerBox
        }
        // The web's composer is docked at a constant gutter (`px-4`), the same
        // one the transcript uses — it is a box in the column, not a floating
        // pill, so it no longer narrows when idle.
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Hosted in a bottom `safeAreaInset`. Keyboard DOWN: float a full
        // home-indicator inset (~34pt) above the edge; a small negative bottom
        // padding dips the idle bar lower while staying clear of the indicator
        // line. Keyboard UP: the inset rides just above the keyboard, so a positive
        // gap is required — the old negative pad tucked the bar *under* the
        // keyboard's top edge (part of it was obscured).
        .padding(.bottom, focused ? 8 : -10)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: max(1, remainingSlots),
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoItems) { _, items in handlePhotoItems(items) }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in addCaptured(image) }
                .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in handleFiles(result) }
        .sheet(item: $presentedInsert) { source in
            ComposeInsertSheet(source: source, model: insertModel) { transform in
                text = transform(text)
            }
        }
        .animation(Theme.Motion.expand, value: isInFlight)
        .animation(Theme.Motion.expand, value: notice)
        .animation(Theme.Motion.expand, value: attachments)
        // Keyboard-gap shift and the focus ring, kept just slightly slower than
        // the keyboard's own animation so the bar settles into place.
        .animation(.snappy(duration: 0.26), value: focused)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: sendHaptic)
    }

    // MARK: - The box

    /// The web's `codeg-composer-chrome`: a `rounded-xl` box outlined by
    /// `border-foreground/20`, holding the thumbnails, the editor, and an action
    /// row (`px-2 pb-2`) along its bottom edge. Nothing floats outside it.
    private var composerBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                AttachmentChipsView(attachments: attachments, onRemove: onRemoveAttachment)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            TextField("Message", text: $text, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...6)
                // Match the transcript body so the text you type reads at the
                // same size as the reply it produces.
                .font(Theme.Typography.messageBody)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(alignment: .bottom, spacing: 4) {
                addButton
                Spacer(minLength: 8)
                actionButton
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(WebTheme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        // Resting border is `border-foreground/20` — a touch darker than
        // `--border`, which is near-invisible at rest; focus swaps it to
        // `border-ring`, exactly the web's two states.
        .hairlineBorder(Theme.Radius.md, color: focused ? WebTheme.ring : WebTheme.foreground.opacity(0.20))
        // `focus-within:ring-[3px] ring-ring/50`. A CSS ring sits *outside* the
        // border, so the stroke is pushed out by its own width and the radius
        // grows to stay concentric.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md + 3, style: .continuous)
                .strokeBorder(WebTheme.focusRing, lineWidth: 3)
                .padding(-3)
                .opacity(focused ? 1 : 0)
        }
        // The whole box reads as one editable surface: tapping its blank chrome
        // focuses the editor. Controls inside take their own taps first.
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .onTapGesture { focused = true }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var addButton: some View {
        Menu {
            // Attach images. Disabled per-item when the attachment budget is full,
            // so the insert actions below stay reachable.
            Section("Attach") {
                Button { showPhotoPicker = true } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                .disabled(!canAttachMore)
                if isCameraAvailable {
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .disabled(!canAttachMore)
                }
                Button { showFileImporter = true } label: {
                    Label("Files", systemImage: "folder")
                }
                .disabled(!canAttachMore)
            }
            // Insert text: quick messages, expert mentions, slash commands.
            Section("Insert") {
                ForEach(ComposeInsertModel.Source.allCases) { source in
                    Button { presentedInsert = source } label: {
                        Label(source.title, systemImage: source.systemImage)
                    }
                }
            }
        } label: {
            // `variant="ghost" size="icon-xs" text-muted-foreground` with a
            // `size-4` plus — a 16pt glyph in a 24pt box.
            LucideIcon(.plus, size: WebTheme.Size.icon)
                .foregroundStyle(WebTheme.mutedForeground)
        }
        .buttonStyle(.web(.ghost, .iconTiny))
        .accessibilityLabel("Add or insert")
    }

    /// `actionButtons` in `message-input.tsx`: a 32pt (`h-8 w-8`) primary Send,
    /// swapping to a destructive Square while a turn is in flight. The web sends
    /// with a paper plane, not an arrow.
    @ViewBuilder
    private var actionButton: some View {
        if isInFlight {
            Button(action: onStop) {
                LucideIcon(.square, size: WebTheme.Size.icon)
            }
            .buttonStyle(.web(.destructive, .iconSmall))
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Stop")
        } else {
            Button(action: send) {
                LucideIcon(.send, size: WebTheme.Size.icon)
            }
            .buttonStyle(.web(.primary, .iconSmall))
            .disabled(!canSend)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Send")
        }
    }

    private func send() {
        guard canSend else { return }
        sendHaptic &+= 1
        onSend()
    }

    // MARK: - Attachment intake

    private func handlePhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let slots = remainingSlots
        let attempted = items.count
        Task { @MainActor in
            var prepared: [Attachment] = []
            for item in items.prefix(slots) {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                if let attachment = await Task.detached(priority: .userInitiated, operation: {
                    AttachmentPrep.make(fromImageData: data, name: "image")
                }).value {
                    prepared.append(attachment)
                }
            }
            // Notice first so the view model's more specific size/count notice (if
            // any) wins when it also drops some during add.
            if prepared.count < attempted { onNotice("Some images couldn't be added.") }
            if !prepared.isEmpty { onAddAttachments(prepared) }
            photoItems = []
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let slots = remainingSlots
        let attempted = urls.count
        Task { @MainActor in
            var prepared: [Attachment] = []
            for url in urls.prefix(slots) {
                if let attachment = await Task.detached(priority: .userInitiated, operation: {
                    AttachmentPrep.make(fromFile: url)
                }).value {
                    prepared.append(attachment)
                }
            }
            if prepared.count < attempted { onNotice("Some images couldn't be added.") }
            if !prepared.isEmpty { onAddAttachments(prepared) }
        }
    }

    /// Camera capture is a single image and small enough to prep inline on the
    /// main actor (avoids sending a non-Sendable `UIImage` across a task boundary).
    private func addCaptured(_ image: UIImage) {
        guard remainingSlots > 0, let attachment = AttachmentPrep.make(from: image, name: "camera") else { return }
        onAddAttachments([attachment])
    }
}

/// A dismissible non-fatal notice (e.g. "a turn is already running").
private struct NoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            LucideIcon(.info, size: WebTheme.Size.iconSmall)
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(WebTheme.sans(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                LucideIcon(.x, size: 10)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .hairlineBorder(Theme.Radius.md, color: Theme.accent.opacity(0.35))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
