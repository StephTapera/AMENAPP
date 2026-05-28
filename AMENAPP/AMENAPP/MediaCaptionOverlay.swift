// MediaCaptionOverlay.swift
// AMEN App — Media System
//
// Floating caption overlay for video content.
// Displays live caption text keyed to playback position.
// Gated by AMENFeatureFlags.shared.mediaNoDoomScrollGuardrailsEnabled (used as
// the caption-system proxy flag until mediaCaptionsEnabled is promoted).
// Accessibility: Dynamic Type, Reduce Motion, Reduce Transparency all respected.

import SwiftUI

// MARK: - Models

struct MediaOverlayCaptionCue: Identifiable, Equatable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    var scriptureRef: String? = nil  // e.g. "John 3:16"
}

enum MediaCaptionDisplayStyle: String, CaseIterable {
    case standard
    case large
    case highContrast
    case simplified

    var accessibilityDescription: String {
        switch self {
        case .standard:     return "Standard"
        case .large:        return "Large text"
        case .highContrast: return "High contrast"
        case .simplified:   return "Simplified"
        }
    }
}

// MARK: - View

struct AccessibleMediaCaptionOverlay: View {
    let currentCue: MediaOverlayCaptionCue?
    let captionStyle: MediaCaptionDisplayStyle
    let isEnabled: Bool
    let onScriptureTap: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Tracks last rendered cue ID so the opacity cross-fade fires only on change.
    @State private var displayedCueID: String? = nil
    @State private var contentOpacity: Double = 1.0

    // MARK: Guard

    private var shouldShow: Bool {
        isEnabled && currentCue != nil
    }

    // MARK: Typography

    private var captionFont: Font {
        switch captionStyle {
        case .standard:
            return .subheadline
        case .large:
            return .title3.weight(.regular)
        case .highContrast:
            return .subheadline.weight(.semibold)
        case .simplified:
            return .subheadline
        }
    }

    private var scriptureFont: Font {
        captionStyle == .large ? .footnote.weight(.semibold) : .caption.weight(.semibold)
    }

    // MARK: Colors

    private var textColor: Color {
        switch captionStyle {
        case .highContrast:
            return .white
        case .standard, .large, .simplified:
            return .primary
        }
    }

    private var backgroundFill: AnyShapeStyle {
        switch captionStyle {
        case .highContrast:
            // High contrast: always opaque black background regardless of transparency setting.
            return AnyShapeStyle(Color.black.opacity(0.92))
        default:
            if reduceTransparency {
                return AnyShapeStyle(Color.black.opacity(0.72))
            }
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var backgroundOverlayColor: Color {
        // Additional darkening tint on top of material for legibility
        switch captionStyle {
        case .highContrast:
            return .clear
        default:
            return reduceTransparency ? .clear : Color.black.opacity(0.28)
        }
    }

    // MARK: Corner Radius

    private var cornerRadius: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 14 : 10
    }

    // MARK: Body

    var body: some View {
        Group {
            if shouldShow, let cue = currentCue {
                captionContent(cue: cue)
                    .opacity(contentOpacity)
                    .onChange(of: cue.id) { _, newID in
                        guard newID != displayedCueID else { return }
                        if reduceMotion {
                            displayedCueID = newID
                        } else {
                            withAnimation(.easeOut(duration: 0.12)) {
                                contentOpacity = 0
                            }
                            // After fade-out, swap content and fade back in.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                                displayedCueID = newID
                                withAnimation(.easeIn(duration: 0.18)) {
                                    contentOpacity = 1
                                }
                            }
                        }
                    }
                    .onAppear {
                        displayedCueID = cue.id
                        contentOpacity = 1
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: shouldShow)
    }

    // MARK: Caption Content

    @ViewBuilder
    private func captionContent(cue: MediaOverlayCaptionCue) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cue.text)
                    .font(captionFont)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                    .accessibilityLabel(cue.text)

                if let ref = cue.scriptureRef {
                    scriptureChip(ref: ref)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(captionBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: cue))
    }

    // MARK: Scripture Chip

    @ViewBuilder
    private func scriptureChip(ref: String) -> some View {
        Button {
            onScriptureTap?(ref)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "book.fill")
                    .font(scriptureFont)
                    .accessibilityHidden(true)
                Text(ref)
                    .font(scriptureFont)
                    .lineLimit(1)
            }
            .foregroundStyle(captionStyle == .highContrast ? Color.yellow : Color.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        captionStyle == .highContrast
                            ? Color.yellow.opacity(0.18)
                            : Color.blue.opacity(reduceTransparency ? 0.15 : 0.12)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        captionStyle == .highContrast
                            ? Color.yellow.opacity(0.55)
                            : Color.blue.opacity(0.30),
                        lineWidth: 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Scripture reference: \(ref). Tap to open.")
        .accessibilityHint("Opens scripture passage")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Background

    @ViewBuilder
    private var captionBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundFill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundOverlayColor)
            }
            .overlay {
                if captionStyle != .highContrast && !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
                }
            }
    }

    // MARK: Accessibility

    private func accessibilityLabel(for cue: MediaOverlayCaptionCue) -> String {
        var parts = [cue.text]
        if let ref = cue.scriptureRef {
            parts.append("Scripture: \(ref)")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Previews

#if DEBUG
private let previewCueStandard = MediaOverlayCaptionCue(
    id: "cue-1",
    startTime: 5,
    endTime: 10,
    text: "And God so loved the world that He gave His only begotten Son.",
    scriptureRef: "John 3:16"
)

private let previewCueLong = MediaOverlayCaptionCue(
    id: "cue-2",
    startTime: 11,
    endTime: 18,
    text: "For the wages of sin is death, but the gift of God is eternal life in Christ Jesus our Lord.",
    scriptureRef: "Romans 6:23"
)

private let previewCueNoRef = MediaOverlayCaptionCue(
    id: "cue-3",
    startTime: 19,
    endTime: 25,
    text: "The Lord is my shepherd; I shall not want.",
    scriptureRef: nil
)

#Preview("Standard caption with scripture") {
    ZStack(alignment: .bottom) {
        LinearGradient(colors: [.indigo, .purple.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AccessibleMediaCaptionOverlay(
            currentCue: previewCueStandard,
            captionStyle: .standard,
            isEnabled: true,
            onScriptureTap: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}

#Preview("Large style") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        AccessibleMediaCaptionOverlay(
            currentCue: previewCueLong,
            captionStyle: .large,
            isEnabled: true,
            onScriptureTap: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}

#Preview("High contrast") {
    ZStack(alignment: .bottom) {
        LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        AccessibleMediaCaptionOverlay(
            currentCue: previewCueStandard,
            captionStyle: .highContrast,
            isEnabled: true,
            onScriptureTap: { _ in }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}

#Preview("Reduce Transparency") {
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        AccessibleMediaCaptionOverlay(
            currentCue: previewCueNoRef,
            captionStyle: .standard,
            isEnabled: true,
            onScriptureTap: nil
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}

#Preview("Hidden — disabled") {
    ZStack(alignment: .bottom) {
        Color(.systemBackground).ignoresSafeArea()
        AccessibleMediaCaptionOverlay(
            currentCue: previewCueStandard,
            captionStyle: .standard,
            isEnabled: false,
            onScriptureTap: nil
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}
#endif
