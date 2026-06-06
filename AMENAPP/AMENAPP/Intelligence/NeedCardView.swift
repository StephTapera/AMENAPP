// NeedCardView.swift
// AMENAPP — Living Intelligence — Need Card
// Displays a detected community need IntelligenceCard.
// Rules:
//   - TruthLevel "COMMUNITY_CONFIRMED" shown as "Shared by community"
//   - Urgency indicator: urgent/standard (no counts)
//   - Actions rendered from card.actions: GIVE, SHOW_UP, PRAY minimum
//   - No spectacle counters of any kind
//   - Liquid Glass material

import SwiftUI

// MARK: - Models

enum NeedType: String, Hashable {
    case material = "MATERIAL"
    case prayer = "PRAYER"
    case volunteer = "VOLUNTEER"
    case donation = "DONATION"
    case community = "COMMUNITY"
    case information = "INFORMATION"
    case none = "NONE"
}

enum NeedUrgency: String, Hashable {
    case low
    case medium
    case high
}

struct NeedCardAction: Identifiable, Hashable {
    let id: String
    let rung: String      // ActionRung raw value
    let label: String
    let handler: String   // action.giveToNeed, action.volunteer, etc.
    let target: String    // needId
}

struct NeedCard: Identifiable {
    let id: String
    let title: String
    let summary: [String]
    let needType: NeedType
    let urgency: NeedUrgency
    let churchContext: String?   // church name if available
    let actions: [NeedCardAction]
    let rankReasons: [String]
    let truthLevelLabel: String  // "Shared by community", "Church confirmed", etc.
    let needId: String           // backingEntity.id

    let createdAt: Date
    let expiresAt: Date
}

// MARK: - Action Handler Protocol

protocol NeedCardDelegate: AnyObject {
    func handleNeedAction(handler: String, target: String)
}

// MARK: - Main View

struct NeedCardView: View {
    let card: NeedCard
    weak var delegate: (any NeedCardDelegate)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAllActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Urgency banner
            if card.urgency == .high {
                urgencyBanner
            }

