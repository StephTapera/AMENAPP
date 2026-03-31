// PostCarouselEnhancements.swift
// AMENAPP
//
// Standalone components that add scripture chips and Church Notes integration
// to carousel slides. Use alongside existing PostCarouselView.
// Does NOT modify existing carousel or post card UI.

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - CarouselScriptureChipRow

/// Horizontal row of tappable scripture reference chips shown below a carousel slide.
/// Usage: CarouselScriptureChipRow(references: ["Romans 8:28", "John 3:16"])
struct CarouselScriptureChipRow: View {
    let references: [String]
    var onChipTap: ((String) -> Void)? = nil

    // Auto-detect references from slide content if references array is empty
    private var resolvedReferences: [String] {
        if !references.isEmpty { return references }
        return []   // Callers should pass detected refs from slideContent
    }

    var body: some View {
        if resolvedReferences.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(resolvedReferences, id: \.self) { ref in
                        ScriptureChip(reference: ref) {
                            dlog("CarouselScriptureChipRow: tapped chip '\(ref)'")
                            onChipTap?(ref)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - ScriptureChip

private struct ScriptureChip: View {
    let reference: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "book.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.75))

                Text(reference)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .background(Capsule().fill(.ultraThinMaterial))
                    .clipShape(Capsule())
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scripture Reference Auto-Detection Helper

extension CarouselScriptureChipRow {
    /// Detects scripture references in a string using a simple regex pattern.
    /// e.g. "Romans 8:28" or "John 3:16-17"
    static func detectReferences(in text: String) -> [String] {
        let pattern = #"[1-3]?\s?[A-Za-z]+\s\d+:\d+(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            dlog("CarouselScriptureChipRow: failed to build scripture regex")
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        let refs = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
        dlog("CarouselScriptureChipRow: detected \(refs.count) scripture references")
        return refs
    }
}

// MARK: - CarouselSaveToNotesButton

/// Compact "Save to Church Notes" action shown on a carousel slide.
/// Usage: CarouselSaveToNotesButton(slideContent: slide.text, postTitle: post.title)
struct CarouselSaveToNotesButton: View {
    let slideContent: String
    let postTitle: String
    var onSave: ((String) -> Void)? = nil

    @State private var isSaved: Bool = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            guard !isSaved else { return }
            dlog("CarouselSaveToNotesButton: saving slide to church notes — '\(postTitle)'")
            onSave?(slideContent)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                scale = 0.95
                isSaved = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.12)) {
                scale = 1.0
            }
            // Reset after 2.5 seconds so user can save again if desired
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSaved = false
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "checkmark" : "note.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSaved ? Color.green : .primary)
                    .contentTransition(.symbolEffect(.replace))

                Text(isSaved ? "Saved" : "Save to Notes")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSaved ? Color.green : .primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSaved ? Color.green.opacity(0.12) : Color.white.opacity(0.45))
                    .background(Capsule().fill(.ultraThinMaterial))
                    .clipShape(Capsule())
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSaved ? Color.green.opacity(0.4) : Color.white.opacity(0.55),
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PostIntegrityBadge

/// Pre-publish integrity indicator for the CreatePost composition flow.
/// NOT shown on posted content — only during composition.
struct PostIntegrityBadge: View {
    enum IntegrityLevel {
        case authentic
        case assisted
        case reviewing
    }

    let level: IntegrityLevel

    @State private var isAnimatingDots: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            // Icon or animated indicator
            Group {
                switch level {
                case .authentic:
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.green.opacity(0.8))

                case .assisted:
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)

                case .reviewing:
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .opacity(isAnimatingDots ? 0.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                            value: isAnimatingDots
                        )
                }
            }

            Text(badgeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(labelColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(fillColor)
                .background(Capsule().fill(.ultraThinMaterial))
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        )
        .onAppear {
            if level == .reviewing {
                isAnimatingDots = true
            }
        }
    }

    private var badgeLabel: String {
        switch level {
        case .authentic: return "Your voice"
        case .assisted:  return "AI-assisted"
        case .reviewing: return "Reviewing..."
        }
    }

    private var labelColor: Color {
        switch level {
        case .authentic: return Color.green.opacity(0.85)
        case .assisted:  return .gray
        case .reviewing: return .gray
        }
    }

    private var fillColor: Color {
        switch level {
        case .authentic: return Color.green.opacity(0.08)
        case .assisted:  return Color.white.opacity(0.35)
        case .reviewing: return Color.white.opacity(0.35)
        }
    }
}

// MARK: - PostPinnedBadge

/// Subtle badge placed in a post header to indicate a pinned post.
/// NOT placed inside PostCard — use in profile header or feed header layer.
struct PostPinnedBadge: View {
    let pinType: PinnedPostRecord.PinType

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.7))

            Text(pinType.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.5))
                .background(Capsule().fill(.ultraThinMaterial))
                .clipShape(Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
        )
    }
}

// MARK: - PinType DisplayName Extension

extension PinnedPostRecord.PinType {
    var displayName: String {
        switch self {
        case .standard:   return "Pinned"
        case .testimony:  return "Pinned Testimony"
        case .teaching:   return "Pinned Teaching"
        case .churchNote: return "Pinned Note"
        }
    }
}

// MARK: - PreviewProvider

struct PostCarouselEnhancements_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                // Scripture chips
                CarouselScriptureChipRow(
                    references: ["Romans 8:28", "John 3:16", "Psalm 23:1"],
                    onChipTap: { ref in print("tapped: \(ref)") }
                )

                // Save to notes
                CarouselSaveToNotesButton(
                    slideContent: "Sample slide content from the carousel.",
                    postTitle: "Sunday Morning Sermon"
                )

                // Integrity badges
                HStack(spacing: 10) {
                    PostIntegrityBadge(level: .authentic)
                    PostIntegrityBadge(level: .assisted)
                    PostIntegrityBadge(level: .reviewing)
                }

                // Pinned badges
                HStack(spacing: 10) {
                    PostPinnedBadge(pinType: .standard)
                    PostPinnedBadge(pinType: .testimony)
                    PostPinnedBadge(pinType: .teaching)
                    PostPinnedBadge(pinType: .churchNote)
                }
            }
            .padding()
        }
        .previewDisplayName("Carousel Enhancements")
    }
}
