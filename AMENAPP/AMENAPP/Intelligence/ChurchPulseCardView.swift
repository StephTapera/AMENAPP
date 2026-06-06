// ChurchPulseCardView.swift
// AMENAPP — Church Pulse Card
//
// Displays church health as a Liquid Glass card.
//
// Design rules (enforced here):
//   - NO raw pulse score number displayed — signals only, in plain language
//   - NO spectacle counters ("47 members praying", "X attending")
//   - Only show actions backed by real data (card.actions is pre-filtered server-side)
//   - "Why this church?" disclosure shows rankReasons
//   - Verified badge shown when backingEntity.verified == true

import SwiftUI

// MARK: - ChurchPulseCardView

struct ChurchPulseCardView: View {
    let card: IntelligenceCard
    let onAction: (CardAction) -> Void

    @State private var showWhySheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            signalsSection
            if !card.actions.isEmpty {
                actionsSection
            }
            footerRow
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardBorder)
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .sheet(isPresented: $showWhySheet) {
            ChurchPulseWhySheet(rankReasons: card.rankReasons, cardTitle: card.title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Church pulse card: \(card.title)")
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.systemGray6)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if card.backingEntity.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified church")
                    }
                }

                Text(tierLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Signals

    /// Shows the plain-language signals from server — no counts, no spectacle.
    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(card.summary.prefix(3), id: \.self) { signal in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    Text(signal)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityLabel("Church activity: \(card.summary.joined(separator: ", "))")
    }

    // MARK: - Actions

    private var actionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(card.actions) { action in
                    Button {
                        onAction(action)
                    } label: {
                        Text(action.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            Spacer()
            Button {
                showWhySheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Why this church?")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why is this church shown? Tap to learn more.")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Background / Border

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.52))
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }

    // MARK: - Helpers

    private var tierLabel: String {
        switch card.tier {
        case .local:     return "Your local church"
        case .community: return "Nearby church"
        default:         return "Church"
        }
    }
}

// MARK: - ChurchPulseWhySheet

private struct ChurchPulseWhySheet: View {
    let rankReasons: [String]
    let cardTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rankReasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Why you're seeing this church")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Church activity is computed from real events, prayer requests, and teachings posted in the app. No estimates or fabricated data are used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About church pulse")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let formation = IntelligenceFormation(
        finite: true,
        spectacleCounters: false,
        lamentFrame: nil,
        loopParentId: nil
    )
    let sampleCard = IntelligenceCard(
        id: "church_pulse_preview",
        tier: .local,
        title: "Grace Community Church — What's Happening",
        summary: [
            "4 upcoming events",
            "Active prayer requests",
            "Volunteer opportunities available",
        ],
        backingEntity: BackingEntity(kind: .church, id: "preview_church", verified: true),
        truthLevel: .churchConfirmed,
        matchScore: nil,
        matchReasons: nil,
        actions: [
            CardAction(rung: .showUp,  label: "View church",         handler: "action.openChurch", target: "preview_church"),
            CardAction(rung: .showUp,  label: "See upcoming events",  handler: "action.openEvent",  target: "preview_church"),
            CardAction(rung: .pray,    label: "See prayer requests",  handler: "action.openPrayer", target: "preview_church"),
        ],
        rankScore: 80,
        rankReasons: ["Your church", "Active this week", "Community is praying"],
        geo: nil,
        formation: formation,
        source: nil,
        createdAt: Date().timeIntervalSince1970,
        expiresAt: Date().addingTimeInterval(6 * 3600).timeIntervalSince1970
    )

    ScrollView {
        ChurchPulseCardView(card: sampleCard) { action in
            print("Tapped action: \(action.label)")
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
#endif
