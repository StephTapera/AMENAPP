// BereanInterviewView.swift
// AMEN Universal Migration & Context System — Wave 2 (interview-ui)
//
// The conversational Migration Interview, lived inside the Passport. Berean asks
// gentle questions; as the user replies, facet *candidates* form live in a
// dismissible "What Berean is learning" sheet. NOTHING persists here — candidates
// only persist through the service's single write path (`approveAndPersist`), and
// only after the user reviews and approves them.
//
// Constraints honored:
//   • Gated on contextSystemEnabled && contextBereanInterviewEnabled (master + sub).
//   • GlassKit surfaces only (no glass-on-glass): one material per stacked layer.
//   • All animation via Motion.adaptive(_:) (reduce-motion safe).
//   • No content import: the user types every word; we never read messages/contacts/photos.
//   • No spiritual ranking: candidates are plain facets, never scored or ordered by faith.
//   • Approval before persistence: this view never writes a ContextFacet directly.
//
// Service binding (BereanMigrationService — rewritten in parallel this wave):
//   • reads  `transcript: [InterviewTurn]` and `facetCandidates: [PendingFacetCandidate]`
//            (both `private(set)` — the view never mutates them).
//   • calls  `startInterviewSession()` (async), `dismissCandidate(_ id: UUID)`,
//            `abortSession()`, and `approveAndPersist(_:userId:)` (the only write path).
//
// `InterviewTurn` is OWNED HERE (the service consumes it). Its `Speaker` carries a
// String raw value and its init takes a timestamp, because the service decodes
// streamed turns via `InterviewTurn.Speaker(rawValue:)` and `InterviewTurn(speaker:text:at:)`.

import SwiftUI
import FirebaseAuth

// MARK: - Ephemeral transcript model (owned by interview-ui; consumed by the service)

struct InterviewTurn: Identifiable, Equatable {
    enum Speaker: String, Equatable { case berean, user }
    let id: UUID
    let speaker: Speaker
    let text: String
    let at: Date

    init(id: UUID = UUID(), speaker: Speaker, text: String, at: Date = Date()) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.at = at
    }
}

struct BereanInterviewView: View {
    @StateObject private var service = BereanMigrationService()
    @StateObject private var flags = AMENFeatureFlags.shared
    @Environment(\.dismiss) private var dismiss

