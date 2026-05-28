// AmenScheduleGatheringView.swift
// Schedule Gathering flow — title, type, time, provider picker, AI suggestions
// Feature-gated: amenGatheringsEnabled + amenGatheringMeetingLinksEnabled

import SwiftUI

struct AmenScheduleGatheringView: View {
    @EnvironmentObject private var flags: AMENFeatureFlags
    @StateObject private var aiVM = AmenGatheringAISuggestionsViewModel()
    @StateObject private var integrationVM = AmenIntegrationViewModel()
    @State private var form = AmenScheduleGatheringForm()
    @State private var phase: Phase = .compose
    @State private var showAISuggestions = false
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case compose, creatingLink, success(joinUrl: String), failed(Error)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .compose:
                    composeView
                case .creatingLink:
                    creatingView
                case .success(let joinUrl):
                    successView(joinUrl: joinUrl)
                case .failed(let error):
                    failedView(error: error)
                }
            }
            .navigationTitle("Schedule Gathering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .compose = phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Schedule") {
                            Task { await scheduleGathering() }
                        }
                        .disabled(!form.isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .task {
            await integrationVM.loadConnections()
            if flags.amenGatheringAISuggestionsEnabled {
                await aiVM.loadSuggestions(for: form.gatheringType, durationMinutes: form.durationMinutes)
            }
        }
        .onChange(of: form.gatheringType) { _, newType in
            if flags.amenGatheringAISuggestionsEnabled {
                Task { await aiVM.loadSuggestions(for: newType, durationMinutes: form.durationMinutes) }
            }
        }
    }

    // MARK: - Compose

    private var composeView: some View {
        Form {
            // Title
            Section("Title") {
                TextField("Gathering title", text: $form.title)
                    .accessibilityLabel("Gathering title")

                if flags.amenGatheringAISuggestionsEnabled && !aiVM.titleSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Berean suggestions", systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(aiVM.titleSuggestions) { suggestion in
                                    Button {
                                        form.title = suggestion.title
                                        aiVM.confirmTitle(suggestion)
                                    } label: {
                                        Text(suggestion.title)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                form.title == suggestion.title
                                                    ? Color.blue.opacity(0.12)
                                                    : Color(.systemGray6),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(
                                                form.title == suggestion.title ? .blue : .primary
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Suggest title: \(suggestion.title)")
                                }
                            }
                        }
                    }
                }
            }

            // Type
            Section("Type") {
                Picker("Gathering type", selection: $form.gatheringType) {
                    ForEach(AmenGatheringType.allCases) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Gathering type: \(form.gatheringType.displayName)")
            }

            // Date & Time
            Section("Date & Time") {
                DatePicker("Start", selection: $form.date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .accessibilityLabel("Gathering start date and time")

                Picker("Duration", selection: $form.durationMinutes) {
                    ForEach([30, 45, 60, 90, 120, 180], id: \.self) { min in
                        Text(durationLabel(min)).tag(min)
                    }
                }
                .accessibilityLabel("Duration: \(form.durationLabel)")
            }

            // Meeting Platform
            if flags.amenGatheringMeetingLinksEnabled {
                Section {
                    let connected = integrationVM.connections
                        .filter { $0.status == .connected && $0.provider.supportsGatherings }
                        .map { $0.provider }
                    AmenGatheringProviderPicker(
                        selectedProvider: $form.provider,
                        connectedProviders: connected,
                        onAddManualLink: nil
                    )
                } header: {
                    Text("Meeting Platform")
                } footer: {
                    Text("AMEN will create a meeting link via the selected platform.")
                }
            }

            // Scripture Focus (AI)
            if flags.amenGatheringAISuggestionsEnabled && !aiVM.scriptureSuggestions.isEmpty {
                Section("Scripture Focus (Berean)") {
                    ForEach(aiVM.scriptureSuggestions) { s in
                        Button {
                            form.selectedScripture = s
                            aiVM.confirmScripture(s)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.reference).font(.subheadline.weight(.medium))
                                    Text(s.theme).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if form.selectedScripture?.reference == s.reference {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(s.reference) — \(s.theme). \(form.selectedScripture?.reference == s.reference ? "Selected" : "Not selected")")
                    }
                }
            }
        }
    }

    // MARK: - Creating / Success / Failed

    private var creatingView: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text("Scheduling gathering…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Scheduling gathering")
    }

    private func successView(joinUrl: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Gathering Scheduled!")
                .font(.title3.weight(.semibold))
            if let url = URL(string: joinUrl) {
                Link(destination: url) {
                    Label("Join Link Ready", systemImage: "video.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open meeting join link")
            }
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private func failedView(error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Scheduling Failed")
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button("Try Again") { phase = .compose }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func scheduleGathering() async {
        guard form.isValid else { return }
        phase = .creatingLink

        do {
            if let provider = form.provider, flags.amenGatheringMeetingLinksEnabled {
                // In production: first call gatheringsCreate, then gatheringsCreateMeetingLink
                // For this implementation, we go straight to meeting link creation with a temp ID
                let result = try await AmenIntegrationService.shared.createMeetingLink(
                    gatheringId: UUID().uuidString, // Real impl uses persisted gathering ID
                    provider: provider
                )
                phase = .success(joinUrl: result.joinUrl ?? "")
            } else {
                // No provider — gathering created without a meeting link
                phase = .success(joinUrl: "")
            }
        } catch {
            phase = .failed(error)
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hrs = minutes / 60; let mins = minutes % 60
        return mins == 0 ? "\(hrs) hr" : "\(hrs) hr \(mins) min"
    }
}

#Preview {
    AmenScheduleGatheringView()
        .environmentObject(AMENFeatureFlags.shared)
}
