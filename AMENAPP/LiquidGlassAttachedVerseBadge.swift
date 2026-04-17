//
//  LiquidGlassAttachedVerseBadge.swift
//  AMENAPP
//
//  Elegant Liquid Glass attached verse preview badge for composer
//

import SwiftUI

struct LiquidGlassAttachedVerseBadge: View {
    let reference: String
    let text: String
    let onRemove: () -> Void
    let onEdit: () -> Void
    
    @State private var appear = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon indicator
            ZStack {
                Circle()
                    .fill(VerseGlassTokens.accentSubtle)
                    .frame(width: 36, height: 36)
                
                Image(systemName: "book.closed.fill")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(VerseGlassTokens.accentPrimary)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reference)
                        .font(.systemScaled(13, weight: .bold))
                        .foregroundStyle(VerseGlassTokens.accentPrimary)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(11))
                        .foregroundStyle(VerseGlassTokens.accentPrimary.opacity(0.7))
                }
                
                Text(text)
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Edit button
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(VerseGlassTokens.glassFill)
                        }
                }
                .buttonStyle(.plain)
                
                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(VerseGlassTokens.glassFill)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                .fill(VerseGlassTokens.accentSubtle)
                .overlay {
                    RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                        .strokeBorder(VerseGlassTokens.accentPrimary.opacity(0.25), lineWidth: 1)
                }
        }
        .shadow(color: VerseGlassTokens.accentGlow, radius: 8, y: 3)
        .scaleEffect(appear ? 1.0 : 0.92)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                appear = true
            }
        }
    }
}
