// IntroductionDraftView.swift
// AMEN Universal Migration & Context System — Wave 4 (intro-generator)
//
// THE intro surface. It asks `generateIntroduction` for a community-specific self-
// introduction drafted from the user's OWN context facets, shows that draft in an
// EDITABLE field, and routes any posting through the app's normal post composer
// (CreatePostView). It NEVER auto-posts and NEVER persists anything itself.
//
// Hard rules honored here (CONTRACTS §7 + §9):
//   • Flag-gated on contextSystemEnabled && contextMatchingEnabled. Nothing renders or
//     calls the CF unless both are true.
//   • ONLY public/groups-visible facet keys are ever sent. We pick them on-device from the
//     user's own facets; the CF re-validates visibility AND tier server-side and drops
//     anything private/Tier-P. Two independent gates — client picks, server enforces.
//   • The draft is ALWAYS editable before it can go anywhere (a plain TextEditor bound to
//     @State). The user can rewrite it entirely.
//   • NEVER auto-posts. The only way text leaves this screen is the user tapping "Use in a
//     post", which opens CreatePostView pre-filled with the (edited) draft. The user still
//     has to actually post there. A Copy button is offered as a no-network alternative.
//   • GlassKit only (AmenLiquidGlassPillButton + ultraThinMaterial card), no glass-on-glass.
//   • All animation via Motion.adaptive (reduce-motion safe).
//   • No spiritual ranking — copy + the CF's own scrub both refuse ranking framing.

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - View model

/// Drives one intro-draft session for a single community. Holds ephemeral state only —
/// it persists nothing and never logs a facet value or the draft body.
@MainActor
final class IntroductionDraftViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case ready          // a draft (possibly empty) was produced
        case empty          // no eligible public/groups facets — invite manual write
        case failed         // the request failed; user may retry or write their own
    }

    @Published var draft: String = ""
    @Published private(set) var phase: Phase = .idle
    /// How many public/groups-visible facet keys we found to send (display only — count, never values).
    @Published private(set) var eligibleFacetCount: Int = 0

    private let communityId: String
    private var _store: ContextStoreService?
    private var store: ContextStoreService { _store ?? ContextStoreService.shared }
    private let functions: Functions

    init(communityId: String,
         store: ContextStoreService? = nil,
         functions: Functions = Functions.functions()) {
        self.communityId = communityId
        self._store = store
        self.functions = functions
    }

    /// Collect the user's PUBLIC/GROUPS-visible facet keys on-device. Private / friends /
    /// church / Tier-P facets are never selected here, and the server re-validates regardless.
    /// Returns keys only — never values.
    private func eligibleFacetKeys(from facets: [ContextFacet]) -> [String] {
        facets
            .filter { $0.visibility == .publicVisibility || $0.visibility == .groups }
            // Belt-and-suspenders: never send a Tier-P key even if its visibility were relaxed.
            .filter { ContextTierTable.isServerReadable($0.tier) }
            .map { $0.key }
            .filter { !$0.isEmpty }
    }

    /// Load facets, pick eligible keys, and request a draft. Fails closed (empty/failed) — never
    /// fabricates. Safe to call again to retry.
    func generate(flags: AMENFeatureFlags) async {
        guard flags.contextSystemEnabled && flags.contextMatchingEnabled else {
            phase = .failed
            return
        }
        guard Auth.auth().currentUser?.uid != nil else {
            phase = .failed
            return
        }

        phase = .loading

        // Read the owner's own facets (the store enforces the master gate + owner identity).
        let facets: [ContextFacet]
        do {
            facets = try await store.loadFacets()
        } catch {
            phase = .failed
            return
        }

        let keys = eligibleFacetKeys(from: facets)
        eligibleFacetCount = keys.count

        guard !keys.isEmpty else {
            // Nothing shareable — invite the user to write their own intro.
            phase = .empty
            return
        }

        do {
            let callable = functions.httpsCallable("generateIntroduction")
            let result = try await callable.call([
                "communityId": communityId,
                "facetKeys": keys,
            ])
            let payload = result.data as? [String: Any]
            let serverDraft = (payload?["draft"] as? String) ?? ""

            if serverDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Server gated everything out or fail-closed — let the user write their own.
                phase = .empty
            } else {
                draft = serverDraft
                phase = .ready
            }
        } catch {
            phase = .failed
        }
    }
}

// MARK: - IntroductionDraftView

struct IntroductionDraftView: View {

    /// Community the user is introducing themselves to. Passed straight to the CF as an
    /// identifier (never another user's data).
    let communityId: String
    /// Friendly name for the community, for the header copy. Optional.
    var communityName: String? = nil

