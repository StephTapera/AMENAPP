// BereanThreadCapsule.swift
// AMEN App — Morphing thread navigation header for BereanChatView.
// Dynamic Island-style capsule that expands to reveal thread microstate.
// Agent E — Berean AI Chat UI rebuild, 2026-05-27.

import SwiftUI

// MARK: - BereanThreadCapsule

/// Persistent thread navigation header that lives above the message list.
/// At rest it shows a compact glass pill with title + microstate summary.
/// Tapping it expands into a glass drawer revealing mode, references, memory,
/// and theological lens. Scrolling past 60pt collapses it to a minimal
/// back-affordance chevron + mode icon.
struct BereanThreadCapsule: View {

    // MARK: - Public Interface

    let threadTitle: String
    let mode: BereanPersonalityMode
    let verseCount: Int
    let docCount: Int
    let memoryOn: Bool
    let theologicalLens: String?   // nil = not set

    @Binding var scrollOffset: CGFloat
    var onBackTapped: () -> Void

    // MARK: - Private State

    @State private var isExpanded: Bool = false
    @Namespace private var capsuleNamespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Computed Layout

    /// True when the parent scroll position has pushed past the auto-collapse threshold.
    private var isScrollCollapsed: Bool { scrollOffset > 60 }

    // MARK: - Springs