    // Presentation state.
    @State private var draft: String = ""
    @State private var showLearningSheet = false
    @State private var showApproval = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextBereanInterviewEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Migration Interview")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // startInterviewSession() is async on the @MainActor service.
            await service.startInterviewSession()
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            reassuranceBanner

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if service.transcript.isEmpty {
                        openingPrompt
                    } else {
                        ForEach(Array(service.transcript.enumerated()), id: \.element.id) { index, turn in
                            transcriptBubble(turn)
                                .staggeredReveal(index: index)
                        }
                    }
                    learningPreviewInline
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            composerBar
        }
        .safeAreaInset(edge: .bottom) { footerActions }
        .sheet(isPresented: $showLearningSheet) { learningSheet }
        .sheet(isPresented: $showApproval) { approvalSheet }
    }

    // MARK: Opening prompt (shown before the service streams its first turn)

    private var openingPrompt: some View {
        transcriptBubble(
            InterviewTurn(
                speaker: .berean,
                text: "Hey — no rush here. We can build your context together, one small thing at a time. What's something you've been into lately?"
            )
        )
    }

    // MARK: Reassurance (non-negotiable privacy line)

    private var reassuranceBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("We never read your messages, contacts, or photos. Berean only learns from what you choose to type here — and nothing is saved until you review and approve it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
    }

    // MARK: Transcript bubble

    @ViewBuilder
    private func transcriptBubble(_ turn: InterviewTurn) -> some View {
        let isBerean = turn.speaker == .berean
        HStack {
            if !isBerean { Spacer(minLength: 40) }
            VStack(alignment: isBerean ? .leading : .trailing, spacing: 4) {
                Text(isBerean ? "Berean" : "You")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(turn.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous)
                                    .fill(Color.accentColor.opacity(isBerean ? 0 : 0.12))
                            )
                    )
            }
            if isBerean { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isBerean ? "Berean" : "You"): \(turn.text)")
    }

    // MARK: Inline learning preview (taps open the full sheet)

    @ViewBuilder
    private var learningPreviewInline: some View {
        if !service.facetCandidates.isEmpty {
            Button {
                showLearningSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                    Text("What Berean is learning")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(service.facetCandidates.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusMedium, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the list of things Berean is learning. Nothing is saved until you approve it.")
        }
    }

    // MARK: "What Berean is learning" sheet (live, dismissible candidates)

    private var learningSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Forming live as you talk. Nothing here is saved yet — dismiss anything that doesn't fit, then review & approve when you're ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)

                    if service.facetCandidates.isEmpty {
                        emptyLearningState
                    } else {
                        ForEach(Array(service.facetCandidates.enumerated()), id: \.element.id) { index, candidate in
                            candidateCard(candidate)
                                .staggeredReveal(index: index)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("What Berean is learning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showLearningSheet = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Review & approve") {
                        showLearningSheet = false
                        showApproval = true
                    }
                    .disabled(service.facetCandidates.isEmpty)
                }
            }
        }
    }

    private var emptyLearningState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing yet. Keep chatting — candidates will appear here as you share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: Candidate card (dismissible)

    @ViewBuilder
    private func candidateCard(_ pending: PendingFacetCandidate) -> some View {
        let c = pending.candidate
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(c.category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                tierBadge(pending.tier)
                Spacer()
                Button {
                    dismissCandidate(pending)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss \(pending.label)")
            }

            Text(pending.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            let summary = c.value.displaySummary
            if !summary.isEmpty {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Visibility: \(visibilityLabel(c.suggestedVisibility)) · not saved yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func tierBadge(_ tier: EncryptionTier) -> some View {
        Text("Tier \(tier.rawValue)")
            .font(.caption2)
            .foregroundStyle(tier == .p ? .green : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(
                Capsule().stroke((tier == .p ? Color.green : Color.secondary).opacity(0.4), lineWidth: 0.6)
            )
    }

    private func visibilityLabel(_ v: Visibility) -> String {
        switch v {
        case .privateVisibility: return "Private (default)"
        case .friends:           return "Friends"
        case .groups:            return "Groups"
        case .church:            return "Church"
        case .publicVisibility:  return "Public"
        }
    }

    // MARK: Approval routing
    //
    // Wave 3 owns the full Approval UI. The service's `facetCandidates` is `private(set)`
    // and is `[PendingFacetCandidate]`, so we cannot bind it to the Wave-1 `FacetApprovalView`
    // (`@Binding [ContextFacet]`). A minimal inline review list is fine here: it calls the
    // service's single write path, `approveAndPersist`, which derives tier, attaches
    // provenance (.interview, userApproved = true), and writes via ContextStoreService.
    //
    // TODO(wave3-merge): replace this inline list with the real FacetApprovalView once it
    // accepts [PendingFacetCandidate] and per-item approve/edit/visibility controls.

    private var approvalSheet: some View {
        NavigationStack {
            Group {
                if service.facetCandidates.isEmpty {
                    emptyLearningState
                } else {
                    List {
                        Section {
                            ForEach(service.facetCandidates) { pending in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pending.label)
                                        .font(.subheadline.weight(.semibold))
                                    let summary = pending.candidate.value.displaySummary
                                    if !summary.isEmpty {
                                        Text(summary)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 6) {
                                        Text(pending.candidate.category.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        Text("·")
                                        Text(visibilityLabel(pending.candidate.suggestedVisibility))
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        dismissCandidate(pending)
                                    } label: {
                                        Label("Dismiss", systemImage: "xmark")
                                    }
                                }
                            }
                        } header: {
                            Text("These stay private by default. Saving keeps only what's listed here.")
                                .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Review & approve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showApproval = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Approve \(service.facetCandidates.count)") {
                        approveAll()
                    }
                    .disabled(service.facetCandidates.isEmpty)
                }
            }
        }
    }

    // MARK: Composer

    private var composerBar: some View {
        HStack(spacing: 8) {
            TextField("Type a reply… (you control every word)", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial,
                            in: Capsule(style: .continuous))

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDraftEmpty)
            .opacity(isDraftEmpty ? 0.5 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Footer actions

    private var footerActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    stopInterview()
                } label: {
                    Text("Stop — keep what we have")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showApproval = true
                } label: {
                    Text("Review & approve")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(service.facetCandidates.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(service.facetCandidates.isEmpty)
            }

            Text("Stop anytime. Nothing is stored until you approve it on the next screen.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: Actions

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // TODO(wave2-merge): the rewritten service streams transcript turns from its
        // brokered session and has no client-side "send" entry point yet. When a
        // `sendUserMessage(_:)` (or equivalent) lands, call it here so the user's turn
        // and the model's reply flow through the service. Until then we clear the field;
        // the service still owns the transcript (we never mutate `service.transcript`).
        withAnimation(Motion.adaptive(Motion.appearEase)) {
            draft = ""
        }
    }

    private func dismissCandidate(_ pending: PendingFacetCandidate) {
        withAnimation(Motion.adaptive(Motion.unpopToggle)) {
            service.dismissCandidate(pending.id)
        }
    }

    private func approveAll() {
        let toApprove = service.facetCandidates
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else { return }
        showApproval = false
        Task {
            await service.approveAndPersist(toApprove, userId: uid)
            dismiss()
        }
    }

    private func stopInterview() {
        // Stop = end the session; the service persists nothing on abort. The user keeps
        // only whatever was already approved (persisted) before stopping.
        service.abortSession()
        dismiss()
    }
}
