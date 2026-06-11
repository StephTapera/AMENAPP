// FaithJourneyBuilderView.swift
// AMEN Universal Migration & Context System — Wave 1 (faith-builder)
//
// Builds a `FaithJourneyValue` and emits one or more `ContextFacet`s in category
// `.faith_journey`. By contract:
//   • Gated on AMENFeatureFlags.shared.contextSystemEnabled AND contextManualEntryEnabled.
//   • A dedicated faith CONSENT screen (FaithConsentView) precedes any server-readable
//     (Tier C) faith write. Decline → faith facets stay Tier P; faith matching off only.
//   • Every facet's tier is DERIVED from ContextTierTable — never set per-facet. The
//     "areas needing support" facet uses a key ending in `.areas_needing_support`, which
//     ContextTierTable forces to Tier P (client-only, never server-readable).
//   • NO scores / levels / rankings / leaderboards anywhere. Personalizes + connects only.
//   • GlassKit surfaces only; all animation via Motion.adaptive.
//   • Church selection is wired to Find a Church search (selection ONLY — no matching here).
//   • Persistence: ContextStoreService does not yet exist → // TODO(store) + ephemeral @State.

import SwiftUI
import CoreLocation
import FirebaseAuth

struct FaithJourneyBuilderView: View {

    // MARK: Consent
    @ObservedObject private var consent = FaithConsentState.shared
    @State private var showConsent = false

    // MARK: Faith Journey draft (ephemeral — TODO(store): hydrate/persist via ContextStoreService)
    @State private var currentChurchId: String?
    @State private var currentChurchName: String?
    @State private var currentStudy: String = ""
    @State private var favoriteBooks: [String] = []
    @State private var spiritualGoals: [String] = []
    @State private var newGoal: String = ""
    @State private var prayerHabits: [String] = []
    @State private var areasOfGrowth: [String] = []
    @State private var areasNeedingSupport: [String] = []   // ALWAYS Tier P

    // MARK: Church selection (Find a Church search — selection only)
    @State private var churchQuery: String = ""
    @State private var churchResults: [Church] = []
    @State private var isSearchingChurch = false
    @State private var churchSearchTask: Task<Void, Never>?

    // MARK: Save state
    @State private var savedFacets: [ContextFacet] = []   // TODO(store): replace with ContextStoreService write
    @State private var saveError = false

    // Common curated chips (no ranking — just convenience).
    private let bibleBooks = ["Genesis", "Psalms", "Proverbs", "Isaiah", "Matthew",
                              "John", "Acts", "Romans", "Philippians", "James", "Revelation"]
    private let prayerOptions = ["Morning prayer", "Evening prayer", "Prayer journal",
                                 "Praying with others", "Fasting", "Scripture-based prayer"]
    private let growthOptions = ["Consistency in prayer", "Scripture memory", "Patience",
                                 "Serving others", "Forgiveness", "Trust"]
    private let supportOptions = ["Walking through grief", "Doubt & questions", "Anxiety",
                                  "Loneliness", "Temptation", "A broken relationship"]

