//
//  SelahCalmEnhancements.swift
//  AMENAPP
//
//  Additive, calm enhancements for the existing Selah reading experience.
//  These components are designed to be lightweight, low-saturation, native,
//  and emotionally grounding. They do not replace, rename, or remove any
//  existing Selah UI — they are inline additions and view modifiers that
//  the host view (SelahView) opts into.
//
//  Nothing here ships fabricated spiritual insight. All surfaced content
//  is derived from the user's own real session activity via SelahService.
//

import SwiftUI

// MARK: - Adaptive Reading Tone

/// A subtle, time-of-day reading tone for the reading canvas.
/// Returns a near-white shade that nudges warmer in the morning and softer
/// at night, while always remaining readable against black text.
///
/// This is intentionally a *very* low-intensity shift — only a few percent
/// of hue/luminance — so the white-canvas/black-text aesthetic is preserved.
enum SelahReadingTone {
    case morning
    case daylight
    case evening
    case night

    static func current(date: Date = Date(), calendar: Calendar = .current) -> SelahReadingTone {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<9:   return .morning
        case 9..<17:  return .daylight
        case 17..<21: return .evening
        default:      return .night
        }
    }

    /// Reading-canvas background tone. Designed to layer on top of the
    /// system background — keeps black text fully readable.
    var canvasColor: Color {
        switch self {
        case .morning:  return Color(red: 0.985, green: 0.975, blue: 0.955)
        case .daylight: return Color(red: 0.970, green: 0.970, blue: 0.970)
        case .evening:  return Color(red: 0.975, green: 0.965, blue: 0.955)
        case .night:    return Color(red: 0.955, green: 0.955, blue: 0.960)
        }
    }

    var caption: String {
        switch self {
        case .morning:  return "Morning calm"
        case .daylight: return "Daylight"
        case .evening:  return "Evening light"
        case .night:    return "Quiet night"
        }
    }
}

// MARK: - Smart Highlight Palette

/// Theme-aware highlight tones. Low saturation, accessibility-safe against
/// both black text and the white reading canvas.
enum SelahHighlightTone {
    case wisdom
    case peace
    case prayer
    case hope
    case faith
    case neutral

    /// Pick a tone for a theme tag name (case-insensitive).
    static func tone(for theme: String?) -> SelahHighlightTone {
        guard let raw = theme?.lowercased() else { return .neutral }
        if raw.contains("wisdom") || raw.contains("knowledge") { return .wisdom }
        if raw.contains("peace") || raw.contains("rest")       { return .peace }
        if raw.contains("pray")                                 { return .prayer }
        if raw.contains("hope") || raw.contains("encourag")    { return .hope }
        if raw.contains("faith") || raw.contains("trust")      { return .faith }
        return .neutral
    }

    var fill: Color {
        switch self {
        case .wisdom:  return Color(red: 0.97, green: 0.90, blue: 0.72).opacity(0.55) // soft amber
        case .peace:   return Color(red: 0.86, green: 0.92, blue: 0.95).opacity(0.55) // pale blue-gray
        case .prayer:  return Color(red: 0.96, green: 0.89, blue: 0.74).opacity(0.55) // muted gold
        case .hope:    return Color(red: 0.90, green: 0.95, blue: 0.88).opacity(0.55) // sage green
        case .faith:   return Color(red: 0.92, green: 0.89, blue: 0.96).opacity(0.55) // soft lavender
        case .neutral: return Color.yellow.opacity(0.18)
        }
    }
}

// MARK: - Selah Topic Chip

/// A calm capsule chip used for filtering, personalization, or onboarding.
/// Soft outline when unselected, subtle Amen accent fill when selected.
struct SelahTopicChip: View {
    let label: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    init(label: String, icon: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Ambient Reading Chrome

/// Fades secondary chrome to a calmer opacity after a period of inactivity,
/// then restores immediately on touch / scroll. Intended for read-mode
/// surfaces — never for primary content.
///
/// Respects `accessibilityReduceMotion`: when reduce motion is on, opacity
/// stays steady at the active level.
struct AmbientReadingChromeModifier: ViewModifier {
    /// Whether the host view is currently in a "read" surface.
    let isActive: Bool
    /// Idle period (seconds) before chrome dims.
    var idleSeconds: TimeInterval = 6
    /// Dim opacity (active state is always 1.0).
    var dimmedOpacity: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed: Bool = false
    @State private var idleTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(effectiveOpacity)
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.45), value: isDimmed)
            .onAppear { resetTimer() }
            .onChange(of: isActive) { _, active in
                if active { resetTimer() } else { cancelTimer() }
            }
            .onDisappear { cancelTimer() }
    }

    private var effectiveOpacity: Double {
        guard isActive else { return 1.0 }
        if reduceMotion { return 1.0 }
        return isDimmed ? dimmedOpacity : 1.0
    }

    private func resetTimer() {
        cancelTimer()
        isDimmed = false
        guard isActive else { return }
        idleTask = Task { [idleSeconds] in
            try? await Task.sleep(nanoseconds: UInt64(idleSeconds * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run { isDimmed = true }
            }
        }
    }

    private func cancelTimer() {
        idleTask?.cancel()
        idleTask = nil
    }
}

