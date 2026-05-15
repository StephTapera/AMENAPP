// AmenMediaActionOverlay.swift
// AMENAPP
//
// Phase 11: Floating action controls over media messages.
// Uses AmenFloatingActionTray (Clear Liquid Glass) — overlay ONLY on media, never on bubbles.

import SwiftUI

struct AmenMediaActionOverlay: View {
    let message: AppMessage
    let flags: AMENFeatureFlags
    let onSave: () -> Void
    let onShare: () -> Void
    let onSaveToSelah: (() -> Void)?
    let onAddToNotes: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        AmenFloatingActionTray {
            Button(action: onSave) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Save to photo library")

            separatorLine

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Share")

            if flags.selahMediaOSEnabled, let onSaveToSelah {
                separatorLine
                Button(action: onSaveToSelah) {
                    Image(systemName: "bookmark")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }
                .accessibilityLabel("Save to Selah")
            }

            if let onAddToNotes {
                separatorLine
                Button(action: onAddToNotes) {
                    Image(systemName: "note.text")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Add to Church Notes")
            }

            separatorLine

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.20))
            .frame(width: 0.5, height: 20)
    }
}
