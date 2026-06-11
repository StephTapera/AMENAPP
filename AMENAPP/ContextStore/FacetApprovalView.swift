// FacetApprovalView.swift
// AMEN Universal Migration & Context System — Wave 3 (approval-ui)
//
// THE approval surface for the Context System. The orchestration calls this
// "the single most important screen in this system" and the reason is one
// invariant: NOTHING PERSISTS UNTIL THE USER APPROVES.
//
// Currency: this view operates on PROPOSED facets — `[ContextFacet]` whose
// `provenance.userApproved == false`. Both the Wave 2 Berean Migration Interview
// and the Wave 3 Universal Extractor convert their candidates into proposed
// ContextFacets and hand them to THIS view. It is the canonical approval surface
// (BereanInterviewView's inline list is superseded — TODO(gate: HUMAN-MACHINE) — wave3-merge: swap once FacetApprovalView accepts [PendingFacetCandidate]).
//
// Hard rules honored here (CONTRACTS §9):
//   - Approval before persistence. We ONLY call ContextStoreService.shared.saveFacet
//     after the user approves a card (which sets provenance.userApproved = true).
//     No timer, onAppear, or bulk path writes an un-approved facet.
//   - New facets default to visibility .privateVisibility. The visibility control
//     starts Private and the user may relax it before approving.
//   - GlassKit only (AmenLiquidGlassPillButton / capsule surface), no glass-on-glass.
//   - All animation via Motion.adaptive (reduce-motion safe).
//   - No spiritual ranking. Confidence is EXTRACTION confidence, shown as such.
//   - Flag-gated on contextSystemEnabled.
//
// Instrumentation (spec §9, extraction-quality metrics): the view-model exposes
// AGGREGATE COUNTS ONLY — % edited and % rejected. It never records, logs, or
// emits any facet value, label, key, or category. Counts only.

import SwiftUI

// MARK: - Metrics view-model (aggregate counts only — NO facet contents)

/// Extraction-quality instrumentation for the approval session.
///
/// Privacy contract: this object stores ONLY integer counters. It must never
/// hold a facet, its value, label, key, or category. The published percentages
/// are derived from counts and are the only thing analytics may read.
@MainActor
final class FacetApprovalMetrics: ObservableObject {

    /// Total proposed facets shown in this session (the denominator).
    @Published private(set) var totalProposed: Int = 0
    /// How many the user edited before approving.
    @Published private(set) var editedCount: Int = 0
    /// How many the user rejected outright.
    @Published private(set) var rejectedCount: Int = 0
    /// How many the user approved.
    @Published private(set) var approvedCount: Int = 0

    /// % of proposed facets the user edited (extraction-quality signal).
    var percentEdited: Double {
        totalProposed > 0 ? Double(editedCount) / Double(totalProposed) : 0
    }

    /// % of proposed facets the user rejected (extraction-quality signal).
    var percentRejected: Double {
        totalProposed > 0 ? Double(rejectedCount) / Double(totalProposed) : 0
    }

    /// Seed the denominator once, when the candidate set is first presented.
    func setTotalIfNeeded(_ count: Int) {
        if totalProposed == 0 { totalProposed = count }
    }

    func recordEdited()   { editedCount += 1 }
    func recordRejected() { rejectedCount += 1 }
    func recordApproved() { approvedCount += 1 }
}

// MARK: - FacetApprovalView

struct FacetApprovalView: View {

    /// Proposed candidates. Mutated in place as the user edits visibility/value;
    /// removed from the array once approved (persisted) or rejected (discarded).
    @Binding var candidates: [ContextFacet]

    @StateObject private var flags = AMENFeatureFlags.shared
    @StateObject private var metrics = FacetApprovalMetrics()

    /// Card whose value is being edited inline (by facet id).
    @State private var editingID: UUID? = nil
    @State private var saveError = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Review what we found")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { metrics.setTotalIfNeeded(candidates.count) }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro

                if candidates.isEmpty {
                    allDoneNotice
                } else {
                    ForEach(orderedCategories, id: \.self) { category in
                        categorySection(category)
                    }
                    bulkBar
                }
            }
            .padding()
        }
        .shakeOnError(saveError)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing is saved until you approve it. Each item is private by default — you choose who can see it. Edit or reject anything.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AmenAIUsageLabel(text: "AI-assisted · you decide what's kept")
        }
    }

    private var allDoneNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.title2)
                .foregroundStyle(.green)
            Text("All set. Everything you approved is saved and private by default.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Category section (approve-all / reject-all)

    @ViewBuilder
    private func categorySection(_ category: FacetCategory) -> some View {
        let items = candidates.filter { $0.category == category }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(displayName(category).uppercased())
                        .font(.caption.weight(.bold))
                        .kerning(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Approve all") { approveAll(in: category) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                    Button("Reject all") { rejectAll(in: category) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                }

                ForEach(items) { facet in
                    candidateCard(facet)
                }
            }
        }
    }

    // MARK: Candidate card

    private func candidateCard(_ facet: ContextFacet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(facet.label)
                .font(.headline)
                .foregroundStyle(.primary)

            valueView(for: facet)

            HStack(spacing: 8) {
                metaChip(sourceText(facet.provenance))
                if let conf = facet.provenance.confidence {
                    metaChip(confidenceText(conf), highlight: conf >= 0.75)
                }
                if facet.provenance.userEdited {
                    metaChip("Edited")
                }
            }

            // Visibility control — defaults to Private; user may relax before approving.
            VisibilityControl(visibility: bindingForVisibility(facet))

            actionRow(for: facet)
        }
        .padding(16)
        .background(cardSurface)
        .feedItemAppear(id: facet.id)
    }

    @ViewBuilder
    private func valueView(for facet: ContextFacet) -> some View {
        if editingID == facet.id, case .text(let current) = facet.value {
            TextField("Value", text: bindingForText(facet, current: current), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
        } else {
            Text(facet.value.displaySummary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionRow(for facet: ContextFacet) -> some View {
        HStack(spacing: 8) {
            AmenLiquidGlassPillButton(
                title: "Approve",
                systemImage: "checkmark",
                isLoading: false,
                isDisabled: false
            ) { approve(facet) }

            AmenLiquidGlassPillButton(
                title: editingID == facet.id ? "Done" : "Edit",
                systemImage: "pencil",
                isLoading: false,
                isDisabled: !isEditable(facet)
            ) { toggleEdit(facet) }

            AmenLiquidGlassPillButton(
                title: "Reject",
                systemImage: "xmark",
                isLoading: false,
                isDisabled: false
            ) { reject(facet) }
        }
    }

    // MARK: Bulk bar

    private var bulkBar: some View {
        VStack(spacing: 8) {
            Text("Confidence shows how sure the extractor is — never a measure of you. No item is ranked spiritually.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                AmenLiquidGlassPillButton(
                    title: "Approve all remaining",
                    systemImage: "checkmark.circle",
                    isLoading: false,
                    isDisabled: false
                ) { approveAllRemaining() }

                AmenLiquidGlassPillButton(
                    title: "Reject all remaining",
                    systemImage: "xmark.circle",
                    isLoading: false,
                    isDisabled: false
                ) { rejectAllRemaining() }
            }
        }
        .padding(.top, 8)
    }

    // MARK: Small pieces

    private func metaChip(_ text: String, highlight: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(highlight ? Color.green : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.6))
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

    // MARK: - Actions (the only persistence path is approve)

    /// Approve a single facet: set userApproved = true and persist via the store.
    /// This is the ONLY method that writes. Nothing else persists.
    private func approve(_ facet: ContextFacet) {
        guard let idx = candidates.firstIndex(where: { $0.id == facet.id }) else { return }
        var toSave = candidates[idx]
        toSave.provenance.userApproved = true
        toSave.updatedAt = Date()

        Task {
            do {
                try await ContextStoreService.shared.saveFacet(toSave)
                await MainActor.run {
                    metrics.recordApproved()
                    if editingID == facet.id { editingID = nil }
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        candidates.removeAll { $0.id == facet.id }
                    }
                }
            } catch {
                // Persistence guard failed (tier, sanitization, sign-in, gate).
                // Keep the card so the user can retry; never silently drop.
                await MainActor.run {
                    saveError.toggle()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    /// Reject a single facet: discard it. NOTHING is persisted.
    private func reject(_ facet: ContextFacet) {
        metrics.recordRejected()
        if editingID == facet.id { editingID = nil }
        withAnimation(Motion.adaptive(Motion.unpopToggle)) {
            candidates.removeAll { $0.id == facet.id }
        }
    }

    /// Toggle inline edit. Closing an edit marks the facet userEdited = true
    /// (the extraction was changed by the user) and counts it for metrics once.
    private func toggleEdit(_ facet: ContextFacet) {
        if editingID == facet.id {
            // Finishing edit.
            if let idx = candidates.firstIndex(where: { $0.id == facet.id }),
               !candidates[idx].provenance.userEdited {
                candidates[idx].provenance.userEdited = true
                candidates[idx].updatedAt = Date()
                metrics.recordEdited()
            }
            withAnimation(Motion.adaptive(Motion.springRelease)) { editingID = nil }
        } else {
            withAnimation(Motion.adaptive(Motion.springPress)) { editingID = facet.id }
        }
    }

    private func approveAll(in category: FacetCategory) {
        for facet in candidates.filter({ $0.category == category }) {
            approve(facet)
        }
    }

    private func rejectAll(in category: FacetCategory) {
        let toReject = candidates.filter { $0.category == category }
        for _ in toReject { metrics.recordRejected() }
        withAnimation(Motion.adaptive(Motion.unpopToggle)) {
            candidates.removeAll { $0.category == category }
        }
    }

    private func approveAllRemaining() {
        for facet in candidates { approve(facet) }
    }

    private func rejectAllRemaining() {
        for _ in candidates { metrics.recordRejected() }
        withAnimation(Motion.adaptive(Motion.unpopToggle)) {
            candidates.removeAll()
        }
    }

    // MARK: - Bindings

    private func bindingForVisibility(_ facet: ContextFacet) -> Binding<Visibility> {
        Binding(
            get: { candidates.first(where: { $0.id == facet.id })?.visibility ?? .privateVisibility },
            set: { newValue in
                if let idx = candidates.firstIndex(where: { $0.id == facet.id }) {
                    candidates[idx].visibility = newValue
                }
            }
        )
    }

    private func bindingForText(_ facet: ContextFacet, current: String) -> Binding<String> {
        Binding(
            get: {
                if let f = candidates.first(where: { $0.id == facet.id }),
                   case .text(let v) = f.value { return v }
                return current
            },
            set: { newValue in
                if let idx = candidates.firstIndex(where: { $0.id == facet.id }) {
                    candidates[idx].value = .text(newValue)
                }
            }
        )
    }

    // MARK: - Helpers

    /// Only plain-text facets are inline-editable here; structured values
    /// (faith journey, communication, relationship category) are edited upstream.
    private func isEditable(_ facet: ContextFacet) -> Bool {
        if case .text = facet.value { return true }
        return false
    }

    /// Categories in a stable display order, restricted to those present.
    private var orderedCategories: [FacetCategory] {
        FacetCategory.allCases.filter { cat in candidates.contains { $0.category == cat } }
    }

    private func sourceText(_ prov: Provenance) -> String {
        let base: String
        switch prov.source {
        case .manual:           base = "You entered this"
        case .interview:        base = "Migration interview"
        case .extracted_paste:  base = "Pasted text"
        case .extracted_file:   base = "Uploaded file"
        case .derived:          base = "Suggested"
        }
        if let label = prov.sourceLabel, !label.isEmpty {
            return "Source: \(label)"
        }
        return "Source: \(base)"
    }

    private func confidenceText(_ confidence: Double) -> String {
        let pct = Int((confidence * 100).rounded())
        return "Confidence: \(pct)%"
    }

    private func displayName(_ category: FacetCategory) -> String {
        switch category {
        case .interests:      return "Interests"
        case .values:         return "Values"
        case .goals:          return "Goals"
        case .skills:         return "Skills"
        case .communities:    return "Communities"
        case .relationships:  return "Relationships"
        case .communication:  return "Communication"
        case .learning:       return "Learning"
        case .faith_journey:  return "Faith journey"
        case .current_focus:  return "Current focus"
        case .family:         return "Family"
        case .work:           return "Work"
        case .health:         return "Health"
        }
    }
}
