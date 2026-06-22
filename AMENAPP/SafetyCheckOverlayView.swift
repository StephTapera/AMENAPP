// SafetyCheckOverlayView.swift — AMEN App
// Pre-posting safety review sheet with three severity tiers.

import SwiftUI

struct SafetyCheckOverlayView: View {
    let safetyScore: Double
    let aiReasoning: String
    let flaggedCategories: [String]
    let onEdit: () -> Void
    let onPostAnyway: () -> Void
    let onCancel: () -> Void
    var contentId: String = ""

    @State private var showAppeal = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Severity Tier

    private enum Tier {
        case warning, review, blocked
    }

    private var tier: Tier {
        if safetyScore > 0.85 { return .blocked }
        if safetyScore > 0.6  { return .review }
        return .warning
    }

    private var tintColor: Color {
        switch tier {
        case .warning: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .review:  return Color(red: 0.96, green: 0.38, blue: 0.24)
        case .blocked: return Color(red: 0.96, green: 0.26, blue: 0.26)
        }
    }

    private var iconName: String {
        switch tier {
        case .warning: return "exclamationmark.triangle.fill"
        case .review:  return "clock.fill"
        case .blocked: return "xmark.shield.fill"
        }
    }

    private var titleText: String {
        switch tier {
        case .warning: return "Content May Be Sensitive"
        case .review:  return "Content Under Review"
        case .blocked: return "Can't Post This"
        }
    }

    private var subtitleText: String {
        switch tier {
        case .warning: return "Take a moment to review before posting."
        case .review:  return "This content has been flagged for human review."
        case .blocked: return "This content violates our faith community standards."
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header icon
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(tintColor.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Circle()
                                .strokeBorder(tintColor.opacity(0.25), lineWidth: 1.5)
                                .frame(width: 80, height: 80)
                            Image(systemName: iconName)
                                .font(.systemScaled(34, weight: .semibold))
                                .foregroundColor(tintColor)
                        }
                        .padding(.top, 32)

                        VStack(spacing: 6) {
                            Text(titleText)
                                .font(.systemScaled(20, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(subtitleText)
                                .font(.systemScaled(14))
                                .foregroundColor(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                    }

                    // AI Reasoning card (real text, not "community guidelines")
                    reasoningCard

                    // Flagged categories
                    if !flaggedCategories.isEmpty {
                        flaggedCategoriesSection
                    }

                    // Safety score pill
                    scoreIndicator

                    // Action buttons
                    actionButtons

                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 20)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAppeal) {
            AppealView(
                contentId: contentId,
                originalDecision: tier == .blocked ? "blocked" : "review",
                aiReasoning: aiReasoning,
                onSubmit: { showAppeal = false }
            )
        }
    }

    // MARK: - Reasoning Card

    private var reasoningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(11, weight: .bold))
                    .foregroundColor(tintColor)
                Text("AI Assessment")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundColor(tintColor)
            }

            Text(aiReasoning.isEmpty ? "Content was flagged by automated safety systems." : aiReasoning)
                .font(.systemScaled(15))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Flagged Categories

    private var flaggedCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flagged categories")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)

            FlowRow(spacing: 6) {
                ForEach(flaggedCategories, id: \.self) { category in
                    Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundColor(tintColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(tintColor.opacity(0.13))
                                .overlay(Capsule().strokeBorder(tintColor.opacity(0.25), lineWidth: 1))
                        )
                }
            }
        }
    }

    // MARK: - Score Indicator

    private var scoreIndicator: some View {
        HStack(spacing: 10) {
            Text("Safety score")
                .font(.systemScaled(12))
                .foregroundColor(.white.opacity(0.4))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                    Capsule()
                        .fill(tintColor)
                        .frame(width: geo.size.width * safetyScore, height: 6)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.0f%%", safetyScore * 100))
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(tintColor)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            switch tier {
            case .warning:
                // Primary: Edit Post
                primaryButton(label: "Edit Post", systemImage: "pencil") {
                    dismiss()
                    onEdit()
                }
                // Ghost: Post Anyway
                ghostButton(label: "Post Anyway") {
                    dismiss()
                    onPostAnyway()
                }
                ghostButton(label: "Cancel", textColor: .white.opacity(0.4)) {
                    dismiss()
                    onCancel()
                }

            case .review:
                primaryButton(label: "OK, I Understand", systemImage: "checkmark") {
                    dismiss()
                    onCancel()
                }
                ghostButton(label: "Appeal Decision") {
                    showAppeal = true
                }

            case .blocked:
                primaryButton(label: "Edit Post", systemImage: "pencil") {
                    dismiss()
                    onEdit()
                }
                ghostButton(label: "Appeal Decision") {
                    showAppeal = true
                }
                ghostButton(label: "Cancel", textColor: .white.opacity(0.4)) {
                    dismiss()
                    onCancel()
                }
            }
        }
    }

    // MARK: - Button Helpers

    private func primaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.systemScaled(14, weight: .semibold))
                Text(label)
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tintColor)
                    .shadow(color: tintColor.opacity(0.35), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }

    private func ghostButton(
        label: String,
        textColor: Color = Color.white.opacity(0.7),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.systemScaled(15, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FlowRow (horizontal wrapping HStack)

private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > containerWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: containerWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
