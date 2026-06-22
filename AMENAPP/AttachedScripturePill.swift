//
//  AttachedScripturePill.swift
//  AMENAPP
//
//  Compact liquid glass scripture pill shown in the composer
//  and on published post cards after a verse is attached.
//  Tap to open scripture detail, long-press for context menu.
//

import SwiftUI

struct AttachedScripturePill: View {
    let attachment: ScriptureAttachment
    let onTap: () -> Void
    let onReplace: () -> Void
    let onRemove: () -> Void
    let onViewChapter: () -> Void
    let onCopyReference: () -> Void
    
    /// Lighter variant for post cards (no edit controls visible)
    var isPostCard: Bool = false
    
    @State private var appear = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Scripture icon
                Image(systemName: "text.book.closed.fill")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.5))
                
                // Reference
                Text(attachment.displayReference)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                
                // Translation badge
                Text(attachment.translation)
                    .font(.systemScaled(9, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                
                if !isPostCard {
                    // Remove button (composer only)
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove attached scripture")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(Color(.systemBackground))
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Open Scripture", systemImage: "book.fill")
            }
            
            Button {
                onViewChapter()
            } label: {
                Label("View Full Chapter", systemImage: "text.book.closed")
            }
            
            Divider()
            
            Button {
                onReplace()
            } label: {
                Label("Replace Scripture", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Button {
                onCopyReference()
            } label: {
                Label("Copy Reference", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityLabel("Attached scripture, \(attachment.displayReference), double tap to open full scripture")
        .accessibilityHint("Long press for more options")
        .scaleEffect(appear ? 1.0 : 0.92)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                appear = true
            }
        }
    }
}

// MARK: - Post Card Variant

/// Lightweight scripture pill for published post cards (no remove button)
struct PostCardScripturePill: View {
    let reference: String
    let translation: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "text.book.closed.fill")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                
                Text(reference)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                
                Text(translation)
                    .font(.systemScaled(8, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                    )
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(8, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Color(.systemBackground))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
            }
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scripture, \(reference), double tap to open")
    }
}
