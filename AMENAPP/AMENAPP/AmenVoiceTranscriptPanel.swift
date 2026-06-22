// AmenVoiceTranscriptPanel.swift
// AMENAPP
//
// Phase 10: Voice message transcript panel.
// Honest unavailable state — STT for received messages not yet wired.

import SwiftUI

enum AmenVoiceTranscriptState: Equatable {
    case unavailable
    case loading
    case succeeded(String)
    case failed
}

struct AmenVoiceTranscriptPanel: View {
    /// Honest copy shown when STT for received messages is not yet wired.
    /// Exposed as `internal` so audit-fix tests can assert against it.
    static let unavailableMessage = "Voice transcription isn't available yet."

    let state: AmenVoiceTranscriptState
    let onClose: () -> Void
    let onCopy: ((String) -> Void)?
    let onTranslate: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Transcript")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close transcript")
            }

            switch state {
            case .unavailable:
                Text(AmenVoiceTranscriptPanel.unavailableMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .succeeded(let text):
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    if let onCopy {
                        Button {
                            onCopy(text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if let onTranslate {
                        Button {
                            onTranslate(text)
                        } label: {
                            Label("Translate", systemImage: "globe")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .foregroundStyle(.blue)

            case .failed:
                Text("Couldn't load transcript. Try again later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}