    private var expandSpring: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var fastSettle: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.28, dampingFraction: 0.88)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedDrawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isScrollCollapsed {
                collapsedChevron
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            } else {
                compactCapsule
                    .transition(.opacity)
            }
        }
        .animation(expandSpring, value: isExpanded)
        .animation(fastSettle, value: isScrollCollapsed)
    }

    // MARK: - Compact Capsule (default resting state)

    private var compactCapsule: some View {
        Button {
            withAnimation(expandSpring) { isExpanded = true }
        } label: {
            HStack(spacing: 8) {
                // Mode icon
                Image(systemName: mode.icon)
                    .font(AMENFont.medium(13))
                    .foregroundColor(BereanColor.textSecondary)
                    .accessibilityHidden(true)

                // Thread title + microstate
                VStack(alignment: .leading, spacing: 1) {
                    Text(threadTitle)
                        .font(BereanType.caption())
                        .foregroundColor(BereanColor.textPrimary)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: "capsuleTitle", in: capsuleNamespace)

                    Text(microstateLabel)
                        .font(AMENFont.regular(11))
                        .foregroundColor(BereanColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Memory indicator dot
                if memoryOn {
                    Circle()
                        .fill(Color.amenGold)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(capsuleBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thread: \(threadTitle). \(microstateLabel). Tap to expand thread details.")
        .accessibilityHint("Shows current mode, references, and memory status")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Scroll-collapsed: back chevron + tiny mode icon

    private var collapsedChevron: some View {
        HStack(spacing: 8) {
            // Back button — 44×44 minimum tap target
            Button(action: onBackTapped) {
                Image(systemName: "chevron.left")
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(BereanColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            .accessibilityHint("Go back to previous screen")

            // Tiny mode pill
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(AMENFont.regular(11))
                    .foregroundColor(BereanColor.textSecondary)
                    .accessibilityHidden(true)
                Text(mode.rawValue)
                    .font(AMENFont.regular(11))
                    .foregroundColor(BereanColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        reduceTransparency ? nil :
                            Capsule().fill(BereanColor.glassFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                    )
            )
            // Fix 4: Mode pill is visible and meaningful to VoiceOver users
            // while the compact capsule is scroll-collapsed — do not hide it.
            .accessibilityLabel("Mode: \(mode.rawValue)")
            .accessibilityHidden(false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    // MARK: - Expanded Drawer

    private var expandedDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row: title + dismiss
            HStack(alignment: .center, spacing: 0) {
                Text(threadTitle)
                    .font(BereanType.headline())
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(2)
                    .matchedGeometryEffect(id: "capsuleTitle", in: capsuleNamespace)

                Spacer(minLength: 12)

                // Dismiss button — 44×44 minimum tap target
                Button {
                    withAnimation(expandSpring) { isExpanded = false }
                } label: {
                    ZStack {
                        Circle()
                            .fill(reduceTransparency
                                ? Color(uiColor: .tertiarySystemBackground)
                                : BereanColor.glassFill)
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(AMENFont.semiBold(12))
                            .foregroundColor(BereanColor.textSecondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss thread details")
                .accessibilityHint("Collapses back to compact view")
            }

            // Mode pill
            HStack(spacing: 8) {
                BereanPersonalityPill(mode: mode)
                    .accessibilityLabel("Mode: \(mode.rawValue)")
                Spacer(minLength: 0)
            }

            // Reference counts row
            if verseCount > 0 || docCount > 0 {
                HStack(spacing: 12) {
                    if verseCount > 0 {
                        DrawerChip(
                            icon: "book.closed",
                            label: "\(verseCount) \(verseCount == 1 ? "verse" : "verses")"
                        )
                    }
                    if docCount > 0 {
                        DrawerChip(
                            icon: "doc.text",
                            label: "\(docCount) \(docCount == 1 ? "doc" : "docs")"
                        )
                    }
                    Spacer(minLength: 0)
                }
            }

            // Memory chip
            DrawerChip(
                icon: memoryOn ? "brain.head.profile" : "brain",
                label: "Memory: \(memoryOn ? "on" : "off")",
                accent: memoryOn ? Color.amenGold : BereanColor.textTertiary
            )
            .accessibilityLabel("Memory is currently \(memoryOn ? "on" : "off")")

            // Theological lens (optional)
            if let lens = theologicalLens {
                DrawerChip(
                    icon: "eyeglasses",
                    label: lens
                )
                .accessibilityLabel("Theological lens: \(lens)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(expandedBackground)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var capsuleBackground: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
                .shadow(color: BereanColor.shadowColor.opacity(0.06), radius: 6, y: 2)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(BereanColor.glassFill))
                .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
                .shadow(color: BereanColor.shadowColor.opacity(0.08), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    private var expandedBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
                .shadow(color: BereanColor.shadowColor.opacity(0.10), radius: 14, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(BereanColor.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.48),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: BereanColor.shadowColor.opacity(0.10), radius: 16, y: 5)
        }
    }

    // MARK: - Helpers

    private var microstateLabel: String {
        var parts: [String] = [mode.rawValue]
        if verseCount > 0 { parts.append("\(verseCount) \(verseCount == 1 ? "verse" : "verses")") }
        if docCount > 0 { parts.append("\(docCount) \(docCount == 1 ? "doc" : "docs")") }
        if memoryOn { parts.append("memory on") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - DrawerChip (internal helper)

/// Small metadata chip used inside the expanded drawer.
private struct DrawerChip: View {
    let icon: String
    let label: String
    var accent: Color = BereanColor.textSecondary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AMENFont.regular(12))
                .foregroundColor(accent)
                .accessibilityHidden(true)
            Text(label)
                .font(BereanType.caption())
                .foregroundColor(BereanColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(reduceTransparency
                    ? Color(uiColor: .tertiarySystemBackground)
                    : BereanColor.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.4)
                )
        )
    }
}

// MARK: - Previews

#Preview("Compact — memory on") {
    VStack {
        BereanThreadCapsule(
            threadTitle: "Romans 8 Deep Study",
            mode: .scholar,
            verseCount: 3,
            docCount: 1,
            memoryOn: true,
            theologicalLens: "Reformed",
            scrollOffset: .constant(0),
            onBackTapped: {}
        )
        .padding(.horizontal, 16)

        Spacer()
    }
    .padding(.top, 60)
    .background(BereanColor.background)
}

#Preview("Scroll-collapsed") {
    VStack {
        BereanThreadCapsule(
            threadTitle: "Prayer for Anxiety",
            mode: .shepherd,
            verseCount: 0,
            docCount: 0,
            memoryOn: false,
            theologicalLens: nil,
            scrollOffset: .constant(80),
            onBackTapped: {}
        )
        .padding(.horizontal, 8)

        Spacer()
    }
    .padding(.top, 60)
    .background(BereanColor.background)
}

#Preview("Expanded drawer") {
    struct ExpandedPreview: View {
        @State private var offset: CGFloat = 0
        var body: some View {
            VStack {
                BereanThreadCapsule(
                    threadTitle: "The Sermon on the Mount — Matthew 5–7",
                    mode: .deepStudy,
                    verseCount: 7,
                    docCount: 2,
                    memoryOn: true,
                    theologicalLens: "Baptist",
                    scrollOffset: $offset,
                    onBackTapped: {}
                )
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 60)
            .background(BereanColor.background)
            .onAppear {
                // Delay so preview renders expanded state
            }
        }
    }
    return ExpandedPreview()
}
