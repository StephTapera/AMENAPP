// AmenMediaSmartActionsView.swift
// AMEN App — Smart Collaboration Layer: Slice 5 — Media Smart Actions
//
// Non-negotiable rules enforced here:
//   1. Media actions render ONLY when a real backend job backs them — no fake UI without a real jobId.
//   2. Flag OFF (threadMediaIntelligenceEnabled) → completely invisible (EmptyView).
//   3. All states handled: no-job (hidden Summarize button), queued, processing, complete, error.
//   4. VoiceOver + Reduce Motion supported throughout.
//   5. No raw media transcript shown without explicit user request.
//   6. Polling stops when state reaches .complete or .error, or after max retries (10).
//   7. Polling only starts after a real jobId is returned from the backend callable.

import SwiftUI
import FirebaseFirestore

// MARK: - AmenMediaJobState

enum AmenMediaJobState: String, Codable {
    case queued
    case processing
    case complete
    case error
}

// MARK: - AmenMediaJobStatus

struct AmenMediaJobStatus: Codable, Identifiable {
    /// Document ID — equals the jobId returned by `requestMediaTranscription`.
    var id: String
    var state: AmenMediaJobState
    var mediaMessageId: String
    /// nil until state == .complete. Never auto-displayed — user must request view.
    var transcriptSummary: String?
    /// Empty until state == .complete.
    var keyMoments: [String]
    /// Populated only when state == .error.
    var errorMessage: String?
}

// MARK: - AmenMediaSmartActionsView

struct AmenMediaSmartActionsView: View {
    let mediaMessageId: String
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    // MARK: Private state

    /// nil = no job in flight. Non-nil = polling is active or terminal.
    @State private var jobStatus: AmenMediaJobStatus?
    @State private var isRequesting = false
    @State private var requestError: String?
    /// Controls whether the completed summary card is expanded.
    @State private var summaryExpanded = false
    /// Toast message for "Coming soon" full-transcript action.
    @State private var toastMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var killSwitch = RemoteKillSwitch.shared

    // MARK: Body

