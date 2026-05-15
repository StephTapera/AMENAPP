// AmenCatchUpTray.swift
// AMENAPP
//
// Phase 9: Catch Me Up tray shown above the composer when unread count >= 15.
// Honest unavailable state — no DM summarizer backend exists yet.

import SwiftUI

enum AmenCatchUpState: Equatable {
    case idle
    case loading
    case unavailable
    case succeeded([String])    // summary bullet points
    case failed
}

struct AmenCatchUpTray: View {
    let state: AmenCatchUpState
    let unreadCount: Int
    let onRequest: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch state {
            case .idle:
                idlePrompt
            case .loading:
                loadingView
            case .unavailable:
                unavailableView
            case .succeeded(let bullets):
                summaryView(bullets: bullets)
            case .failed:
                failedView
            }
        }
        .background(trayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var idlePrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.doc")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(unreadCount) unread messages")
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button("Catch Me Up", action: onRequest)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.blue)
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Catch up on \(unreadCount) unread messages")
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Catching up…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var unavailableView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Message summarization isn't available yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityLabel("Message summarization is not available yet. Double-tap to dismiss.")
    }

    private func summaryView(bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Summary")
                    .font(.callout.weight(.semibold))
                Spacer()
                dismissButton
            }
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(bullet)
                        .font(.callout)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var failedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Couldn't load summary. Try again later.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Dismiss")
    }

    private var trayBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
            )
    }
}
