// LifeCapsuleView.swift
// AMEN Universal Migration & Context System — Wave 5 (manual-projection)
//
// The Life Capsule is a PRIVATE, narrative PROJECTION over the owner's facets — a
// gentle "this is who I am right now" summary the owner reads to themselves. It is
// NOT a store and NOT a denormalized copy.
//
// TIER-P CONFIDENTIALITY (non-negotiable):
//   • The narrative is composed entirely CLIENT-SIDE, in this view, from facets
//     already in memory. No facet value is ever sent to a Cloud Function, logged,
//     or written to a server-readable document. (SemanticEmbeddingService was
//     considered and REJECTED for this path: all of its methods POST text to a CF,
//     which would leak facet content off-device — so it is deliberately NOT used.)
//   • Because it can reflect Tier-P facets (relationships/family/health, faith
//     "areas needing support"), the narrative itself is treated as Tier P: it stays
//     on-device and is never persisted anywhere server-readable.
//   • Selective share is a COPY action only: the owner picks individual excerpts and
//     copies them to the clipboard (UIPasteboard). Copying grants NO data access and
//     changes no facet's stored visibility. There is no "share to server" path.
//
// Gated on contextSystemEnabled. No spiritual ranking.

import SwiftUI
import UIKit

struct LifeCapsuleView: View {
    @StateObject private var flags = AMENFeatureFlags.shared
    @StateObject private var store = ContextStoreService.shared

    /// Excerpts the owner has selected to copy. Selection lives only in this view's
    /// transient state — never persisted.
    @State private var selectedExcerpts: Set<String> = []
    @State private var copiedConfirmation = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Life Capsule")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                privacyHeader

                let excerpts = capsuleExcerpts
                if excerpts.isEmpty {
                    emptyState
                } else {
                    narrativeCard(excerpts)
                    selectiveShareSection(excerpts)
                }

                footnote
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await loadIfNeeded() }
    }

    private var privacyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Text("PRIVATE TO YOU")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.pink)
            }
            Text("Your Life Capsule")
                .font(.largeTitle.weight(.bold))
            Text("A quiet, written reflection of who you are right now — composed on your device, from your Passport. It is never sent to a server, never stored online, and never seen by anyone unless you copy a piece of it yourself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func narrativeCard(_ excerpts: [LifeCapsuleExcerpt]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(excerpts) { excerpt in
                Text(excerpt.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassportCardSurface(reduceTransparency: false))
    }

    private func selectiveShareSection(_ excerpts: [LifeCapsuleExcerpt]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share a piece — by copying it")
                .font(.subheadline.weight(.semibold))
            Text("Pick only what you want to share. Selected lines are copied to your clipboard so you can paste them somewhere yourself. Copying never gives anyone access to your Passport.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(excerpts) { excerpt in
                    LifeCapsuleExcerptRow(
                        excerpt: excerpt,
                        isSelected: selectedExcerpts.contains(excerpt.id),
                        toggle: { toggle(excerpt.id) }
                    )
                }
            }

            Button {
                copySelected(excerpts)
            } label: {
                Label(copiedConfirmation ? "Copied to clipboard" : "Copy selected excerpts",
                      systemImage: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedExcerpts.isEmpty)
            .accessibilityLabel(selectedExcerpts.isEmpty
                ? "Select at least one excerpt to copy"
                : "Copy \(selectedExcerpts.count) selected excerpts to clipboard")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassportCardSurface(reduceTransparency: false))
    }

    private var footnote: some View {
        Text("There is no “share online” button here on purpose. The only way anything leaves your Capsule is you copying it. Nothing is ranked.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your Capsule is waiting.")
                .font(.headline)
            Text("As you add to your Passport, a private reflection will gather here — just for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard store.facets.isEmpty, !store.isLoading else { return }
        _ = try? await store.loadFacets()
    }

    // MARK: - Projection (composed client-side; never leaves the device)

    private var capsuleExcerpts: [LifeCapsuleExcerpt] {
        LifeCapsuleComposer.compose(from: store.facets)
    }

    // MARK: - Selection + copy (the ONLY way anything leaves the Capsule)

    private func toggle(_ id: String) {
        withAnimation(Motion.adaptive(Motion.springPress)) {
            if selectedExcerpts.contains(id) { selectedExcerpts.remove(id) }
            else { selectedExcerpts.insert(id) }
        }
    }

    private func copySelected(_ excerpts: [LifeCapsuleExcerpt]) {
        let chosen = excerpts.filter { selectedExcerpts.contains($0.id) }
        guard !chosen.isEmpty else { return }
        UIPasteboard.general.string = chosen.map(\.text).joined(separator: "\n\n")
        withAnimation(Motion.adaptive(Motion.springPress)) { copiedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(Motion.adaptive(Motion.springPress)) { copiedConfirmation = false }
        }
    }
}

