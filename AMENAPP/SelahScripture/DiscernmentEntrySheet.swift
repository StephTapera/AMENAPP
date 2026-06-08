//
//  DiscernmentEntrySheet.swift
//  AMENAPP
//
//  Full-screen sheet that orchestrates a Berean discernment check:
//    1. Shows an input preview (citation-block inset)
//    2. Kicks off runCheck on appear → DiscernmentCheckView transitions
//       automatically through loading → result states
//    3. Presents a mandatory user-confirmation alert before sharing
//
//  HARD CONSTRAINTS:
//    - Sharing is ALWAYS opt-in: user must tap "Share to thread" and then
//      confirm the alert before shareCheck is called.
//    - Visibility is never set to "shared" without this explicit two-step.
//    - Privacy footer is always visible in non-refused grounded states
//      (enforced inside DiscernmentCheckView).
//

import SwiftUI

// MARK: - DiscernmentEntrySheet

struct DiscernmentEntrySheet: View {

    // MARK: Input

    let inputText: String
    /// "comment" | "post" | "space_message" | "verse" | "selah_note"
    let sourceType: String
    let sourceRef: String?
    /// Called after the sheet has finished (check completed or dismissed).
    var onComplete: ((DiscernmentCheckResult) -> Void)? = nil

    // MARK: State

    @StateObject private var service = DiscernmentService.shared
    @State private var showShareAlert = false
    @State private var isSharing = false
    @State private var shareErrorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 1. Drag handle
                    dragHandle

                    // 2. Input preview — citation-block inset, first 100 chars
                    inputPreview

                    // 3. DiscernmentCheckView — driven by service.currentCheck
                    //    nil → loading state is shown immediately on appear
                    DiscernmentCheckView(
                        check: service.currentCheck,
                        onShare: { showShareAlert = true },
                        onDismiss: { dismiss() },
                        isSharing: $isSharing
                    )

                    // Share error feedback (non-fatal)
                    if let shareError = shareErrorMessage {
                        Text(shareError)
                            .font(.caption)
                            .foregroundColor(Color(.systemRed).opacity(0.85))
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                            .onAppear {
                                Task {
                                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                                    withAnimation { shareErrorMessage = nil }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Berean Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss Berean Check sheet")
                }
            }
            // 4. Share confirmation alert — shown when user taps "Share to thread"
            .alert("Share Berean Check", isPresented: $showShareAlert) {
                Button("Share", role: .none) {
                    Task { await confirmShare() }
                }
                Button("Keep Private", role: .cancel) { }
            } message: {
                Text(
                    "This will show other participants what Scripture says about these claims. " +
                    "The check is formative — not a verdict about a person."
                )
            }
        }
        // 5. Run check immediately on appear — loading state shown while waiting
        .task {
            // Clear any previous check so the loading state is visible.
            service.currentCheck = nil
            do {
                let result = try await service.runCheck(
                    inputText: inputText,
                    sourceType: sourceType,
                    sourceRef: sourceRef
                )
                onComplete?(result)
            } catch {
                // Error is stored on the service and surfaced via service.error;
                // DiscernmentCheckView will fall back to the loading skeleton
                // until the user dismisses.
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shareErrorMessage)
    }

    // MARK: - Sub-views

    private var dragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
            Spacer()
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var inputPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Checking:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Color(.secondaryLabel))
                .textCase(.uppercase)

            let preview = inputText.count > 100
                ? String(inputText.prefix(100)) + "…"
                : inputText

            Text(preview)
                .font(.subheadline)
                .foregroundColor(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Text being checked: \(inputText.prefix(100))")
    }

    // MARK: - Share Confirmation

    /// Called after the user taps "Share" in the confirmation alert.
    /// This is the ONLY path that triggers shareCheck — never automatic.
    private func confirmShare() async {
        guard let checkId = service.currentCheck?.id else { return }

        isSharing = true
        defer { isSharing = false }

        do {
            let updated = try await service.shareCheck(checkId: checkId)
            onComplete?(updated)
        } catch {
            shareErrorMessage = "Could not share the check. Please try again."
        }
    }
}

