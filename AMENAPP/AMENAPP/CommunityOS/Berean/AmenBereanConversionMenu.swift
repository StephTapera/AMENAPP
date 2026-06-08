// AmenBereanConversionMenu.swift
// AMEN App — CommunityOS / Berean
//
// Phase 2 — Agent A4 (Berean Integration)
// In-Berean conversion UI: full menu sheet + compact inline action bar.
//
// Design rules (C3):
//   - Dark glass pills for in-Berean UI (Berean has a dark/glass background).
//   - All interactive controls >= 44pt touch target.
//   - accessibilityLabel + accessibilityHint on every non-obvious element.
//   - Reduced-motion gate on all spring animations.
//   - No custom hex colors. Uses semantic system colors only.
//   - No public count display.
//
// Two public surfaces:
//   AmenBereanConversionMenu     — full-sheet conversion picker for a BereanCapture
//   AmenBereanCaptureActionBar   — compact horizontal scroll bar for use in chat bubbles

import SwiftUI
import FirebaseAuth

// MARK: - AmenBereanConversionMenu

/// Full conversion sheet shown when the user long-presses or taps the action icon
/// on a Berean answer, study plan, or scripture study output.
///
/// Shows all available conversion targets as a vertical list, triggers conversion
/// directly via `AmenBereanConversionService`, and presents a confirmation toast.
/// "Open in Composer" opens `AmenUniversalComposerView` with pre-filled content.
struct AmenBereanConversionMenu: View {

    // MARK: Inputs

    let capture: BereanCapture
    var onDismiss: (() -> Void)?

    // MARK: State

    @StateObject private var service = AmenBereanConversionService()
    @State private var showComposer = false
    @State private var composerSource: ComposerSource?
    @State private var selectedIntent: AmenIntent?
    @State private var conversionResult: BereanConversionResult?
    @State private var showSuccessToast = false

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Conversion Options

    private struct ConversionOption: Identifiable {
        let id = UUID()
        let intent: AmenIntent
        let title: String
        let subtitle: String
        let systemImage: String
    }

    private var conversionOptions: [ConversionOption] {
        [
            ConversionOption(
                intent:      .share,
                title:       "Share as Post",
                subtitle:    "Post this insight to your feed",
                systemImage: "square.and.arrow.up"
            ),
            ConversionOption(
                intent:      .discuss,
                title:       "Start Discussion",
                subtitle:    "Open a discussion room around this",
                systemImage: "bubble.left.and.bubble.right"
            ),
            ConversionOption(
                intent:      .pray,
                title:       "Create Prayer",
                subtitle:    "Turn this into a prayer request",
                systemImage: "hands.sparkles"
            ),
            ConversionOption(
                intent:      .study,
                title:       "Study Room",
                subtitle:    "Create a group Bible study from this",
                systemImage: "book.closed"
            ),
            ConversionOption(
                intent:      .mentor,
                title:       "Mentorship Topic",
                subtitle:    "Request mentorship on this question",
                systemImage: "person.badge.key"
            )
        ]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        capturePreviewSection
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 16)

                        Divider()
                            .padding(.horizontal, 16)

