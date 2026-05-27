// AmenGatheringFollowUpSuggestionView.swift
// Post-gathering follow-up — host selects actions, confirms AI suggestions, optionally shares
// Feature-gated: amenGatheringFollowUpsEnabled

import SwiftUI

struct AmenGatheringFollowUpSuggestionView: View {
    let gatheringId: String
    let gatheringTitle: String
    let gatheringType: AmenGatheringType
    @EnvironmentObject private var flags: AMENFeatureFlags
    @StateObject private var aiVM = AmenGatheringAISuggestionsViewModel()
    @State private var scripture = ""
    @State private var actionItems: [String] = [""]
    @State private var prayerPoints: [String] = [""]
    @State private var shareToSpace = false
    @State private var phase: Phase = .compose
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case compose, submitting, success, failed(Error) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .compose: composeView
                case .submitting: submittingView
                case .success: successView
                case .failed(let error): failedView(error)
                }
            }
            .navigationTitle("Follow Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                if case .compose = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await saveFollowUp() } }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .task {
            if flags.amenGatheringAISuggestionsEnabled {
                await aiVM.loadSuggestions(for: gatheringType)
            }
        }
    }

    // MARK: - Compose

    private var composeView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gatheringTitle)
                        .font(.headline)
                    Text("Complete your follow-up for this gathering.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Scripture
            Section("Scripture (optional)") {
                TextField("e.g., Philippians 4:6-7", text: $scripture)
                    .accessibilityLabel("Scripture reference for this gathering")

                if flags.amenGatheringAISuggestionsEnabled && !aiVM.scriptureSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Berean suggestions", systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(aiVM.scriptureSuggestions.prefix(2)) { s in
                            Button {
                                scripture = s.reference
                                aiVM.confirmScripture(s)
                            } label: {
                                HStack {
                                    Text(s.reference).font(.caption.weight(.medium))
                                    Text("— \(s.theme)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Suggest scripture: \(s.reference) — \(s.theme)")
                        }
                    }
                }
            }

            // Action Items
            Section {
                ForEach(actionItems.indices, id: \.self) { i in
                    TextField("Action item…", text: $actionItems[i])
                        .accessibilityLabel("Action item \(i + 1)")
                }
                Button {
                    actionItems.append("")
                } label: {
                    Label("Add action item", systemImage: "plus.circle")
                }
                .accessibilityLabel("Add another action item")
            } header: {
                Text("Action Items")
            } footer: {
                Text("What does your group commit to doing this week?")
            }

            // Prayer Points
            Section {
                ForEach(prayerPoints.indices, id: \.self) { i in
                    TextField("Prayer point…", text: $prayerPoints[i])
                        .accessibilityLabel("Prayer point \(i + 1)")
                }
                Button {
                    prayerPoints.append("")
                } label: {
                    Label("Add prayer point", systemImage: "plus.circle")
                }
                .accessibilityLabel("Add another prayer point")
            } header: {
                Text("Prayer Points")
            } footer: {
                Text("Specific prayer requests to continue carrying as a group.")
            }

            // Share
            Section {
                Toggle("Share follow-up to my Space", isOn: $shareToSpace)
                    .accessibilityLabel("Share follow-up to Space: \(shareToSpace ? "on" : "off")")
            } footer: {
                Text("Only content you choose to share will be posted. Prayer points are private by default.")
            }
        }
    }

    private var submittingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Saving follow-up…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Saving follow-up")
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Follow-Up Saved")
                .font(.title3.weight(.semibold))
            Text("Your gathering follow-up has been recorded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func failedView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Save Failed")
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retry") { phase = .compose }.buttonStyle(.borderedProminent)
                Button("Skip") { dismiss() }.buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Save

    private func saveFollowUp() async {
        phase = .submitting
        let service = AmenIntegrationService.shared
        let cleanItems = actionItems.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanPrayer = prayerPoints.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        do {
            _ = try await Functions.functions().httpsCallable("gatheringsCompleteFollowUp").call([
                "gatheringId": gatheringId,
                "userConfirmed": true,
                "isAIGenerated": false,
                "scripture": scripture.isEmpty ? NSNull() : scripture,
                "actionItems": cleanItems.isEmpty ? NSNull() : cleanItems,
                "prayerPoints": cleanPrayer.isEmpty ? NSNull() : cleanPrayer,
            ])
            phase = .success
        } catch {
            phase = .failed(error)
        }
    }
}

import FirebaseFunctions

#Preview {
    AmenGatheringFollowUpSuggestionView(
        gatheringId: "preview",
        gatheringTitle: "Sunday Small Group",
        gatheringType: .smallGroup
    )
    .environmentObject(AMENFeatureFlags.shared)
}
