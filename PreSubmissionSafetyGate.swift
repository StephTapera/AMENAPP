// PreSubmissionSafetyGate.swift
// AMENAPP
//
// SwiftUI view modifier and submit-button wrapper that runs content
// through SafetyOrchestrator before allowing a post, comment,
// prayer request, or message to be published.
//
// Usage — wrap your existing submit action:
//
//   PostSubmitButton(text: $postText, context: .post) {
//       // This block only executes if content passes the safety gate
//       viewModel.publishPost(postText)
//   }
//
// Or use the view modifier on any submit button:
//
//   Button("Post") { viewModel.publishPost(text) }
//       .safetyGated(text: text, context: .post) { viewModel.publishPost(text) }
//
// Design:
//   - Non-blocking for safe content (< 5ms typical)
//   - Shows inline loading indicator during evaluation
//   - Routes the author to the appropriate support surface when needed
//   - Never reveals internal scoring to the user
//   - Blocked content shows a clear, kind, non-judgmental message

import SwiftUI

// MARK: - Safety Gate State

private enum GateState: Equatable {
    case idle
    case evaluating
    case blocked(userMessage: String)
    case reviewing(userMessage: String)  // "under review" — not permanently blocked
    case passed
}

// MARK: - Pre-Submission Gate View Modifier

/// `onAllowed` is called when content may be published.
/// `reviewPending` is true when the post must be written with `reviewStatus: "pending"`
/// so it is hidden from other users' feeds until a moderator approves it.
struct PreSubmissionSafetyGate: ViewModifier {
    let text: String
    let context: SafetyContentContext
    /// Called when content is allowed. `reviewPending` is true when the post must be
    /// stored with `reviewStatus: "pending"` to hide it from feeds until reviewed.
    let onAllowed: (_ reviewPending: Bool) -> Void

    @State private var gateState: GateState = .idle
    @State private var showBlockedSheet = false
    @State private var blockedMessage = ""
    @State private var reviewMessage = ""

    func body(content: Content) -> some View {
        content
            .disabled(gateState == .evaluating)
            .overlay {
                if gateState == .evaluating {
                    // Inline shimmer over the button
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5).opacity(0.6))
                        .overlay {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.85)
                        }
                }
            }
            .onTapGesture {
                evaluate()
            }
            .sheet(isPresented: $showBlockedSheet) {
                SafetyGateBlockedSheet(
                    message: blockedMessage,
                    isReview: gateState == .reviewing(userMessage: reviewMessage),
                    onDismiss: {
                        showBlockedSheet = false
                        gateState = .idle
                    }
                )
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
    }

    private func evaluate() {
        guard gateState == .idle else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onAllowed(false)
            return
        }

        gateState = .evaluating

        SafetyOrchestrator.shared.evaluateBeforeSubmit(
            text: trimmed,
            context: context
        ) { decision in
            switch decision.action {

            case .allow:
                gateState = .passed
                onAllowed(false)
                // Reset after a tick so the button re-enables
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    gateState = .idle
                }

            case .allowWithWarning:
                // Allow publish but surface adaptive support to author
                gateState = .passed
                onAllowed(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    gateState = .idle
                }

            case .holdForSoftReview:
                let msg = decision.userFacingMessage
                    ?? "Your post is being reviewed before it's shared. This usually takes just a moment."
                reviewMessage = msg
                blockedMessage = msg
                gateState = .reviewing(userMessage: msg)
                showBlockedSheet = true
                // Call onAllowed with reviewPending=true so the caller stores
                // reviewStatus: "pending" on the Firestore document, hiding it
                // from other users' feeds until a moderator approves it.
                onAllowed(true)

            case .blockAndReview:
                let msg = decision.userFacingMessage
                    ?? "This content couldn't be posted right now. If you need support, we're here."
                blockedMessage = msg
                gateState = .blocked(userMessage: msg)
                showBlockedSheet = true
                // Do NOT call onAllowed — content is blocked

            case .blockImmediate:
                let msg = decision.userFacingMessage
                    ?? "This content couldn't be posted. It may not align with our community guidelines."
                blockedMessage = msg
                gateState = .blocked(userMessage: msg)
                showBlockedSheet = true
                // Do NOT call onAllowed
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Intercepts a tap and runs the text through the safety gate before calling `onAllowed`.
    /// `reviewPending` will be true when the post must be stored with `reviewStatus: "pending"`.
    func safetyGated(
        text: String,
        context: SafetyContentContext,
        onAllowed: @escaping (_ reviewPending: Bool) -> Void
    ) -> some View {
        modifier(PreSubmissionSafetyGate(text: text, context: context, onAllowed: onAllowed))
    }
}

// MARK: - Pre-built Submit Button

/// Drop-in submit button with the gate built in.
/// Replaces a plain Button("Post") for post/comment surfaces.
struct SafetyGatedSubmitButton: View {
    let label: String
    let text: String
    let context: SafetyContentContext
    let isDisabled: Bool
    let onAllowed: (_ reviewPending: Bool) -> Void

    @State private var isEvaluating = false

    var body: some View {
        Button {
            guard !isDisabled, !isEvaluating else { return }
            runGate()
        } label: {
            HStack(spacing: 8) {
                if isEvaluating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(.white)
                }
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                isDisabled || isEvaluating
                    ? Color(.systemGray3)
                    : Color(red: 0.16, green: 0.40, blue: 0.76),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isEvaluating)
        .animation(.easeOut(duration: 0.15), value: isEvaluating)
        .animation(.easeOut(duration: 0.15), value: isDisabled)
    }

    private func runGate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onAllowed(false)
            return
        }

        isEvaluating = true

        SafetyOrchestrator.shared.evaluateBeforeSubmit(
            text: trimmed,
            context: context
        ) { decision in
            isEvaluating = false
            switch decision.action {
            case .allow, .allowWithWarning:
                onAllowed(false)
            case .holdForSoftReview:
                // Submit but mark as pending review so feed hides it from others
                onAllowed(true)
            case .blockAndReview, .blockImmediate:
                // blocked — the orchestrator will have surfaced support UI
                break
            }
        }
    }
}

// MARK: - Blocked Sheet

private struct SafetyGateBlockedSheet: View {
    let message: String
    let isReview: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Image(systemName: isReview ? "clock.badge.checkmark" : "exclamationmark.triangle")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(isReview ? Color(red: 0.36, green: 0.58, blue: 0.82) : Color(red: 0.85, green: 0.50, blue: 0.28))
                .padding(.top, 8)

            Text(isReview ? "Your post is under review" : "Content couldn't be posted")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            if !isReview {
                // Resources for blocked content
                VStack(spacing: 10) {
                    Button {
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.35))
                            Text("Call 988 — free, confidential support")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Text(isReview ? "Got it" : "Dismiss")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.16, green: 0.40, blue: 0.76), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Passive Feed Scanner Hook

/// Call this in a LazyVStack's `onAppear` for each feed item to
/// passively track content exposure without blocking the UI.
struct PassiveFeedSafetyScanner {
    static func scan(text: String, context: SafetyContentContext) {
        Task.detached(priority: .background) {
            await MainActor.run {
                SafetyOrchestrator.shared.noteContentExposure(text: text, context: context)
            }
        }
    }
}
