import SwiftUI

// MARK: - Post Lifecycle Badge
// Additive badge showing a post's lifecycle stage.
// Drop onto any card overlay — no structural changes needed.

enum PostLifecycleStage: String, CaseIterable {
    case new          = "New"
    case settling     = "Settling"
    case resurfaced   = "Resurfaced"
    case memory       = "Memory"
    case continuing   = "Continuing"
    case eventLinked  = "Event"

    var icon: String {
        switch self {
        case .new:          return "sparkle"
        case .settling:     return "leaf"
        case .resurfaced:   return "arrow.counterclockwise.circle"
        case .memory:       return "brain"
        case .continuing:   return "arrow.right.circle"
        case .eventLinked:  return "calendar.circle"
        }
    }

    var color: Color {
        switch self {
        case .new:          return .blue
        case .settling:     return .green
        case .resurfaced:   return .orange
        case .memory:       return .purple
        case .continuing:   return .teal
        case .eventLinked:  return .pink
        }
    }

    var tooltip: String {
        switch self {
        case .new:          return "Posted recently"
        case .settling:     return "Finding its audience"
        case .resurfaced:   return "Relevant again based on your history"
        case .memory:       return "You saved something from this"
        case .continuing:   return "Part of a thread you started"
        case .eventLinked:  return "Connected to an event"
        }
    }
}

struct PostLifecycleBadge: View {
    let stage: PostLifecycleStage
    var compact: Bool = true

    @State private var showTooltip = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                showTooltip.toggle()
            }
            HapticManager.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: stage.icon)
                    .font(.systemScaled(compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(stage.color)
                if !compact || showTooltip {
                    Text(showTooltip ? stage.tooltip : stage.rawValue)
                        .font(.systemScaled(compact ? 9 : 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(stage.color.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(stage.color.opacity(0.20), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.rawValue): \(stage.tooltip)")
        .onChange(of: showTooltip) { _, showing in
            if showing {
                // Auto-dismiss tooltip after 2.5s
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { showTooltip = false }
                }
            }
        }
    }
}

// MARK: - Lifecycle Engine (local heuristics, no network)

struct PostLifecycleEngine {
    /// Infers lifecycle stage from post metadata. Used client-side for Selah media items.
    static func inferStage(
        createdAt: Date,
        saveCount: Int,
        hasLinkedMemory: Bool,
        isPartOfThread: Bool,
        isEventLinked: Bool,
        wasResurfaced: Bool
    ) -> PostLifecycleStage {
        if isEventLinked { return .eventLinked }
        if isPartOfThread { return .continuing }
        if hasLinkedMemory { return .memory }
        if wasResurfaced { return .resurfaced }

        let ageHours = Date().timeIntervalSince(createdAt) / 3600
        if ageHours < 48 { return .new }
        if saveCount > 3 { return .memory }
        return .settling
    }

    static func inferStage(from item: SelahMediaItem, memories: [SelahMediaMemory]) -> PostLifecycleStage {
        let hasLinkedMemory = memories.contains {
            $0.linkedMediaIds.contains(item.id ?? "")
        }
        let ageHours = Date().timeIntervalSince(item.createdAt) / 3600
        return inferStage(
            createdAt: item.createdAt,
            saveCount: item.saveCount,
            hasLinkedMemory: hasLinkedMemory,
            isPartOfThread: false,
            isEventLinked: false,
            wasResurfaced: ageHours > 168 && item.saveCount > 2
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ForEach(PostLifecycleStage.allCases, id: \.rawValue) { stage in
            PostLifecycleBadge(stage: stage, compact: false)
        }
    }
    .padding()
}
