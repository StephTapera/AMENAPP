//
//  BereanSuggestionChipsView.swift
//  AMENAPP
//
//  Smart contextual suggestion chips for Berean
//

import SwiftUI

struct BereanSuggestionChipsView: View {
    let chips: [BereanLiquidSuggestionChip]
    let onTap: (BereanLiquidSuggestionChip) -> Void
    let isVisible: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.95, anchor: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
    }
    
    private func chipButton(_ chip: BereanLiquidSuggestionChip) -> some View {
        Button {
            onTap(chip)
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 6) {
                if let icon = chip.icon {
                    Image(systemName: icon)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                
                Text(chip.text)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(.primary)
            }
            .suggestionChip()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Default Suggestions

extension BereanLiquidSuggestionChip {
    static let defaultSuggestions: [BereanLiquidSuggestionChip] = [
        BereanLiquidSuggestionChip(text: "Search scripture", icon: "magnifyingglass"),
        BereanLiquidSuggestionChip(text: "Explain simply", icon: "text.bubble"),
        BereanLiquidSuggestionChip(text: "Build a plan", icon: "list.bullet.clipboard"),
        BereanLiquidSuggestionChip(text: "Find verses", icon: "book.closed"),
        BereanLiquidSuggestionChip(text: "Daily devotional", icon: "sun.horizon")
    ]
}

#Preview {
    VStack {
        Spacer()
        
        BereanSuggestionChipsView(
            chips: BereanLiquidSuggestionChip.defaultSuggestions,
            onTap: { print("Tapped: \($0.text)") },
            isVisible: true
        )
        .background(Color(.systemBackground))
    }
}
