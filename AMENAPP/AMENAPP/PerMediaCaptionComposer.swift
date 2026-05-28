import SwiftUI

// MARK: - Per-Media Caption Composer
// Inline Liquid Glass caption editor shown below the CreatePost carousel.
// Bound to the active FrameCaptionDraft; only the current slide is editable at a time.

struct PerMediaCaptionComposer: View {
    @Binding var draft: FrameCaptionDraft
    let index: Int
    let totalCount: Int
    let mediaType: PostMediaType
    let altTextEnabled: Bool
    let scriptureEnabled: Bool
    var reflectionEnabled: Bool = true
    var isModerating: Bool = false
    var isGeneratingAltText: Bool = false
    var statusMessage: String? = nil
    var errorMessage: String? = nil
    var onCaptionFocusChanged: (Bool) -> Void = { _ in }
    var onClearCaption: () -> Void = {}
    var onScriptureTapped: () -> Void = {}
    var onReflectionTapped: () -> Void = {}
    var onAltTextTapped: () -> Void = {}
    var onGenerateAltText: () -> Void = {}

    @FocusState private var captionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let captionLimit = 2200

    private var headerLabel: String {
        let position = "\(index + 1) of \(totalCount)"
        switch mediaType {
        case .image: return "Caption for photo \(position)"
        case .video: return "Caption for video \(position)"
        }
    }

    private var placeholderText: String {
        switch mediaType {
        case .image: return "Add a caption for this photo"
        case .video: return "Add a caption for this video"
        }
    }

    private var captionCount: Int { draft.text.count }
    private var nearLimit: Bool { captionCount > captionLimit - 200 }
    private var overLimit: Bool { captionCount > captionLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            captionField
            if nearLimit { characterCountRow }
            if overLimit { limitWarning }
            moderationStatusRow
            if altTextEnabled || scriptureEnabled || reflectionEnabled {
                chipRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(composerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(composerBorder)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerLabel)
        .accessibilityHint("This caption appears only on this media item.")
        .onChange(of: captionFocused) { _, focused in
            onCaptionFocusChanged(focused)
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: mediaType == .video ? "video.fill" : "photo.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(headerLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isModerating {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Checking caption safety")
            }
            if !draft.text.isEmpty {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        draft.text = ""
                        draft.captionModerationState = .notRequired
                        onClearCaption()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isModerating)
                .accessibilityLabel("Clear caption")
            }
        }
    }

    private var captionField: some View {
        TextField(placeholderText, text: $draft.text, axis: .vertical)
            .font(.body)
            .foregroundStyle(.primary)
            .lineLimit(1...5)
            .focused($captionFocused)
            .disabled(isModerating)
            .onChange(of: draft.text) { _, new in
                if new.count > captionLimit {
                    draft.text = String(new.prefix(captionLimit))
                }
                if draft.captionModerationState == .rejected {
                    draft.captionModerationState = .notRequired
                }
            }
            .accessibilityLabel(headerLabel)
            .accessibilityHint("Type a caption for this media item only.")
    }

    private var characterCountRow: some View {
        HStack {
            Spacer()
            Text("\(captionCount)/\(captionLimit)")
                .font(.caption2)
                .foregroundStyle(overLimit ? .red : .secondary)
                .monospacedDigit()
        }
    }

    private var limitWarning: some View {
        Label("Caption is too long. Shorten it before posting.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private var moderationStatusRow: some View {
        if draft.captionModerationState == .rejected {
            Label(errorMessage ?? "This caption needs edits before posting.", systemImage: "shield.slash.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let errorMessage, !errorMessage.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let statusMessage, !statusMessage.isEmpty {
            Label(statusMessage, systemImage: draft.captionModerationState == .approved ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(draft.captionModerationState == .approved ? .green : .secondary)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if scriptureEnabled {
                    PerMediaCaptionChip(
                        icon: "book.closed.fill",
                        label: draft.scriptureRefs.isEmpty ? "Scripture" : "\(draft.scriptureRefs.count) verse\(draft.scriptureRefs.count == 1 ? "" : "s")",
                        isActive: !draft.scriptureRefs.isEmpty,
                        isEnabled: !isModerating && !isGeneratingAltText,
                        action: onScriptureTapped
                    )
                }
                if reflectionEnabled {
                    PerMediaCaptionChip(
                        icon: "heart.text.square.fill",
                        label: draft.reflectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reflection" : "Reflection done",
                        isActive: !draft.reflectionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        isEnabled: !isModerating && !isGeneratingAltText,
                        action: onReflectionTapped
                    )
                }
                if altTextEnabled {
                    PerMediaCaptionChip(
                        icon: "a.magnify",
                        label: draft.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Alt Text" : "Alt Text done",
                        isActive: !draft.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        isEnabled: !isModerating && !isGeneratingAltText,
                        action: onAltTextTapped
                    )
                    PerMediaCaptionChip(
                        icon: isGeneratingAltText ? "hourglass" : "sparkles",
                        label: isGeneratingAltText ? "Generating" : "Suggest Alt",
                        isActive: isGeneratingAltText,
                        isEnabled: !isModerating && !isGeneratingAltText,
                        action: onGenerateAltText
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var composerBackground: some View {
        if reduceTransparency {
            Color(UIColor.systemBackground)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    private var composerBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 0.5)
    }

    private var borderColor: Color {
        switch draft.captionModerationState {
        case .rejected:
            return .orange.opacity(0.5)
        case .pending:
            return .yellow.opacity(0.45)
        case .approved:
            return .green.opacity(0.35)
        case .notRequired, .removed:
            return .white.opacity(0.25)
        }
    }
}

// MARK: - Chip

struct PerMediaCaptionChip: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(chipBackground)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isActive ? 0.35 : 0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Color(UIColor.secondarySystemBackground)
        } else {
            Rectangle().fill(isActive ? .thinMaterial : .ultraThinMaterial)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    @Previewable @State var draft = FrameCaptionDraft(frameIndex: 0)
    VStack {
        Spacer()
        PerMediaCaptionComposer(
            draft: $draft,
            index: 0,
            totalCount: 3,
            mediaType: .image,
            altTextEnabled: true,
            scriptureEnabled: true
        )
        .padding()
        Spacer()
    }
    .background(Color(UIColor.systemGroupedBackground))
}
#endif