    // MARK: Body

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.contextSystemEnabled
                && AMENFeatureFlags.shared.contextManualEntryEnabled {
                builder
            } else {
                disabledState
            }
        }
        .faithConsentGate(state: consent, present: $showConsent)
    }

    private var disabledState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cross.fill").font(.title2).foregroundStyle(.secondary)
            Text("Faith Journey is not available right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var builder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                consentBanner

                churchSection
                studySection
                booksSection
                goalsSection
                prayerSection
                growthSection
                supportSection          // Tier P, visibly private

                saveButton
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .shakeOnError(saveError)
    }

    // MARK: Header + consent banner

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Faith Journey")
                .font(.title.weight(.bold))
            Text("This personalizes AMEN and helps connect you. There are no levels, scores, or rankings — ever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var consentBanner: some View {
        if consent.effectiveTierCAllowed {
            banner(icon: "checkmark.seal.fill",
                   tint: .green,
                   text: "Faith matching is on. These details (except “areas needing support”) help AMEN connect you.",
                   action: ("Turn off", { consent.revoke() }))
        } else {
            banner(icon: "lock.fill",
                   tint: .secondary,
                   text: "Faith matching is off. Everything here stays private on this device (Tier P).",
                   action: ("Enable", { showConsent = true }))
        }
    }

    private func banner(icon: String, tint: Color, text: String,
                        action: (title: String, run: () -> Void)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action.title, action: action.run)
                .font(.footnote.weight(.semibold))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Church (search-select)

    private var churchSection: some View {
        sectionCard(title: "Current church", tier: .c,
                    hint: "Pick from Find a Church search. We only record which church you chose.") {
            if let name = currentChurchName {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill").foregroundStyle(.secondary)
                    Text(name).font(.body.weight(.semibold))
                    Spacer()
                    Button {
                        currentChurchId = nil
                        currentChurchName = nil
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search churches…", text: $churchQuery)
                        .textInputAutocapitalization(.words)
                        .onChange(of: churchQuery) { _, q in scheduleChurchSearch(q) }
                    if isSearchingChurch { ProgressView().controlSize(.small) }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ForEach(churchResults) { church in
                    Button {
                        selectChurch(church)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(church.name).font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(church.address) · \(church.denomination)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func scheduleChurchSearch(_ query: String) {
        churchSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { churchResults = []; return }
        churchSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // debounce
            if Task.isCancelled { return }
            await MainActor.run { isSearchingChurch = true }
            // Selection only — Find a Church search. Uses last known location if available.
            let coord = ChurchLocationManager.shared.currentLocation?.coordinate
            let results = (try? await ChurchSearchService.shared.searchChurches(
                query: trimmed, near: coord)) ?? []
            if Task.isCancelled { return }
            await MainActor.run {
                churchResults = Array(results.prefix(8))
                isSearchingChurch = false
            }
        }
    }

    private func selectChurch(_ church: Church) {
        currentChurchId = church.id.uuidString
        currentChurchName = church.name
        churchResults = []
        churchQuery = ""
    }

    // MARK: Study

    private var studySection: some View {
        sectionCard(title: "What you're studying now", tier: .c, hint: nil) {
            TextField("e.g. The Gospel of John, a sermon series…", text: $currentStudy)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Favorite books

    private var booksSection: some View {
        sectionCard(title: "Favorite books of the Bible", tier: .c, hint: nil) {
            chipGrid(options: bibleBooks, selected: $favoriteBooks)
        }
    }

    // MARK: Spiritual goals (+ commitment affordance)

    private var goalsSection: some View {
        sectionCard(title: "Spiritual goals", tier: .c, hint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(spiritualGoals, id: \.self) { goal in
                    HStack {
                        Text(goal).font(.subheadline)
                        Spacer()
                        // Wave 4: bridge a spiritual goal into a real Commitment Object.
                        // Reuses the Action Intelligence creation path via CommitmentBridge.
                        ContextMakeCommitmentButton(
                            facet: faithGoalFacet(for: goal),
                            goalText: goal
                        )
                        Button {
                            spiritualGoals.removeAll { $0 == goal }
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack {
                    TextField("Add a goal…", text: $newGoal)
                    Button {
                        let g = newGoal.trimmingCharacters(in: .whitespaces)
                        guard !g.isEmpty, !spiritualGoals.contains(g) else { return }
                        withAnimation(Motion.adaptive(Motion.appearEase)) { spiritualGoals.append(g) }
                        newGoal = ""
                    } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .disabled(newGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Builds the Tier-C faith goal facet that backs a single spiritual goal so the
    /// CommitmentBridge can convert it into a real Commitment Object with a backlink.
    /// Tier is derived from ContextTierTable for the general faith key (NOT the Tier-P
    /// support key), so this is always server-readable — a goal, never sensitive support.
    private func faithGoalFacet(for goal: String) -> ContextFacet {
        let uid = Auth.auth().currentUser?.uid ?? "local-device"
        let key = "faith.journey.spiritual_goal"
        let value = FaithJourneyValue(
            currentChurchId: nil, currentChurchName: nil, currentStudy: nil,
            favoriteBooks: [], spiritualGoals: [goal], prayerHabits: [],
            areasOfGrowth: [], areasNeedingSupport: []
        )
        return makeFacet(
            uid: uid,
            key: key,
            label: "Spiritual goal",
            value: .faithJourney(value),
            tier: ContextTierTable.tier(for: .faith_journey, key: key)
        )
    }

    // MARK: Prayer habits

    private var prayerSection: some View {
        sectionCard(title: "Prayer habits", tier: .c, hint: nil) {
            chipGrid(options: prayerOptions, selected: $prayerHabits)
        }
    }

    // MARK: Areas of growth

    private var growthSection: some View {
        sectionCard(title: "Areas of growth", tier: .c, hint: nil) {
            chipGrid(options: growthOptions, selected: $areasOfGrowth)
        }
    }

    // MARK: Areas needing support — ALWAYS Tier P

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.green)
                Text("Stays private on this device · never sent to AMEN's servers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                tierBadge(.p)
            }
            Text("Areas where you need support")
                .font(.headline)
            Text("The most sensitive part of your journey. It never leaves your device and never appears in matching, logs, or analytics — even when faith matching is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
            chipGrid(options: supportOptions, selected: $areasNeedingSupport)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                }
        )
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save my Faith Journey")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    /// Builds a `FaithJourneyValue`, then emits `ContextFacet`s in `.faith_journey`.
    /// The general faith facet is Tier C ONLY when consent was accepted; otherwise it
    /// stays Tier P. The "areas needing support" facet is ALWAYS Tier P (forced by its key).
    private func save() {
        let value = FaithJourneyValue(
            currentChurchId: currentChurchId,
            currentChurchName: currentChurchName,
            currentStudy: currentStudy.isEmpty ? nil : currentStudy,
            favoriteBooks: favoriteBooks,
            spiritualGoals: spiritualGoals,
            prayerHabits: prayerHabits,
            areasOfGrowth: areasOfGrowth,
            areasNeedingSupport: areasNeedingSupport
        )

        // Consent gate: if not accepted AND there is server-readable faith content to write,
        // present the consent screen first. Tier-P-only content (support) never needs consent.
        let hasServerReadableContent =
            value.currentChurchName != nil || value.currentStudy != nil ||
            !value.favoriteBooks.isEmpty || !value.spiritualGoals.isEmpty ||
            !value.prayerHabits.isEmpty || !value.areasOfGrowth.isEmpty

        if hasServerReadableContent && !consent.effectiveTierCAllowed {
            showConsent = true
            return
        }

        let uid = Auth.auth().currentUser?.uid ?? "local-device"
        var facets: [ContextFacet] = []

        // 1) General faith facet. Tier derived from ContextTierTable for the general key.
        //    When consent was NOT accepted, we degrade visibility to private and keep it
        //    client-only (Tier P) by routing through the support-style key path below.
        if hasServerReadableContent {
            let generalKey = "faith.journey.general"
            // Tier C is only LEGITIMATE after consent. If declined, force Tier P via key.
            let key = consent.effectiveTierCAllowed ? generalKey : "faith.journey.general.areas_needing_support"
            let tier = ContextTierTable.tier(for: .faith_journey, key: key)
            facets.append(makeFacet(
                uid: uid,
                key: key,
                label: "Faith Journey",
                value: .faithJourney(scrubSupport(from: value, alsoStrip: !consent.effectiveTierCAllowed)),
                tier: tier
            ))
        }

        // 2) Areas needing support — ALWAYS its own Tier-P facet (key suffix forces .p).
        if !value.areasNeedingSupport.isEmpty {
            let supportKey = "faith.journey.areas_needing_support"
            let tier = ContextTierTable.tier(for: .faith_journey, key: supportKey)
            // Carry ONLY the support list so this private facet never co-mingles Tier-C data.
            let supportOnly = FaithJourneyValue(
                currentChurchId: nil, currentChurchName: nil, currentStudy: nil,
                favoriteBooks: [], spiritualGoals: [], prayerHabits: [], areasOfGrowth: [],
                areasNeedingSupport: value.areasNeedingSupport
            )
            facets.append(makeFacet(
                uid: uid,
                key: supportKey,
                label: "Areas needing support (private)",
                value: .faithJourney(supportOnly),
                tier: tier
            ))
        }

        // Invariant: every facet's tier must match the canonical table.
        guard facets.allSatisfy({ $0.hasValidTier }) else {
            triggerSaveError()
            return
        }

        savedFacets = facets
        // Persist through ContextStoreService — its write path re-enforces tier validity,
        // userApproved, and the Aegis C59 sanitization receipt. Tier-P facets are written
        // to the owner-only path and never leave the device through a server-readable route.
        Task {
            for facet in facets {
                do {
                    try await ContextStoreService.shared.saveFacet(facet)
                } catch {
                    print("[FaithJourney] saveFacet failed for \(facet.key): \(error)")
                    await MainActor.run { triggerSaveError() }
                }
            }
        }
    }

    /// Removes the Tier-P support list from the general value so it is never written into
    /// the server-readable facet. When `alsoStrip` is true (consent declined), this is moot
    /// because the whole facet is routed Tier P, but we strip regardless for defense in depth.
    private func scrubSupport(from value: FaithJourneyValue, alsoStrip: Bool) -> FaithJourneyValue {
        var copy = value
        copy.areasNeedingSupport = []   // never co-mingle the most-sensitive list
        return copy
    }

    private func makeFacet(uid: String, key: String, label: String,
                           value: StructuredFacetValue, tier: EncryptionTier) -> ContextFacet {
        let now = Date()
        let provenance = Provenance(
            source: .manual,
            sourceLabel: nil,
            extractedAt: nil,
            confidence: nil,
            userApproved: true,             // user tapped Save in the manual builder
            userEdited: true,
            sanitizationPassId: "manual-entry-no-extraction"  // no LLM extraction on this path
        )
        return ContextFacet(
            id: UUID(),
            userId: uid,
            category: .faith_journey,
            key: key,
            label: label,
            value: value,
            visibility: .privateVisibility,  // contract default; user promotes later
            tier: tier,
            provenance: provenance,
            createdAt: now,
            updatedAt: now,
            schemaVersion: 1
        )
    }

    private func triggerSaveError() {
        saveError = false
        DispatchQueue.main.async { saveError = true }
    }

    // MARK: Reusable UI

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String, tier: EncryptionTier, hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                tierBadge(tier)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private func tierBadge(_ tier: EncryptionTier) -> some View {
        let isPrivate = (tier == .p)
        return Text(isPrivate ? "TIER P" : "TIER C")
            .font(.caption2.weight(.bold))
            .foregroundStyle(isPrivate ? Color.green : Color.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((isPrivate ? Color.green : Color.blue).opacity(0.12))
            )
            .accessibilityLabel(isPrivate
                ? "Tier P. Private on this device."
                : "Tier C. Server-readable after consent.")
    }

    /// Multi-select chip grid. Pure selection — no ordering, scoring, or ranking.
    @ViewBuilder
    private func chipGrid(options: [String], selected: Binding<[String]>) -> some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.wrappedValue.contains(option)
                Button {
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        if isOn { selected.wrappedValue.removeAll { $0 == option } }
                        else { selected.wrappedValue.append(option) }
                    }
                } label: {
                    Text(option)
                        .font(.subheadline)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(isOn ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                        )
                        .overlay {
                            Capsule().stroke(Color.primary.opacity(isOn ? 0.3 : 0.12), lineWidth: 0.5)
                        }
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

#if DEBUG
#Preview("Faith Journey Builder") {
    FaithJourneyBuilderView()
}
#endif