    var body: some View {
        // Rule 2: flag OFF → completely invisible.
        guard killSwitch.threadMediaIntelligenceEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .bottom) {
            mainContent
            if let toast = toastMessage {
                toastBanner(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.22), value: toastMessage)
        // Rule 1 / Rule 7: polling only runs when jobStatus carries a real jobId.
        .task(id: jobStatus?.id) {
            await pollIfNeeded()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let status = jobStatus {
            switch status.state {
            case .queued:
                queuedView
            case .processing:
                processingView
            case .complete:
                completeView(status)
            case .error:
                errorView(status)
            }
        } else {
            // No job yet — compact Summarize trigger (hidden from VoiceOver unless focused).
            noJobView
        }
    }

    // MARK: - No-Job State

    private var noJobView: some View {
        Button {
            Task { await requestTranscription() }
        } label: {
            HStack(spacing: 6) {
                if isRequesting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(isRequesting ? "Requesting…" : "Get transcript summary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRequesting ? .secondary : Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .disabled(isRequesting)
        .accessibilityLabel("Request transcript summary for this media message")
        .overlay(alignment: .trailing) {
            if let err = requestError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Queued State

    private var queuedView: some View {
        HStack(spacing: 8) {
            // Reduce Motion: static indicator instead of spinning spinner.
            if reduceMotion {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.75)
                    .accessibilityHidden(true)
            }
            Text("Queued for transcription\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queued for transcription")
    }

    // MARK: - Processing State

    private var processingView: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.75)
                    .accessibilityHidden(true)
            }
            Text("Transcribing\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcription in progress")
    }

    // MARK: - Complete State

    @ViewBuilder
    private func completeView(_ status: AmenMediaJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Collapsible summary card.
            if let summary = status.transcriptSummary {
                Button {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                        summaryExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Transcript Summary")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: summaryExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Transcript summary available. \(summary)")
                .accessibilityHint(summaryExpanded ? "Double-tap to collapse" : "Double-tap to expand")

                if summaryExpanded {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Key moments chips — only shown when present.
            if !status.keyMoments.isEmpty {
                keyMomentsRow(status.keyMoments)
            }

            // "View full transcript" — gated: no raw transcript without user intent.
            Button {
                showToast("Coming soon")
            } label: {
                Label("View full transcript", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("View full transcript (coming soon)")
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func keyMomentsRow(_ moments: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(moments, id: \.self) { moment in
                    Text(moment)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .accessibilityLabel("Key moment: \(moment)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Key moments")
    }

    // MARK: - Error State

    @ViewBuilder
    private func errorView(_ status: AmenMediaJobStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Transcription unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                Task { await retryTranscription() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Retry transcription for this media message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcription unavailable. Tap Retry to try again.")
    }

    // MARK: - Toast Banner

    @ViewBuilder
    private func toastBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color(.label).opacity(0.85), in: Capsule())
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    // MARK: - Background helpers

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var cardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    // MARK: - Actions

    /// Calls the backend `requestMediaTranscription` callable.
    /// Only sets jobStatus (and starts polling) when a real jobId comes back.
    private func requestTranscription() async {
        isRequesting = true
        requestError = nil

        let payload: [String: Any] = [
            "mediaMessageId": mediaMessageId,
            "threadId": threadId,
            "threadType": threadType.rawValue,
            "spaceId": spaceId as Any,
            "channelId": channelId as Any
        ]

        do {
            let response = try await CloudFunctionsService.shared.call("requestMediaTranscription", data: payload)
            guard let data = response as? [String: Any],
                  let jobId = data["jobId"] as? String,
                  !jobId.isEmpty else {
                // Rule 1: no fake UI — if no real jobId, stay in no-job state.
                requestError = "No job returned. Try again."
                isRequesting = false
                return
            }
            // Seed jobStatus with a real jobId → .task fires polling.
            jobStatus = AmenMediaJobStatus(
                id: jobId,
                state: .queued,
                mediaMessageId: mediaMessageId,
                transcriptSummary: nil,
                keyMoments: [],
                errorMessage: nil
            )
            dlog("[AmenMediaSmartActionsView] job queued: \(jobId)")
        } catch {
            requestError = "Request failed. Try again."
            dlog("[AmenMediaSmartActionsView] requestTranscription error: \(error.localizedDescription)")
        }
        isRequesting = false
    }

    /// Clears the error job and triggers a fresh transcription request.
    private func retryTranscription() async {
        jobStatus = nil
        await requestTranscription()
    }

    /// Polls `mediaJobs/{jobId}` every 3 seconds, max 10 retries.
    /// Stops when state is .complete or .error, or retries are exhausted.
    private func pollIfNeeded() async {
        guard var current = jobStatus else { return }
        // Terminal states don't need polling.
        guard current.state != .complete, current.state != .error else { return }

        let db = Firestore.firestore()
        let maxRetries = 10
        var retries = 0

        while retries < maxRetries {
            // 3-second gap between polls — non-blocking via sleep.
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // Check for task cancellation (e.g. view dismissed).
            guard !Task.isCancelled else {
                dlog("[AmenMediaSmartActionsView] polling cancelled for job \(current.id)")
                return
            }

            do {
                let snapshot = try await db.document("mediaJobs/\(current.id)").getDocument()
                guard snapshot.exists else {
                    dlog("[AmenMediaSmartActionsView] job doc not found yet, retrying (\(retries+1)/\(maxRetries))")
                    retries += 1
                    continue
                }

                let updated = try snapshot.data(as: AmenMediaJobStatus.self)
                current = updated

                await MainActor.run {
                    jobStatus = updated
                }

                dlog("[AmenMediaSmartActionsView] poll \(retries+1): state=\(updated.state.rawValue)")

                if updated.state == .complete || updated.state == .error {
                    return
                }
            } catch {
                dlog("[AmenMediaSmartActionsView] poll error (\(retries+1)/\(maxRetries)): \(error.localizedDescription)")
            }

            retries += 1
        }

        // Max retries reached with no terminal state — surface as error.
        dlog("[AmenMediaSmartActionsView] max retries reached for job \(current.id)")
        await MainActor.run {
            jobStatus = AmenMediaJobStatus(
                id: current.id,
                state: .error,
                mediaMessageId: current.mediaMessageId,
                transcriptSummary: nil,
                keyMoments: [],
                errorMessage: "Timed out waiting for transcription."
            )
        }
    }

    // MARK: - Toast helper

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { toastMessage = nil }
        }
    }
}
