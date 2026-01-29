//
//  SharedUIComponents.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//

import SwiftUI

// MARK: - Button Styles

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Filter Chips

/// Generic filter chip with title and optional count - Black & White Liquid Glass Design
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int?
    let action: () -> Void
    
    init(title: String, isSelected: Bool, count: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.count = count
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
                
                if let count = count {
                    Text("\(count)")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(isSelected ? .white : .black.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : Color.black.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black : Color.white)
                    .shadow(color: isSelected ? .black.opacity(0.3) : .black.opacity(0.08), radius: isSelected ? 12 : 8, y: isSelected ? 4 : 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(isSelected ? 0 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
// MARK: - Quick Reply Chip

/// Quick reply chip for messaging - Black & White Liquid Glass Design
struct QuickReplyChip: View {
    let text: String
    var color: Color = .black
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(color)
                        .shadow(color: color.opacity(0.3), radius: 8, y: 2)
                )
        }
    }
}

