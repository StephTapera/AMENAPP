// BereanScriptureContextCardView.swift
// AMEN App — Berean Visual Scripture Intelligence (Agent 2)
//
// Reusable context card for a detected scripture reference.
// Clearly labels scripture vs. interpretation — never mixed.
// Shows passage, cross-references, context summary, and Berean note.

import SwiftUI

struct BereanScriptureContextCardView: View {
    let card: BereanScriptureContextCard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showCrossRefs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: Reference + Version + Label
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.reference.displayString)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)

                    if card.version != .unknown {
                        Text(card.version.rawValue)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Berean content label badge
                HStack(spacing: 4) {
                    Image(systemName: card.bereanLabel.systemIcon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(card.bereanLabel.rawValue)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                }
                .foregroundStyle(labelColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(labelColor.opacity(0.12), in: Capsule())
            }

            divider

            // Passage text
            if !card.passageText.isEmpty {
                Text(card.passageText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Context summary
            if !card.contextSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Background", systemImage: "info.circle")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    Text(card.contextSummary)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            // Cross-references (collapsible)
            if !card.crossReferences.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCrossRefs.toggle()
                    }
                } label: {
                    HStack {
                        Label("Cross-References (\(card.crossReferences.count))", systemImage: "link")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: showCrossRefs ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showCrossRefs {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(card.crossReferences, id: \.self) { ref in
                            Text(ref.displayString)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Berean note (labeled distinction)
            if !card.bereanNote.isEmpty {
                divider

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.56, green: 0.40, blue: 0.85))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Berean Note")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.secondary)
                        Text(card.bereanNote)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                      : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.4))
            .frame(height: 0.5)
    }

    private var labelColor: Color {
        switch card.bereanLabel {
        case .scripture:      return Color(red: 0.16, green: 0.40, blue: 0.76)
        case .interpretation: return Color(red: 0.70, green: 0.45, blue: 0.10)
        case .encouragement:  return Color(red: 0.56, green: 0.40, blue: 0.85)
        }
    }
}
