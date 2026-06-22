// IdentityBlueprintView.swift
// AMEN Universal Migration & Context System — Wave 1 (passport-ui)
//
// The Identity Blueprint is a PROJECTION over ContextStore facets — never a
// separate store. It groups the user's facets by category, shows each facet's
// tier and visibility badge, and allows in-place visibility edits.
//
// Facets are provided by the caller (eventually ContextStoreService). When no
// store is wired, callers pass an empty array and an empty-state is shown.
// Visibility edits are surfaced via onVisibilityChange so the owner can persist.

import SwiftUI

struct IdentityBlueprintView: View {
    @StateObject private var flags = AMENFeatureFlags.shared

    /// Facets to project. Owned/persisted elsewhere (TODO(gate: HUMAN-MACHINE) — store: hydrate from ContextStoreService).
    let facets: [ContextFacet]
    /// Called when the user changes a facet's visibility in place.
    var onVisibilityChange: (ContextFacet, Visibility) -> Void

    init(
        facets: [ContextFacet] = [],
        onVisibilityChange: @escaping (ContextFacet, Visibility) -> Void = { _, _ in }
    ) {
        self.facets = facets
        self.onVisibilityChange = onVisibilityChange
    }

    var body: some View {
        Group {
            if flags.contextSystemEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Identity Blueprint")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("A projection of your facets, grouped by category. Tap a badge to change who sees it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(orderedCategories, id: \.self) { category in
                        if let items = grouped[category], !items.isEmpty {
                            BlueprintCategoryGroup(
                                category: category,
                                facets: items,
                                onVisibilityChange: onVisibilityChange
                            )
                        }
                    }
                }

                Text("Relationships, family & health facets are always Tier P — private, never server-readable.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Your Passport is empty.")
                .font(.headline)
            Text("Add a few things about yourself to start your Blueprint.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var grouped: [FacetCategory: [ContextFacet]] {
        Dictionary(grouping: facets, by: { $0.category })
    }

    /// Stable category order = the canonical declaration order.
    private var orderedCategories: [FacetCategory] { FacetCategory.allCases }
}

// MARK: - Category group (single-layer glass card)

struct BlueprintCategoryGroup: View {
    let category: FacetCategory
    let facets: [ContextFacet]
    var onVisibilityChange: (ContextFacet, Visibility) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(displayName(category))
                    .font(.headline)
                IdentityTierBadge(tier: ContextTierTable.tier(for: category))
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(facets) { facet in
                    BlueprintFacetRow(facet: facet, onVisibilityChange: onVisibilityChange)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
    }

    private func displayName(_ c: FacetCategory) -> String {
        switch c {
        case .current_focus: return "Current focus"
        case .faith_journey: return "Faith journey"
        default: return c.rawValue.capitalized
        }
    }
}

// MARK: - Facet row with edit-in-place visibility

struct BlueprintFacetRow: View {
    let facet: ContextFacet
    var onVisibilityChange: (ContextFacet, Visibility) -> Void

    @State private var showVisibilityEditor = false
    @State private var working: Visibility

    init(facet: ContextFacet, onVisibilityChange: @escaping (ContextFacet, Visibility) -> Void) {
        self.facet = facet
        self.onVisibilityChange = onVisibilityChange
        self._working = State(initialValue: facet.visibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(facet.label).font(.subheadline.weight(.semibold))
                    Text(facet.value.displaySummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        showVisibilityEditor.toggle()
                    }
                } label: {
                    VisibilityBadge(visibility: working)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visibility: \(badgeLabel(working)). Tap to edit.")
            }

            if showVisibilityEditor {
                VisibilityControl(
                    visibility: Binding(
                        get: { working },
                        set: { newValue in
                            working = newValue
                            onVisibilityChange(facet, newValue)
                            // TODO(gate: HUMAN-MACHINE) — store: persist the visibility change via ContextStoreService once service exists.
                        }
                    )
                )
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        )
    }

    private func badgeLabel(_ v: Visibility) -> String {
        switch v {
        case .privateVisibility: return "Private"
        case .friends:           return "Friends"
        case .groups:            return "Groups"
        case .church:            return "Church"
        case .publicVisibility:  return "Public"
        }
    }
}

// MARK: - Badges

struct VisibilityBadge: View {
    let visibility: Visibility

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.6))
    }

    private var label: String {
        switch visibility {
        case .privateVisibility: return "Private"
        case .friends:           return "Friends"
        case .groups:            return "Groups"
        case .church:            return "Church"
        case .publicVisibility:  return "Public"
        }
    }

    private var tint: Color {
        switch visibility {
        case .privateVisibility: return .secondary
        case .friends:           return .green
        case .groups, .church:   return .orange
        case .publicVisibility:  return .blue
        }
    }
}

struct IdentityTierBadge: View {
    let tier: EncryptionTier

    var body: some View {
        Text("TIER \(tier.rawValue)")
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 0.6)
            )
            .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        switch tier {
        case .p: return .pink
        case .c: return .blue
        case .s: return .purple
        }
    }

    private var accessibilityText: String {
        switch tier {
        case .p: return "Tier P, private, never server-readable"
        case .c: return "Tier C, confidential, server-readable for declared features"
        case .s: return "Tier S, server-readable sensitive"
        }
    }
}
