import SwiftUI

// MARK: - Context Window Overlay
// A small Liquid Glass pill shown on media cards explaining why the item appears.
// Additive only — attach to any card view, no structural changes required.

struct SelahContextWindowOverlay: View {
    let reason: String
    let confidence: Double     // 0–1
    var showIcon: Bool = true

    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                expanded.toggle()
            }
            HapticManager.selection()
        } label: {
            HStack(spacing: 5) {
                if showIcon {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(9, weight: .semibold))
                        .foregroundStyle(pillColor)
                }
                Text(expanded ? reason : abbreviatedReason)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(expanded ? 2 : 1)
                    .fixedSize(horizontal: !expanded, vertical: false)
                if confidence < 0.6 && expanded {
                    Text("·")
                        .font(.systemScaled(10))
                        .foregroundStyle(.tertiary)
                    Text("suggested")
                        .font(.systemScaled(9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, expanded ? 10 : 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(pillColor.opacity(0.22), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Context: \(reason)")
    }

    private var abbreviatedReason: String {
        // Show first 3 words max in collapsed state
        let words = reason.split(separator: " ")
        if words.count <= 3 { return reason }
        return words.prefix(3).joined(separator: " ") + "…"
    }

    private var pillColor: Color {
        if confidence >= 0.8 { return .purple }
        if confidence >= 0.5 { return .blue }
        return .secondary
    }
}

// MARK: - Predefined Context Windows

extension SelahContextWindowOverlay {
    static func savedBySimilar() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Because you saved similar content", confidence: 0.85)
    }
    static func trustedSaves(_ count: Int) -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "\(count) trusted saves", confidence: 0.9)
    }
    static func partOfThread() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Part of a thread", confidence: 1.0)
    }
    static func resurfacedFromMemory() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Resurfaced from your memory", confidence: 0.75)
    }
    static func creatorIntent(_ intent: String) -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Creator intent: \(intent)", confidence: 0.7)
    }
    static func matchesTheme(_ theme: String) -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Matches your \(theme) theme", confidence: 0.8)
    }
    static func fromCloseCircle() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "From your close circle", confidence: 1.0)
    }
    static func goodForQuietMode() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Good for quiet mode", confidence: 0.65)
    }
    static func worthSaving() -> SelahContextWindowOverlay {
        SelahContextWindowOverlay(reason: "Worth saving", confidence: 0.72)
    }
}

// MARK: - Context Window from RankedMedia

extension SelahContextWindowOverlay {
    init(from ranked: SelahRankedMedia) {
        self.init(
            reason: ranked.matchReason,
            confidence: ranked.score
        )
    }
}

// MARK: - Multiple Windows Row

struct SelahContextWindowRow: View {
    let windows: [SelahContextWindowData]
    @State private var showAll = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(windows.prefix(showAll ? windows.count : 2)) { window in
                    SelahContextWindowOverlay(reason: window.text, confidence: window.confidence)
                }
                if windows.count > 2 && !showAll {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll = true }
                    } label: {
                        Text("+\(windows.count - 2) more")
                            .font(.systemScaled(10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SelahContextWindowData: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Double
    let reason: String
}
