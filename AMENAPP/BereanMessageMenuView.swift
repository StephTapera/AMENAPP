// BereanMessageMenuView.swift
// AMENAPP
//
// Long-press floating action menu for Berean AI message bubbles.

import SwiftUI

struct BereanMessageMenuView: View {
    let message: String
    let onDismiss: () -> Void
    let onPostToAMEN: (String) -> Void
    /// Called when user taps "Dig In" — triggers a follow-up ask in the parent chat
    var onDigIn: (() -> Void)? = nil
    /// Called when user taps "Pray" — saves to prayer
    var onSaveToPrayer: (() -> Void)? = nil
    /// Called when user taps "Save" — saves to Church Notes
    var onSaveToNotes: (() -> Void)? = nil

    private let actions: [(emoji: String, label: String, id: String)] = [
        ("📋", "Copy",   "copy"),
        ("📖", "Notes",  "notes"),
        ("📤", "Post",   "post"),
        ("🙏", "Pray",   "pray"),
        ("🔍", "Dig In", "digin"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions, id: \.id) { action in
                Button { handleAction(action.id) } label: {
                    VStack(spacing: 3) {
                        Text(action.emoji)
                            .font(.system(size: 18))
                        Text(action.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    .frame(minWidth: 46)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private func handleAction(_ id: String) {
        switch id {
        case "copy":
            UIPasteboard.general.string = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "notes":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSaveToNotes?()
        case "post":
            onPostToAMEN(message)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "pray":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSaveToPrayer?()
        case "digin":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDigIn?()
        default: break
        }
        onDismiss()
    }
}
