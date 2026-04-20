//
//  ScriptureGraphExplorerView.swift
//  AMENAPP
//
//  Living Scripture Graph explorer — visual neighborhood of cross-references,
//  thematic connections, and related passages surrounding a central passage.
//
//  The graph is not drawn as a literal node-edge diagram (that's CPU-expensive
//  and hard to read on mobile). Instead we use a hub-and-spoke card layout:
//    - Central passage at the top
//    - Cross-reference "spoke" cards below, sorted by strength DESC
//    - Theme cluster chips
//    - One-tap to drill into any spoke passage via ScriptureInsightView
//
//  Gated behind `livingScriptureGraphEnabled`.
//
//  Non-negotiables:
//    - Never show a cross-reference with confidence < 0.4
//    - Relationship type labels are always shown (no silent connections)
//    - Tapping a cross-reference opens a new ScriptureInsightView, not a raw URL
//

import SwiftUI

// MARK: - Scripture Graph Explorer View

struct ScriptureGraphExplorerView: View {
    let graphPayload: ScriptureGraphPayload

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTheme: ScriptureTheme? = nil
    @State private var drillPassageRef: String? = nil
    @State private var showInsight = false

    private var filteredCrossRefs: [ScriptureCrossRef] {
        graphPayload.centralPassage.crossReferences
            .filter { $0.strength >= 0.4 }
            .sorted { $0.strength > $1.strength }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Central node
                    centralPassageCard

                    // Theme cluster
                    if !graphPayload.themeCluster.isEmpty {
                        themeSection
                    }

                    // Cross-reference spokes
                    if !filteredCrossRefs.isEmpty {
                        crossRefSection
                    } else {
                        emptyCrossRefsNote
                    }

                    // Graph stats footer
                    graphFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Scripture Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    graphEdgeCountBadge
                }
            }
        }
        .sheet(isPresented: $showInsight) {
            if let ref = drillPassageRef {
                ScriptureInsightView(reference: ref)
            }
        }
    }

    // MARK: - Central Passage Card

    private var centralPassageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)

                Text("Central Passage")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            Text(graphPayload.centralPassage.reference.displayString)
                .font(AMENFont.bold(19))
                .foregroundStyle(.primary)

            Text(graphPayload.centralPassage.summary)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            // Christ connection teaser
            if let christConn = graphPayload.centralPassage.christConnection,
               christConn.confidence >= 0.6 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cross")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.52, green: 0.26, blue: 0.73))
                    Text(christConn.connectionStatement)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color(red: 0.52, green: 0.26, blue: 0.73))
                        .lineSpacing(2)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Themes")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(graphPayload.themeCluster) { theme in
                        ThemeChip(
                            theme: theme,
                            isSelected: selectedTheme?.id == theme.id
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedTheme = selectedTheme?.id == theme.id ? nil : theme
                            }
                        }
                    }
                }
            }

            if let theme = selectedTheme {
                ThemeDetailCard(theme: theme)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Cross Reference Section

    private var crossRefSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connected Passages")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(filteredCrossRefs.count) connections")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }

            Text("Tap any passage to study it in depth.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)

            ForEach(filteredCrossRefs) { crossRef in
                CrossRefCard(crossRef: crossRef) {
                    drillPassageRef = crossRef.targetReference.displayString
                    showInsight = true
                }
            }
        }
    }

    private var emptyCrossRefsNote: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Cross-references for this passage are being built.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var graphFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Scripture connections are based on recognized hermeneutical traditions and the Berean semantic graph.")
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.top, 8)
    }

    private var graphEdgeCountBadge: some View {
        Text("\(graphPayload.totalEdgeCount) edges")
            .font(AMENFont.regular(12))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Theme Chip

private struct ThemeChip: View {
    let theme: ScriptureTheme
    let isSelected: Bool
    let action: () -> Void

    private var chipColor: Color {
        switch theme.category {
        case .theological:    return .blue
        case .narrative:      return .orange
        case .prophetic:      return Color(red: 0.52, green: 0.26, blue: 0.73)
        case .wisdom:         return .green
        case .ethical:        return .teal
        case .eschatological: return .red
        }
    }

    var body: some View {
        Button(action: action) {
            Text(theme.name)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(isSelected ? .white : chipColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? chipColor : chipColor.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Detail Card

private struct ThemeDetailCard: View {
    let theme: ScriptureTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(theme.name)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            Text(theme.description)
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            if !theme.relatedPassages.isEmpty {
                Text("Appears in \(theme.relatedPassages.count) related passages")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

// MARK: - Cross Ref Card

private struct CrossRefCard: View {
    let crossRef: ScriptureCrossRef
    let onTap: () -> Void

    private var relationshipColor: Color {
        switch crossRef.relationshipType {
        case .fulfillment:  return Color(red: 0.52, green: 0.26, blue: 0.73)
        case .parallel:     return .blue
        case .contrast:     return .orange
        case .quotation:    return .green
        case .allusion:     return .teal
        case .commentary:   return .gray
        case .application:  return Color.green
        }
    }

    private var strengthLabel: String {
        switch crossRef.strength {
        case 0.8...1.0: return "Strong"
        case 0.6..<0.8: return "Good"
        default:        return "Moderate"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {

                // Connection type indicator
                VStack(spacing: 4) {
                    Circle()
                        .fill(relationshipColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Rectangle()
                        .fill(relationshipColor.opacity(0.2))
                        .frame(width: 2)
                }
                .frame(width: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(crossRef.targetReference.displayString)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)

                        Text(crossRef.relationshipType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(relationshipColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(relationshipColor.opacity(0.1))
                            )

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(crossRef.targetText)
                        .font(.custom("Georgia", size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(3)

                    Text("\(strengthLabel) connection")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}
