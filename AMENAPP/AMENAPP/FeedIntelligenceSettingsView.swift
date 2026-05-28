import SwiftUI

struct FeedIntelligenceSettingsView: View {
    @StateObject private var modeManager = AmenFeedModeManager.shared
    @State private var summary: FeedIntelligenceSummary? = nil
    @State private var isLoading = true
    @State private var isResetting = false
    @State private var resetScope: FeedResetScope? = nil
    @State private var showResetConfirm = false

    var body: some View {
        List {
            if isLoading {
                Section { ProgressView().tint(.secondary) }
            } else {
                activeSignalsSection
                feedModesSection
                topicControlsSection
                feedHealthSection
                resetSection
                transparencySection
            }
        }
        .navigationTitle("Feed Intelligence")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadSummary() }
        .confirmationDialog("Reset feed preferences?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset temporary preferences") { performReset(.temporary) }
            Button("Reset emotional preferences") { performReset(.emotional) }
            Button("Reset creator preferences") { performReset(.creator) }
            Button("Reset all feed intelligence", role: .destructive) { performReset(.all) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var activeSignalsSection: some View {
        Section("Active Feed Directions") {
            if let signals = summary?.activeSignals, !signals.isEmpty {
                ForEach(signals) { signal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal.interpretedSummary)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            Text(signal.duration.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let expires = signal.expiresAt {
                                Text("· Expires \(expires.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("No active feed directions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedModesSection: some View {
        Section("Feed Modes") {
            ForEach(AmenFeedMode.allCases) { mode in
                HStack(spacing: 12) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName).font(.subheadline.weight(.medium))
                        Text(mode.description).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { modeManager.activeModes.contains(mode) },
                        set: { _ in modeManager.toggle(mode) }
                    ))
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var topicControlsSection: some View {
        Section("Topic Signals") {
            if let boosted = summary?.boostedTopics, !boosted.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boosted").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    AMENFlowLayout(spacing: 6) {
                        ForEach(Array(boosted.keys.sorted()), id: \.self) { topic in
                            topicChip(topic, isBoost: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let suppressed = summary?.suppressedTopics, !suppressed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reduced").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    AMENFlowLayout(spacing: 6) {
                        ForEach(Array(suppressed.keys.sorted()), id: \.self) { topic in
                            topicChip(topic, isBoost: false)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if summary?.boostedTopics.isEmpty == true && summary?.suppressedTopics.isEmpty == true {
                Text("No topic signals yet.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var feedHealthSection: some View {
        Section("Feed Health") {
            FeedHealthDashboardView()
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise").foregroundStyle(.red)
                    Text(isResetting ? "Resetting…" : "Reset feed preferences")
                }
            }
            .disabled(isResetting)
        }
    }

    private var transparencySection: some View {
        Section {
            Text("Amen uses your direct requests, saves, hides, follows, and viewing patterns to improve recommendations. You can review or reset these signals anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func topicChip(_ topic: String, isBoost: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isBoost ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .bold))
            Text(topic).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isBoost ? .primary : .secondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func loadSummary() async {
        isLoading = true
        summary = try? await AmenFeedDirectionService.shared.getFeedIntelligenceSummary()
        isLoading = false
    }

    private func performReset(_ scope: FeedResetScope) {
        isResetting = true
        FeedDirectionAnalytics.feedReset(scope: scope.rawValue)
        Task {
            try? await AmenFeedDirectionService.shared.resetFeedPreference(scope: scope)
            await loadSummary()
            isResetting = false
        }
    }
}
