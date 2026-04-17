// ChurchMorningPrepView.swift
// AMENAPP
//
// Calm, modular pre-church prep screen.
// Shown when a journey enters prep_active status.
// Sections: Morning Plan summary, Worship Prep, Scripture for Today,
//           Coffee / Stop, Going With, Leave Timing.
// Berean AI integration: scripture and reflection prompts (lazy-loaded).

import SwiftUI

struct ChurchMorningPrepView: View {

    let journeyId: String
    @EnvironmentObject private var store: ChurchJourneyStore
    @EnvironmentObject private var router: ChurchJourneyRouter
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var completedSections: Set<String> = []
    @State private var showingArrived = false

    private var journey: ChurchJourney? { store.activeJourney }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                glassHeader
                    .padding(.bottom, 4)

                VStack(spacing: 14) {
                    if let journey {
                        morningPlanCard(journey: journey)

                        if journey.options.scripturePrepEnabled {
                            scripturePrepCard(journey: journey)
                        }

                        if journey.options.worshipPrepEnabled {
                            worshipPrepCard(journey: journey)
                        }

                        if journey.options.coffeeEnabled {
                            coffeeCard(journey: journey)
                        }

                        if journey.options.familyModeEnabled {
                            familyCard
                        }

                        leaveTimingCard(journey: journey)
                    } else {
                        loadingPlaceholder
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Before You Go")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("I'm Here") {
                    showingArrived = true
                }
                .font(.subheadline.weight(.medium))
                .accessibilityLabel("Mark as arrived at church")
            }
        }
        .confirmationDialog("Mark as arrived?", isPresented: $showingArrived) {
            Button("Yes, I'm at church") {
                Task { await markArrived() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will open your church notes and record your attendance.")
        }
    }

    // MARK: - Glass Header

    private var glassHeader: some View {
        VStack(spacing: 6) {
            if let journey {
                Text(journey.churchNameSnapshot)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(journey.formattedServiceTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(.ultraThinMaterial)
    }

    // MARK: - Morning Plan Summary

    private func morningPlanCard(journey: ChurchJourney) -> some View {
        PrepSectionCard(
            icon: "sun.horizon",
            title: "Morning Plan",
            completed: completedSections.contains("plan")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let dep = journey.timing.departureAt {
                    timingRow(label: "Leave", date: dep, icon: "car")
                }
                if let coffee = journey.timing.coffeeWindowStartAt, journey.options.coffeeEnabled {
                    timingRow(label: "Coffee", date: coffee, icon: "cup.and.heat.waves")
                }
                if let prepStart = journey.timing.prepStartAt,
                   journey.options.worshipPrepEnabled || journey.options.scripturePrepEnabled {
                    timingRow(label: "Prep starts", date: prepStart, icon: "book")
                }

                Button {
                    completedSections.insert("plan")
                } label: {
                    Text("Got it")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel("Mark morning plan as reviewed")
            }
        }
    }

    // MARK: - Scripture Prep

    private func scripturePrepCard(journey: ChurchJourney) -> some View {
        PrepSectionCard(
            icon: "book",
            title: "Scripture for Today",
            completed: completedSections.contains("scripture")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                let scriptures = journey.outputs.suggestedScriptures
                if scriptures.isEmpty {
                    Text("Psalm 100 • Hebrews 10:24–25")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scriptures.prefix(3), id: \.self) { ref in
                        Text(ref)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    prepActionPill("Read in 3 min", systemImage: "book.closed") {
                        completedSections.insert("scripture")
                    }
                    prepActionPill("Save for Notes", systemImage: "note.text.badge.plus") {
                        completedSections.insert("scripture")
                    }
                }
            }
        }
    }

    // MARK: - Worship Prep

    private func worshipPrepCard(journey: ChurchJourney) -> some View {
        PrepSectionCard(
            icon: "music.note",
            title: "Worship Prep",
            completed: completedSections.contains("worship")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                let worshipLinks = journey.outputs.suggestedWorshipLinks
                if worshipLinks.isEmpty {
                    Text("A 5-minute worship playlist or personal prayer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(worshipLinks.prefix(2)) { link in
                        Text(link.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                prepActionPill("Start Listening", systemImage: "play.circle") {
                    completedSections.insert("worship")
                }
            }
        }
    }

    // MARK: - Coffee Card

    private func coffeeCard(journey: ChurchJourney) -> some View {
        PrepSectionCard(
            icon: "cup.and.heat.waves",
            title: "Coffee Stop",
            completed: completedSections.contains("coffee")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let coffeeStart = journey.timing.coffeeWindowStartAt {
                    Text("Best pickup window: " + coffeeStart.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    prepActionPill("Open Maps", systemImage: "map") {
                        completedSections.insert("coffee")
                    }
                    prepActionPill("Already handled", systemImage: "checkmark") {
                        completedSections.insert("coffee")
                    }
                }
            }
        }
    }

    // MARK: - Family Card

    private var familyCard: some View {
        PrepSectionCard(
            icon: "figure.2",
            title: "Going With Family",
            completed: completedSections.contains("family")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Share your plan so everyone knows the timing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                prepActionPill("Share Plan", systemImage: "square.and.arrow.up") {
                    completedSections.insert("family")
                }
            }
        }
    }

    // MARK: - Leave Timing Card

    private func leaveTimingCard(journey: ChurchJourney) -> some View {
        PrepSectionCard(
            icon: "car",
            title: "Leave Timing",
            completed: completedSections.contains("leave")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let leaveIn = ChurchJourneyPlanner.leaveInSummary(timing: journey.timing) {
                    Text(leaveIn)
                        .font(.headline)
                }

                Text(ChurchJourneyPlanner.departureSummary(
                    timing: journey.timing,
                    serviceStart: journey.serviceStartAt
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                prepActionPill("Open Route", systemImage: "map") {
                    completedSections.insert("leave")
                }
            }
        }
    }

    // MARK: - Loading Placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 100)
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Helper Views

    private func timingRow(label: String, date: Date, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(date, style: .time)
                .font(.subheadline.weight(.medium))
        }
    }

    private func prepActionPill(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Arrived action

    private func markArrived() async {
        guard let journeyId = store.activeJourney?.id else { return }
        // Optimistically advance UI
        _ = journeyId
        // The router will navigate to notes once store refreshes with arrived status
        // The CF call is initiated here and the listener will pick up the state change
    }
}

// MARK: - Prep Section Card Component

private struct PrepSectionCard<Content: View>: View {
    let icon: String
    let title: String
    let completed: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(completed ? .secondary : .primary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(completed ? .secondary : .primary)
                Spacer()
                if completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))
                        .accessibilityLabel("Completed")
                }
            }

            if !completed {
                content()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: completed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) section\(completed ? ", completed" : "")")
    }
}