// MARK: - Excerpt model + client-side composition (pure, on-device)

/// One sentence/line of the private narrative. Composed in-memory; never stored.
struct LifeCapsuleExcerpt: Identifiable {
    let id: String
    let text: String
}

/// Pure client-side narrative composer. No networking, no persistence, no CF calls,
/// no ranking. Runs entirely on the facets already in memory — so it can safely
/// reflect Tier-P facets without ever exposing them to a server-readable path.
enum LifeCapsuleComposer {

    /// Compose gentle, first-person reflection lines from the owner's facets.
    /// Order follows the canonical facet category order for stability; it is NOT a
    /// ranking of importance.
    static func compose(from facets: [ContextFacet]) -> [LifeCapsuleExcerpt] {
        guard !facets.isEmpty else { return [] }

        var lines: [LifeCapsuleExcerpt] = []

        func summaries(_ category: FacetCategory) -> [String] {
            facets
                .filter { $0.category == category }
                .map { $0.value.displaySummary.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func add(_ id: String, _ text: String) {
            lines.append(LifeCapsuleExcerpt(id: id, text: text))
        }

        let values = summaries(.values)
        if !values.isEmpty {
            add("values", "Right now, what matters most to me is \(naturalList(values)).")
        }

        let interests = summaries(.interests)
        if !interests.isEmpty {
            add("interests", "I find myself drawn to \(naturalList(interests)).")
        }

        let focus = summaries(.current_focus) + summaries(.goals)
        if !focus.isEmpty {
            add("focus", "These days I'm focused on \(naturalList(focus)).")
        }

        let work = summaries(.work)
        if !work.isEmpty {
            add("work", "In my work, \(naturalList(work)).")
        }

        let learning = summaries(.learning)
        if !learning.isEmpty {
            add("learning", "I tend to learn best through \(naturalList(learning)).")
        }

        let communication = summaries(.communication)
        if !communication.isEmpty {
            add("communication", "When I connect with people, \(naturalList(communication)).")
        }

        let skills = summaries(.skills)
        if !skills.isEmpty {
            add("skills", "Some things I bring with me: \(naturalList(skills)).")
        }

        // Tier-P-bearing reflections live ONLY here, on-device, and are never copied
        // unless the owner explicitly selects them.
        let relationships = summaries(.relationships)
        if !relationships.isEmpty {
            add("relationships", "The people and circles I hold close include \(naturalList(relationships)).")
        }

        let faith = summaries(.faith_journey)
        if !faith.isEmpty {
            add("faith", "On my faith journey, \(naturalList(faith)).")
        }

        return lines
    }

    /// Join items into a calm, human list ("a, b, and c"). No ranking implied.
    private static func naturalList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last ?? "")"
        }
    }
}

// MARK: - Excerpt row (selectable; single-layer surface)

struct LifeCapsuleExcerptRow: View {
    let excerpt: LifeCapsuleExcerpt
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(excerpt.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous)
                    .stroke(Color.primary.opacity(isSelected ? 0.16 : 0.08), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Double-tap to \(isSelected ? "remove from" : "add to") your copy selection.")
    }
}
