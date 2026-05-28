// AmenGatheringAISuggestionsView.swift
// Berean AI suggestions panel for gatherings — titles, agenda, scripture
// Feature-gated: amenGatheringAISuggestionsEnabled

import SwiftUI

struct AmenGatheringAISuggestionsView: View {
    @ObservedObject var vm: AmenGatheringAISuggestionsViewModel
    let gatheringType: AmenGatheringType

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                bereanHeader

                if vm.isLoading {
                    loadingSection
                } else {
                    if !vm.titleSuggestions.isEmpty {
                        titleSection
                    }
                    if !vm.scriptureSuggestions.isEmpty {
                        scriptureSection
                    }
                    if !vm.agendaItems.isEmpty {
                        agendaSection
                    }
                }

                aiDisclosure
            }
            .padding()
        }
        .navigationTitle("Berean Suggestions")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var bereanHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Berean AI")
                    .font(.headline)
                Text("Suggestions for your \(gatheringType.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean AI — Suggestions for your \(gatheringType.displayName)")
    }

    // MARK: - Loading

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing suggestions…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityLabel("Loading Berean suggestions")
    }

    // MARK: - Titles

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Suggested Titles", icon: "text.cursor")
            ForEach(vm.titleSuggestions) { suggestion in
                AmenGatheringAgendaSuggestionCard(
                    title: suggestion.title,
                    subtitle: suggestion.rationale,
                    isSelected: vm.selectedTitle?.title == suggestion.title,
                    onTap: { vm.confirmTitle(suggestion) }
                )
            }
        }
    }

    // MARK: - Scripture

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Scripture Focus", icon: "book.fill")
            ForEach(vm.scriptureSuggestions) { s in
                AmenGatheringAgendaSuggestionCard(
                    title: s.reference,
                    subtitle: "\(s.theme) — \(s.preview)",
                    isSelected: vm.confirmedScripture?.reference == s.reference,
                    onTap: { vm.confirmScripture(s) }
                )
            }
        }
    }

    // MARK: - Agenda

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Suggested Agenda", icon: "list.bullet")
                Spacer()
                Button("Use This Agenda") {
                    vm.confirmAgenda(vm.agendaItems)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .accessibilityLabel("Use Berean suggested agenda")
            }
            ForEach(vm.agendaItems) { item in
                HStack(spacing: 12) {
                    Text("\(item.durationMinutes)m")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.activity)
                            .font(.subheadline)
                        if let ref = item.scriptureReference {
                            Text(ref)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.durationMinutes) minutes — \(item.activity)\(item.scriptureReference.map { " — \($0)" } ?? "")")
            }
        }
    }

    // MARK: - Disclosure

    private var aiDisclosure: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Suggestions are generated from Berean's knowledge of Scripture and ministry practices — not from your gathering history. You control what is saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI disclosure: Suggestions are from Berean's Scripture knowledge. You control what is saved.")
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }
}
