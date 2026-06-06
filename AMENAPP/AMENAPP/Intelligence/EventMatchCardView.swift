// EventMatchCardView.swift
// AMENAPP — Living Intelligence — Event Match Card
// Displays a matched event IntelligenceCard.
// Rules:
//   - matchReasons shown as chips, no spectacle counters
//   - "Friends are attending" reason allowed, never a count
//   - RSVP button calls action.rsvpEvent handler
//   - "Why this event?" disclosure shows rankReasons
//   - Liquid Glass material, no plain white card

import SwiftUI

// MARK: - Model

struct EventMatchCard: Identifiable {
    let id: String
    let title: String
    let churchName: String?
    let summary: [String]
    let matchReasons: [String]
    let rankReasons: [String]
    let eventId: String        // backingEntity.id
    let urgencyHigh: Bool

    // Formation
    let expiresAt: Date
}

// MARK: - Action Handler Protocol

protocol EventMatchCardDelegate: AnyObject {
    func rsvpEvent(eventId: String)
    func prayForEvent(eventId: String)
    func openEvent(eventId: String)
}

// MARK: - Main View

struct EventMatchCardView: View {
    let card: EventMatchCard
    weak var delegate: (any EventMatchCardDelegate)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingWhySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            cardHeader

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 16)

            // Summary bullets
            VStack(alignment: .leading, spacing: 6) {
                ForEach(card.summary.prefix(3), id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#A78843"))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Match reason chips (no counts)
            if !card.matchReasons.isEmpty {
                matchReasonRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 16)

            // Actions
            actionRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // "Why this event?" disclosure
            Button {
                showingWhySheet = true
            } label: {
                Label("Why this event?", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .accessibilityLabel("Why is this event recommended?")
            .accessibilityHint("Opens explanation of ranking")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $showingWhySheet) {
            WhyThisEventSheet(rankReasons: card.rankReasons, eventTitle: card.title)
                .presentationDetents([.medium])
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                if let church = card.churchName {
                    Text(church)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color(hex: "#A78843"))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Match Reason Chips

    private var matchReasonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(card.matchReasons.prefix(4), id: \.self) { reason in
                    Text(reason)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .accessibilityLabel("Match reason: \(reason)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Why this matched for you")
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            // Primary: RSVP
            Button {
                delegate?.rsvpEvent(eventId: card.eventId)
            } label: {
                Label("RSVP", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#A78843"))
                    )
            }
            .accessibilityLabel("RSVP to \(card.title)")
            .accessibilityHint("Marks you as attending this event")

            // Secondary: Pray
            Button {
                delegate?.prayForEvent(eventId: card.eventId)
            } label: {
                Label("Pray", systemImage: "hands.sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
            .accessibilityLabel("Pray for this event")

            Spacer()
        }
    }
}

// MARK: - Why Sheet

private struct WhyThisEventSheet: View {
    let rankReasons: [String]
    let eventTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rankReasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color(hex: "#A78843"))
                                .accessibilityHidden(true)
                            Text(reason)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Why this event was recommended")
                        .textCase(nil)
                        .font(.subheadline.weight(.medium))
                }
            }
            .navigationTitle("Why \"\(eventTitle)\"?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
private final class PreviewDelegate: EventMatchCardDelegate {
    func rsvpEvent(eventId: String) {}
    func prayForEvent(eventId: String) {}
    func openEvent(eventId: String) {}
}

#Preview {
    EventMatchCardView(
        card: EventMatchCard(
            id: "preview_1",
            title: "Sunday Morning Worship",
            churchName: "Cornerstone Church",
            summary: [
                "From a church you follow",
                "Timely for this season",
            ],
            matchReasons: ["From a church you follow", "Near you", "Friends are attending"],
            rankReasons: ["Match score: 75", "From a church you follow", "Near you"],
            eventId: "event_abc123",
            urgencyHigh: false,
            expiresAt: Date().addingTimeInterval(86400 * 7)
        ),
        delegate: PreviewDelegate()
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