    @StateObject private var flags = AMENFeatureFlags.shared
    @StateObject private var model: IntroductionDraftViewModel

    @State private var showComposer = false
    @State private var copiedConfirmation = false

    init(communityId: String, communityName: String? = nil) {
        self.communityId = communityId
        self.communityName = communityName
        _model = StateObject(wrappedValue: IntroductionDraftViewModel(communityId: communityId))
    }

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextMatchingEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Introduce yourself")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.phase == .idle {
                await model.generate(flags: flags)
            }
        }
        .sheet(isPresented: $showComposer) {
            // Route posting through the app's normal composer, pre-filled with the EDITED draft.
            // The user still has to actually post there — this view never auto-posts.
            CreatePostView(initialText: model.draft)
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stateBody
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerTitle)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("This draft is built only from what you've already marked public or visible to groups — nothing private. Edit it freely; nothing is posted until you choose to.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenAIUsageLabel(text: "AI-assisted draft · you edit & decide")
        }
    }

    private var headerTitle: String {
        if let name = communityName, !name.isEmpty {
            return "A first hello for \(name)"
        }
        return "A first hello"
    }

    @ViewBuilder
    private var stateBody: some View {
        switch model.phase {
        case .idle, .loading:
            loadingCard
        case .ready:
            editorCard
            actionRow
            disclaimer
        case .empty:
            emptyCard
        case .failed:
            failedCard
        }
    }

    // MARK: Cards

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Drafting from your public context…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardSurface)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR DRAFT — EDIT ANYTHING")
                .font(.caption.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(.secondary)

            // The draft is ALWAYS editable. This is the only place the text lives before the
            // user chooses to use it; there is no hidden auto-post path.
            TextEditor(text: $model.draft)
                .frame(minHeight: 160)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
                )
                .accessibilityLabel("Editable introduction draft")
        }
        .padding(16)
        .background(cardSurface)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            // Routes through the normal composer — NEVER posts directly.
            AmenLiquidGlassPillButton(
                title: "Use in a post",
                systemImage: "square.and.pencil",
                isLoading: false,
                isDisabled: trimmedDraft.isEmpty
            ) { showComposer = true }

            AmenLiquidGlassPillButton(
                title: copiedConfirmation ? "Copied" : "Copy",
                systemImage: copiedConfirmation ? "checkmark" : "doc.on.doc",
                isLoading: false,
                isDisabled: trimmedDraft.isEmpty
            ) { copyDraft() }

            AmenLiquidGlassPillButton(
                title: "Redraft",
                systemImage: "arrow.clockwise",
                isLoading: model.phase == .loading,
                isDisabled: model.phase == .loading
            ) { Task { await model.generate(flags: flags) } }
        }
    }

    private var disclaimer: some View {
        Text("Nothing is posted automatically. \"Use in a post\" opens the normal composer with your edited draft — you decide whether to share it. No part of this ranks you or anyone spiritually.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing public to draft from — yet.")
                .font(.headline)
            Text("We only draft from context you've marked public or visible to groups. You haven't shared any yet, so there's nothing to build a draft from. You can introduce yourself in your own words instead.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenLiquidGlassPillButton(
                title: "Write my own",
                systemImage: "square.and.pencil",
                isLoading: false,
                isDisabled: false
            ) {
                // Open the composer empty — the user writes their own intro.
                model.draft = ""
                showComposer = true
            }
        }
        .padding(16)
        .background(cardSurface)
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't draft an introduction.")
                .font(.headline)
            Text("Something went wrong reaching the draft service. You can try again, or just introduce yourself in your own words.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                AmenLiquidGlassPillButton(
                    title: "Try again",
                    systemImage: "arrow.clockwise",
                    isLoading: false,
                    isDisabled: false
                ) { Task { await model.generate(flags: flags) } }

                AmenLiquidGlassPillButton(
                    title: "Write my own",
                    systemImage: "square.and.pencil",
                    isLoading: false,
                    isDisabled: false
                ) {
                    model.draft = ""
                    showComposer = true
                }
            }
        }
        .padding(16)
        .background(cardSurface)
    }

    // MARK: Helpers

    private var trimmedDraft: String {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyDraft() {
        UIPasteboard.general.string = model.draft
        withAnimation(Motion.adaptive(Motion.popToggle)) { copiedConfirmation = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                withAnimation(Motion.adaptive(Motion.springPress)) { copiedConfirmation = false }
            }
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusLarge, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusLarge, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: AmenGlassMetrics.borderWidth)
            )
            .shadow(color: .black.opacity(0.06), radius: AmenGlassMetrics.shadowRadius, y: 4)
    }
}
