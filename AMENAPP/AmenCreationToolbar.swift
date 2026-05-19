// AmenCreationToolbar.swift
// AMENAPP
// Toolbar for Universal Create composer.

import SwiftUI

struct AmenCreationToolbar: View {
    let onAddMedia: () -> Void
    let onOpenCamera: () -> Void
    let onPreview: () -> Void
    let onSwitchMode: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSwitchMode) {
                Label("Mode", systemImage: "slider.horizontal.3")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .accessibilityLabel("Switch creation mode")

            Button(action: onAddMedia) {
                Label("Media", systemImage: "photo.on.rectangle")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .accessibilityLabel("Add media")

            Button(action: onOpenCamera) {
                Label("Camera", systemImage: "camera")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .accessibilityLabel("Open camera")

            Spacer()

            Button(action: onPreview) {
                Label("Preview", systemImage: "eye")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .accessibilityLabel("Preview post")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
    }
}
