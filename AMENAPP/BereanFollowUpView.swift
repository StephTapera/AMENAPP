// BereanFollowUpView.swift
// AMENAPP
//
// Smart follow-up suggestion chips shown above the input bar after each AI response (PROMPT 4).

import SwiftUI

struct BereanFollowUp: Identifiable {
    let id: UUID
    let icon: String
    let text: String
    let prompt: String
}

struct BereanFollowUpView: View {
    let suggestions: [BereanFollowUp]
    let onSelect: (BereanFollowUp) -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                    Button { onSelect(item) } label: {
                        HStack(spacing: 5) {
                            Text(item.icon)
                                .font(.system(size: 12))
                            Text(item.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.2))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.78).delay(Double(index) * 0.06),
                        value: appeared
                    )
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
        .onAppear {
            withAnimation { appeared = true }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}
