//
//  InlineScriptureSuggestionBar.swift
//  AMENAPP
//
//  Compact suggestion bar that appears near the composer when
//  scripture intent is detected in the user's draft text.
//  Non-intrusive, dismissible, liquid glass styled.
//

import SwiftUI

struct InlineScriptureSuggestionBar: View {
    let verse: BereanScriptureChip
    let label: String
    let onAttach: () -> Void
    let onDismiss: () -> Void
    let onSeeRelated: () -> Void
    
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: "lightbulb.fill")
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(Color.orange.opacity(0.8))
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                
                Text(verse.reference)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            
            Spacer()
            
            // Attach action
            Button(action: onAttach) {
                Text("Attach")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach \(verse.reference)")
            
            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
        .scaleEffect(appear ? 1.0 : 0.95)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                appear = true
            }
        }
    }
}
