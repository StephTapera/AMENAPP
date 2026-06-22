// SmartCommentComposer.swift
// AMENAPP — Smart Comments Wave 1
//
// Sticky floating composer bar shown at the bottom of SmartCommentsSheet.
// Glass pill background on the bar; blue tint submit button when text is present.
//
// Reduce-transparency fallback: opaque systemBackground for the bar when
// UIAccessibility.isReduceTransparencyEnabled is true.

import SwiftUI
import Foundation
import UIKit

struct SmartCommentComposer: View {

    // MARK: - Input

    /// Called when the user taps Send. Receives the trimmed body text.
    let onSubmit: (String) async -> Void

    /// True while a submission is in flight. Shows a spinner in place of the send icon.
    var isPosting: Bool = false

    // MARK: - Local State

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    // MARK: - Constants

    private let softWarnThreshold = 1800
    private let hardLimit = 2000

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Character count warning — appears only when approaching the limit.
            if text.count >= softWarnThreshold {
                HStack {
                    Spacer()
                    Text("\(text.count) / \(hardLimit)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(text.count > hardLimit ? .red : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }
            }

            // Composer bar
            HStack(alignment: .bottom, spacing: 10) {
                // Text input
                TextField("Share a reflection...", text: $text, axis: .vertical)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(isPosting)

                Spacer(minLength: 0)

                // Send button / spinner
                if isPosting {
                    ProgressView()
                        .tint(.blue)
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        submitIfValid()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSend ? .white : Color.white.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(canSend ? Color.blue : Color.blue.opacity(0.3))
                            )
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send comment")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(composerBarBackground)
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.top, 8)
        .background(Color(uiColor: .systemBackground).opacity(0.01)) // allow hit-testing through
    }

    // MARK: - Background

    @ViewBuilder
    private var composerBarBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Capsule()
                .fill(Color(uiColor: .systemGray6))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= hardLimit && !isPosting
    }

    private func submitIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= hardLimit, !isPosting else { return }

        // Clear text optimistically before the async call completes.
        // The pending state is reflected in SmartCommentsSheet via pendingLocalComment.
        let body = trimmed
        text = ""
        isFocused = false

        Task {
            await onSubmit(body)
        }
    }
}