extension View {
    /// Apply calm ambient dimming to non-essential reading chrome.
    func selahAmbientChrome(active: Bool, idleSeconds: TimeInterval = 6) -> some View {
        modifier(AmbientReadingChromeModifier(isActive: active, idleSeconds: idleSeconds))
    }
}

// MARK: - Selah Moments Inline Card

/// A calm, honest surfacing of the user's *real* recent reading activity.
/// Shows up to three of the user's recurring scripture references or themes,
/// derived directly from SelahService sessions — never AI-fabricated.
///
/// If there is not enough activity, the card stays hidden entirely rather
/// than fabricating an "insight."
struct SelahMomentsInlineCard: View {
    @ObservedObject private var service = SelahService.shared
    var onTapReference: ((String) -> Void)? = nil

    var body: some View {
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                    Text("SELAH MOMENTS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }

                Text(headline)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !momentChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(momentChips, id: \.self) { ref in
                                SelahTopicChip(
                                    label: ref,
                                    icon: "book.fill",
                                    isSelected: false
                                ) {
                                    onTapReference?(ref)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// Returns up to three references that appear multiple times in recent
    /// sessions, sorted by frequency. Honest surfacing only.
    private var moments: [(reference: String, count: Int)] {
        let allRefs = service.sessions.flatMap { $0.scriptureRefs }
        var counts: [String: Int] = [:]
        for ref in allRefs {
            counts[ref, default: 0] += 1
        }
        return counts
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(3)
            .map { (reference: $0.key, count: $0.value) }
    }

    private var momentChips: [String] {
        moments.map { $0.reference }
    }

    private var headline: String {
        guard let top = moments.first else { return "" }
        if moments.count == 1 {
            return "You've returned to \(top.reference) \(top.count) times recently."
        }
        return "Scripture you've been returning to recently."
    }
}

// MARK: - Verse Context Peek

/// A lightweight floating preview shown when the host taps a verse reference.
/// Calm capsule glass, dismissible, no hard navigation interruption.
///
/// The host wires it up by presenting `.sheet` or `.popover` with this
/// view. It calls back when the user chooses to open the verse fully.
struct SelahVerseContextPeek: View {
    let reference: String
    let snippet: String?
    let translation: String?
    var onOpenInSelah: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(reference)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            if let snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(3)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap below to open this passage in Selah.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    onDismiss?()
                } label: {
                    Text("Close")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    onOpenInSelah?()
                } label: {
                    HStack(spacing: 5) {
                        Text("Open in Selah")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, y: 6)
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verse preview for \(reference)")
    }
}

// MARK: - Floating Verse Action Toolbar (Liquid Glass)

/// A translucent floating action bar shown when the host detects a verse
/// selection. Keeps actions calm and limited: Copy, Highlight, Save,
/// Reflect, Pray, Share. Host controls visibility + callbacks.
struct SelahFloatingVerseActionToolbar: View {
    var onCopy: (() -> Void)? = nil
    var onHighlight: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    var onReflect: (() -> Void)? = nil
    var onPray: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            actionButton(icon: "doc.on.doc",         label: "Copy",      handler: onCopy)
            divider
            actionButton(icon: "highlighter",        label: "Highlight", handler: onHighlight)
            divider
            actionButton(icon: "bookmark",           label: "Save",      handler: onSave)
            divider
            actionButton(icon: "text.bubble",        label: "Reflect",   handler: onReflect)
            divider
            actionButton(icon: "hands.sparkles",     label: "Pray",      handler: onPray)
            divider
            actionButton(icon: "square.and.arrow.up", label: "Share",    handler: onShare)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.70), Color.white.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 14, y: 5)
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.5, height: 18)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, handler: (() -> Void)?) -> some View {
        Button {
            handler?()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(handler == nil)
        .opacity(handler == nil ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}

// MARK: - Calm Continuity Banner

/// A subtle "Continue in <reference>" banner inspired by Apple Books
/// continuity. Designed to live above the reading content when prior
/// Selah session activity exists. Honest copy only — no fabricated state.
struct SelahContinueReadingBanner: View {
    let title: String
    let subtitle: String?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "book.pages")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue reading \(title)")
    }
}
