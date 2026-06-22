// MediaCompletionOverlay.swift
// AMENAPP
//
// Shown when a video reaches completion (95%+ watched or explicit end signal).
// Offers Replay / Next / Reflect / Done in a 2×2 grid with a Selah bridge option.
// Gated by `mediaCompletionOverlayEnabled`.

import SwiftUI

struct MediaCompletionOverlay: View {

    let postId: String
    let postTitle: String
    let creatorName: String
    let onReplay: () -> Void
    let onNext: () -> Void
    let onReflect: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        if !flags.mediaCompletionOverlayEnabled {
            EmptyView()
        } else {
            overlayContent
        }
    }

    // MARK: - Overlay Layout

    private var overlayContent: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            // Glass card
            VStack(spacing: 20) {

                // Completion badge
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Finished")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())

                // Post metadata
                VStack(spacing: 4) {
                    Text(postTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(creatorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // 2×2 action grid
                actionGrid

                // Selah bridge — only shown when flag is on
                if flags.mediaSelahAudioModeEnabled {
                    Button {
                        dlog("[MediaCompletionOverlay] Save to Selah tapped — postId: \(postId)")
                        NotificationCenter.default.post(
                            name: .saveToSelah,
                            object: nil,
                            userInfo: ["postId": postId]
                        )
                    } label: {
                        Text("Save to Selah")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                }
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 8)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Action Grid

    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            actionCell(
                label: "Replay",
                icon: "arrow.clockwise",
                action: onReplay
            )
            actionCell(
                label: "Next",
                icon: "forward.fill",
                action: onNext
            )
            actionCell(
                label: "Reflect",
                icon: "text.quote",
                action: onReflect
            )
            actionCell(
                label: "Done",
                icon: "xmark",
                action: onDismiss
            )
        }
    }

    private func actionCell(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let saveToSelah = Notification.Name("com.amenapp.saveToSelah")
}
