//
//  DiscernmentActionButton.swift
//  AMENAPP
//
//  Reusable glass-capsule pill that triggers a Berean discernment check.
//
//  Drop this into any view surface (comment, post, space_message, verse,
//  selah_note) and pass the text and source metadata. The button opens
//  DiscernmentEntrySheet as a sheet, which handles the full check lifecycle.
//
//  Design tokens:
//    Pill: .regularMaterial background + Capsule shape + black label
//    Error label: auto-clears after 3 seconds
//    Tap target: minimum 44 pt (WCAG AA)
//

import SwiftUI

// MARK: - DiscernmentActionButton

struct DiscernmentActionButton: View {

    // MARK: Input

    let inputText: String
    /// "comment" | "post" | "space_message" | "verse" | "selah_note"
    let sourceType: String
    let sourceRef: String?
    /// Called with the final DiscernmentCheckResult after a successful check.
    var onComplete: ((DiscernmentCheckResult) -> Void)? = nil

    // MARK: State

    @State private var showSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.circle")
                        .font(.subheadline)
                        .foregroundColor(Color(.label))

                    Text("Check against Scripture")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color(.label))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Check this text against Scripture using the Berean method")
            .sheet(isPresented: $showSheet) {
                DiscernmentEntrySheet(
                    inputText: inputText,
                    sourceType: sourceType,
                    sourceRef: sourceRef,
                    onComplete: { result in
                        showSheet = false
                        onComplete?(result)
                    }
                )
            }

            // Error state — shown briefly, auto-clears after 3 seconds
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(Color(.systemRed).opacity(0.85))
                    .padding(.leading, 4)
                    .transition(.opacity)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation { self.errorMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }
}
