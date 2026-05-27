// AmenStartPrayerSessionView.swift
// Start an immediate prayer session — creates instant meeting link
// Feature-gated: amenGatheringsEnabled

import SwiftUI

struct AmenStartPrayerSessionView: View {
    @EnvironmentObject private var flags: AMENFeatureFlags
    @StateObject private var integrationVM = AmenIntegrationViewModel()
    @State private var selectedProvider: AmenIntegrationProvider?
    @State private var phase: Phase = .ready
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case ready, creating, success(joinUrl: String), failed(Error)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    readyView
                case .creating:
                    creatingView
                case .success(let joinUrl):
                    successView(joinUrl: joinUrl)
                case .failed(let error):
                    failedView(error: error)
                }
            }
            .navigationTitle("Start Prayer Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await integrationVM.loadConnections() }
    }

    // MARK: - Ready

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)
                    Text("Start a Prayer Session")
                        .font(.title3.weight(.semibold))
                    Text("AMEN will create an instant meeting and notify your Space members.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 32)

                // Provider selection
                if flags.amenGatheringMeetingLinksEnabled {
                    let connected = integrationVM.connections
                        .filter { $0.status == .connected && $0.provider.supportsGatherings }
                        .map { $0.provider }

                    VStack(alignment: .leading, spacing: 12) {
                        AmenGatheringProviderPicker(
                            selectedProvider: $selectedProvider,
                            connectedProviders: connected,
                            onAddManualLink: nil
                        )
                    }
                    .padding(.horizontal)
                }

                // Start button
                Button {
                    Task { await startSession() }
                } label: {
                    Label("Start Prayer Session", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .padding(.horizontal)
                .accessibilityLabel("Start Prayer Session now")

                // Privacy note
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Prayer sessions are private. Only invited Space members will receive the link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Prayer sessions are private. Only invited Space members receive the link.")
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var creatingView: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text("Creating prayer session…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Creating prayer session")
    }

    private func successView(joinUrl: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Prayer Session Ready")
                .font(.title3.weight(.semibold))

            Text("Your Space members have been notified.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let url = URL(string: joinUrl), !joinUrl.isEmpty {
                VStack(spacing: 12) {
                    Link(destination: url) {
                        Label("Join Now", systemImage: "video.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .accessibilityLabel("Join prayer session")

                    Button {
                        UIPasteboard.general.string = joinUrl
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Copy meeting link to clipboard")
                }
                .padding(.horizontal)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
        .padding()
    }

    private func failedView(error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Session Failed")
                .font(.title3.weight(.semibold))
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button("Try Again") { phase = .ready }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func startSession() async {
        guard let provider = selectedProvider, flags.amenGatheringMeetingLinksEnabled else {
            // No provider — succeed without link
            phase = .success(joinUrl: "")
            return
        }
        phase = .creating
        do {
            let result = try await AmenIntegrationService.shared.createMeetingLink(
                gatheringId: UUID().uuidString,
                provider: provider
            )
            phase = .success(joinUrl: result.joinUrl ?? "")
        } catch {
            phase = .failed(error)
        }
    }
}

#Preview {
    AmenStartPrayerSessionView()
        .environmentObject(AMENFeatureFlags.shared)
}
