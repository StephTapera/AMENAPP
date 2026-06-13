// BereanTraditionAwareView.swift
// AMEN App — SwiftUI view for BalancedAnswer display
//
// No "correct" tradition is highlighted — purely informational.
// Flag gate: AMENFeatureFlags.shared.bereanTraditionAware

import SwiftUI

// MARK: - BereanTraditionAwareView

struct BereanTraditionAwareView: View {

    let answer: BalancedAnswer

    @State private var expandedTraditions: Set<TraditionKey> = []

    var body: some View {
        guard AMENFeatureFlags.shared.bereanTraditionAware else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                commonGroundSection
                traditionsSection
                if !answer.sources.isEmpty {
                    sourcesSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Common Ground (shown first, prominent)

    private var commonGroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Common Ground", systemImage: "person.3.sequence.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(answer.commonGround)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
        }
    }

    // MARK: - Tradition Accordions

    private var traditionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Perspectives by Tradition")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 4)

            ForEach(answer.traditions, id: \.key) { tradition in
                TraditionAccordionRow(
                    tradition: tradition,
                    isExpanded: expandedTraditions.contains(tradition.key)
                ) {
                    if expandedTraditions.contains(tradition.key) {
                        expandedTraditions.remove(tradition.key)
                    } else {
                        expandedTraditions.insert(tradition.key)
                    }
                }
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(answer.sources, id: \.self) { source in
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - TraditionAccordionRow

private struct TraditionAccordionRow: View {

    let tradition: TraditionView
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack {
                    Text(tradition.key.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded && !tradition.perspective.isEmpty {
                Text(tradition.perspective)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tradition.key.displayName) perspective")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand to read")
    }
}

// MARK: - TraditionKey Display Names

extension TraditionKey {
    var displayName: String {
        switch self {
        case .reformed:    return "Reformed"
        case .catholic:    return "Catholic"
        case .orthodox:    return "Orthodox"
        case .wesleyan:    return "Wesleyan"
        case .pentecostal: return "Pentecostal"
        case .anabaptist:  return "Anabaptist"
        }
    }
}