            // Header
            cardHeader

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 16)

            // Summary bullets
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.summary.prefix(3), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: needTypeIcon)
                            .font(.caption)
                            .foregroundStyle(needTypeColor)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Truth level + church context
            contextRow
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 16)

            // Action buttons
            actionRow
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(urgencyBorderColor, lineWidth: card.urgency == .high ? 1.5 : 0)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Urgency Banner

    private var urgencyBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text("Urgent Need")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .tracking(0.3)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .fill(Color(hex: "#C0392B"))
        )
        .accessibilityLabel("Urgent need alert")
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Need type label
                HStack(spacing: 4) {
                    Image(systemName: needTypeIcon)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text(needTypeDisplayName)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                }
                .foregroundStyle(needTypeColor)
                .accessibilityLabel("Need type: \(needTypeDisplayName)")

                Text(card.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()

            // Urgency indicator — icon only, no count
            urgencyIndicatorIcon
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Context Row (truth level + church)

    private var contextRow: some View {
        HStack(spacing: 8) {
            // Truth level badge
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(card.truthLevelLabel)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if let church = card.churchContext, !church.isEmpty {
                Text("•")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(church)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([card.truthLevelLabel, card.churchContext].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: - Action Row

    private var actionRow: some View {
        // Show all actions from the card; fall back to a default if none provided
        let displayActions = card.actions.isEmpty
            ? defaultFallbackActions
            : card.actions

        return NeedCardFlowLayout(spacing: 8) {
            ForEach(displayActions.prefix(4)) { action in
                Button {
                    delegate?.handleNeedAction(handler: action.handler, target: action.target)
                } label: {
                    Label(action.label, systemImage: iconForRung(action.rung))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isPrimaryAction(action.rung) ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isPrimaryAction(action.rung) ? AnyShapeStyle(needTypeColor) : AnyShapeStyle(.ultraThinMaterial))
                        )
                }
                .accessibilityLabel(action.label)
                .accessibilityHint(actionHint(action.rung))
            }
        }
    }

    // MARK: - Helpers

    private var defaultFallbackActions: [NeedCardAction] {
        [
            NeedCardAction(id: "fallback_need", rung: "NOTICE", label: "View Need",
                           handler: "action.openNeed", target: card.needId),
        ]
    }

    private var needTypeIcon: String {
        switch card.needType {
        case .material:    return "bag.fill"
        case .prayer:      return "hands.sparkles.fill"
        case .volunteer:   return "person.2.fill"
        case .donation:    return "heart.fill"
        case .community:   return "person.3.fill"
        case .information: return "info.circle.fill"
        case .none:        return "square.dashed"
        }
    }

    private var needTypeColor: Color {
        switch card.urgency {
        case .high:   return Color(hex: "#C0392B")
        case .medium: return Color(hex: "#E67E22")
        case .low:    return Color(hex: "#A78843")
        }
    }

    private var urgencyBorderColor: Color {
        card.urgency == .high ? Color(hex: "#C0392B").opacity(0.5) : .clear
    }

    private var needTypeDisplayName: String {
        switch card.needType {
        case .material:    return "Material Need"
        case .prayer:      return "Prayer Need"
        case .volunteer:   return "Volunteer"
        case .donation:    return "Donation"
        case .community:   return "Community"
        case .information: return "Information"
        case .none:        return "Need"
        }
    }

    @ViewBuilder
    private var urgencyIndicatorIcon: some View {
        switch card.urgency {
        case .high:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#C0392B"))
                .accessibilityLabel("Urgent")
        case .medium:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color(hex: "#E67E22"))
                .accessibilityLabel("Standard urgency")
        case .low:
            EmptyView()
        }
    }

    private func isPrimaryAction(_ rung: String) -> Bool {
        ["GIVE", "SHOW_UP", "PRAY"].contains(rung)
    }

    private func iconForRung(_ rung: String) -> String {
        switch rung {
        case "GIVE":    return "heart.fill"
        case "SHOW_UP": return "person.badge.plus"
        case "PRAY":    return "hands.sparkles"
        case "DISCUSS": return "bubble.left.and.bubble.right"
        case "LEARN":   return "book.fill"
        case "NOTICE":  return "eye"
        default:        return "arrow.forward.circle"
        }
    }

    private func actionHint(_ rung: String) -> String {
        switch rung {
        case "GIVE":    return "Opens giving options for this need"
        case "SHOW_UP": return "Signs you up as a volunteer"
        case "PRAY":    return "Adds your prayer to this need"
        case "DISCUSS": return "Opens discussion thread"
        case "LEARN":   return "Opens more information"
        default:        return "Opens this need"
        }
    }
}

// MARK: - FlowLayout (wrapping chip row)

private struct NeedCardFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { row in
            row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
        }.reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
        let maxWidth = proposal.width ?? 320
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0

        for (i, subview) in subviews.enumerated() {
            let w = subview.sizeThatFits(.unspecified).width
            if rowWidth + w > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(i)
            rowWidth += w + spacing
        }
        return rows
    }
}

// MARK: - Preview

#if DEBUG
private final class PreviewDelegate: NeedCardDelegate {
    func handleNeedAction(handler: String, target: String) {}
}

#Preview("Urgent Material Need") {
    NeedCardView(
        card: NeedCard(
            id: "preview_need_1",
            title: "Urgent Need",
            summary: [
                "Material need shared",
                "Shared by community",
                "From your church",
            ],
            needType: .material,
            urgency: .high,
            churchContext: "Cornerstone Church",
            actions: [
                NeedCardAction(id: "1", rung: "GIVE", label: "Give Resources",
                               handler: "action.giveToNeed", target: "need_abc"),
                NeedCardAction(id: "2", rung: "SHOW_UP", label: "Help Out",
                               handler: "action.volunteer", target: "need_abc"),
                NeedCardAction(id: "3", rung: "PRAY", label: "Pray",
                               handler: "action.addToPrayer", target: "need_abc"),
            ],
            rankReasons: ["Community-submitted need", "Classified as MATERIAL", "Urgency: high"],
            truthLevelLabel: "Shared by community",
            needId: "need_abc",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 14)
        ),
        delegate: PreviewDelegate()
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Community Need") {
    NeedCardView(
        card: NeedCard(
            id: "preview_need_2",
            title: "Community Need",
            summary: ["Community need shared", "Shared by community"],
            needType: .community,
            urgency: .low,
            churchContext: nil,
            actions: [
                NeedCardAction(id: "1", rung: "DISCUSS", label: "Join the Conversation",
                               handler: "action.discuss", target: "need_xyz"),
                NeedCardAction(id: "2", rung: "SHOW_UP", label: "Show Up",
                               handler: "action.volunteer", target: "need_xyz"),
            ],
            rankReasons: ["Community-submitted need", "Classified as COMMUNITY"],
            truthLevelLabel: "Shared by community",
            needId: "need_xyz",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 14)
        ),
        delegate: PreviewDelegate()
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