                        Text("Save this Berean insight as:")
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 12)

                        conversionOptionList
                            .padding(.horizontal, 16)

                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        openInComposerRow
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 32)
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))

                // Success toast
                if showSuccessToast, let result = conversionResult {
                    successToast(message: result.successMessage)
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                        .padding(.bottom, 16)
                        .padding(.horizontal, 16)
                }
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.30, dampingFraction: 0.82),
                value: showSuccessToast
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Conversion Failed", isPresented: Binding(
                get: { service.conversionError != nil },
                set: { if !$0 { service.conversionError = nil } }
            )) {
                Button("OK", role: .cancel) { service.conversionError = nil }
            } message: {
                Text(service.conversionError ?? "Please try again.")
            }
            .sheet(isPresented: $showComposer, onDismiss: { composerSource = nil }) {
                if let src = composerSource {
                    AmenUniversalComposerView(
                        source: src,
                        onDismiss: { showComposer = false }
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AmenRadius.card)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Save Berean Insight")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: - Capture Preview

    private var capturePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: capture.sourceType.systemImage)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(capture.sourceType.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )

            Text(capture.resolvedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)

            Text(capture.content)
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean insight: \(capture.resolvedTitle)")
    }

    // MARK: - Conversion Option List

    private var conversionOptionList: some View {
        VStack(spacing: 8) {
            ForEach(conversionOptions) { option in
                conversionOptionRow(option)
            }
        }
    }

    private func conversionOptionRow(_ option: ConversionOption) -> some View {
        let isProcessing = service.isConverting && selectedIntent == option.intent

        return Button {
            triggerConversion(intent: option.intent)
        } label: {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: option.systemImage)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.10))
                    )

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(uiColor: .label))
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                Spacer()

                // Loading or chevron
                if isProcessing {
                    ProgressView()
                        .tint(Color.accentColor)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(service.isConverting)
        .accessibilityLabel(option.title)
        .accessibilityHint(option.subtitle)
    }

    // MARK: - Open in Composer Row

    private var openInComposerRow: some View {
        Button {
            let src = service.openInComposer(capture, intent: .share)
            composerSource = src
            showComposer = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "pencil.and.scribble")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open in Composer")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(uiColor: .label))
                    Text("Edit before saving")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityLabel("Open in Composer")
        .accessibilityHint("Edit the Berean content before saving it")
    }

    // MARK: - Success Toast

    private func successToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(
                    color: Color.black.opacity(0.10),
                    radius: 16, x: 0, y: 6
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    // MARK: - Conversion Logic

    private func triggerConversion(intent: AmenIntent) {
        guard let actorId = Auth.auth().currentUser?.uid, !actorId.isEmpty else {
            service.conversionError = "Sign in to save Berean insights."
            return
        }

        selectedIntent = intent

        Task {
            do {
                let result: BereanConversionResult
                switch intent {
                case .share:
                    result = try await service.convertToPost(capture, actorId: actorId)
                case .discuss:
                    result = try await service.convertToDiscussion(
                        capture,
                        roomType: roomTypeForCapture(capture),
                        actorId: actorId
                    )
                case .pray:
                    result = try await service.convertToPrayerRequest(capture, actorId: actorId)
                case .study:
                    result = try await service.convertToStudyRoom(capture, actorId: actorId)
                case .mentor:
                    result = try await service.convertToMentorshipTopic(capture, actorId: actorId)
                default:
                    // Other intents route through the Composer
                    let src = service.openInComposer(capture, intent: intent)
                    composerSource = src
                    showComposer = true
                    return
                }

                conversionResult = result
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.28, dampingFraction: 0.80)
                ) {
                    showSuccessToast = true
                }

                // Auto-dismiss the toast after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { showSuccessToast = false }
                selectedIntent = nil

            } catch {
                service.conversionError = "Could not save insight. Please try again."
                selectedIntent = nil
            }
        }
    }

    /// Infers the best discussion room type from the capture's source type.
    private func roomTypeForCapture(_ capture: BereanCapture) -> AmenDiscussionRoomType {
        switch capture.sourceType {
        case .scriptureStudy, .studyPlan:
            return .bibleStudy
        case .prayerGuide:
            return .prayer
        case .sermonOutline, .answer, .devotional, .conversationExcerpt:
            return .general
        }
    }
}

// MARK: - AmenBereanCaptureActionBar

/// Compact horizontal scroll bar of dark glass action pills.
/// Designed to sit below a Berean chat bubble on the dark Berean background.
///
/// Shows 5–6 of the most contextually relevant conversion intents as
/// `.darkOverlayPill`-style capsules. Tapping an intent either triggers
/// an in-place conversion or opens the composer.
struct AmenBereanCaptureActionBar: View {

    // MARK: Inputs

    let capture: BereanCapture
    var onConvert: (AmenIntent) -> Void
    var onOpenComposer: (ComposerSource) -> Void

    // MARK: Private

    @StateObject private var service = AmenBereanConversionService()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private struct ActionPillMeta: Identifiable {
        let id = UUID()
        let intent: AmenIntent
        let label: String
        let systemImage: String
    }

    private var pillMetas: [ActionPillMeta] {
        [
            ActionPillMeta(intent: .share,   label: "Share",    systemImage: "square.and.arrow.up"),
            ActionPillMeta(intent: .discuss, label: "Discuss",  systemImage: "bubble.left.and.bubble.right"),
            ActionPillMeta(intent: .pray,    label: "Pray",     systemImage: "hands.sparkles"),
            ActionPillMeta(intent: .study,   label: "Study",    systemImage: "book.closed"),
            ActionPillMeta(intent: .mentor,  label: "Mentor",   systemImage: "person.badge.key")
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pillMetas) { meta in
                    actionPill(meta: meta)
                }

                // "Open in Composer" pill
                openComposerPill
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean insight actions")
    }

    // MARK: - Action Pill

    private func actionPill(meta: ActionPillMeta) -> some View {
        Button {
            onConvert(meta.intent)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: meta.systemImage)
                    .font(.systemScaled(12, weight: .medium))
                Text(meta.label)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(uiColor: .secondarySystemBackground)
                            : Color.white.opacity(0.18)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta.label)
        .accessibilityHint("Convert this Berean insight to a \(meta.label.lowercased())")
    }

    // MARK: - Open Composer Pill

    private var openComposerPill: some View {
        Button {
            let src = service.openInComposer(capture, intent: .share)
            onOpenComposer(src)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "pencil.and.scribble")
                    .font(.systemScaled(12, weight: .medium))
                Text("Edit")
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(uiColor: .tertiarySystemBackground)
                            : Color.white.opacity(0.10)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open in Composer")
        .accessibilityHint("Edit this Berean insight before saving")
    }
}
