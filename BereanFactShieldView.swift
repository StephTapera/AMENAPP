// BereanFactShieldView.swift
// AMENAPP
//
// Collapsible fact-confidence indicators shown below each AI message bubble (PROMPT 5).

import SwiftUI

enum FactBadge: String {
    case verified   = "Verified"
    case likely     = "Likely"
    case checkSource = "Check Source"
}

struct FactClaim: Identifiable {
    let id: UUID
    let text: String
    let confidence: Double  // 0.0 – 1.0
    let badge: FactBadge
}

struct BereanFactShieldView: View {
    let claims: [FactClaim]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row — tap to expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    expanded.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(averageColor)
                    Text("Fact Shield")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("· \(claims.count) claim\(claims.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)

            // Expanded claim list
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(claims) { claim in
                        HStack(alignment: .top, spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(confidenceColor(claim.confidence))
                                .frame(width: 3)
                                .frame(minHeight: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(claim.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(.label))
                                    .lineLimit(2)
                                HStack(spacing: 4) {
                                    Text(claim.badge.rawValue)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(confidenceColor(claim.confidence), in: Capsule())
                                    Text("\(Int(claim.confidence * 100))% confidence")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                }
                            }
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .padding(.top, 6)
    }

    private var averageColor: Color {
        let avg = claims.map(\.confidence).reduce(0, +) / Double(max(claims.count, 1))
        return confidenceColor(avg)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.75 { return Color(red: 0.2, green: 0.7, blue: 0.4) }
        if confidence >= 0.5  { return Color(red: 0.9, green: 0.65, blue: 0.2) }
        return Color(red: 0.9, green: 0.3, blue: 0.3)
    }
}
