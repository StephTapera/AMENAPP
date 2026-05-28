// AmenGatheringProviderPicker.swift
// Let users pick Zoom or Teams for a gathering meeting link
// Falls back gracefully when no provider is connected

import SwiftUI

struct AmenGatheringProviderPicker: View {
    @Binding var selectedProvider: AmenIntegrationProvider?
    let connectedProviders: [AmenIntegrationProvider]
    let onAddManualLink: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meeting Platform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if connectedProviders.isEmpty {
                emptyState
            } else {
                providerOptions
            }
        }
    }

    @ViewBuilder
    private var providerOptions: some View {
        VStack(spacing: 8) {
            ForEach(connectedProviders) { provider in
                providerRow(provider)
            }

            Button {
                selectedProvider = nil
                onAddManualLink?()
            } label: {
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text("Add meeting link manually")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add meeting link manually")
        }
    }

    private func providerRow(_ provider: AmenIntegrationProvider) -> some View {
        Button {
            selectedProvider = selectedProvider == provider ? nil : provider
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.systemIconFallback)
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(providerSubtitle(provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedProvider == provider ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedProvider == provider ? .blue : .secondary)
                    .font(.system(size: 20))
            }
            .padding(12)
            .background(
                selectedProvider == provider
                    ? Color.blue.opacity(0.08)
                    : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedProvider == provider ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.displayName). \(selectedProvider == provider ? "Selected" : "Not selected")")
        .accessibilityAddTraits(selectedProvider == provider ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("No meeting platforms connected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink(destination: AmenIntegrationConnectionsView()) {
                Text("Connect Zoom or Microsoft 365")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func providerSubtitle(_ provider: AmenIntegrationProvider) -> String {
        switch provider {
        case .microsoft: return "Teams meeting via Outlook"
        case .zoom: return "Zoom meeting room"
        case .slack: return "Slack notification"
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: 24) {
                AmenGatheringProviderPicker(
                    selectedProvider: .constant(.zoom),
                    connectedProviders: [.microsoft, .zoom],
                    onAddManualLink: nil
                )
                .padding()

                AmenGatheringProviderPicker(
                    selectedProvider: .constant(nil),
                    connectedProviders: [],
                    onAddManualLink: nil
                )
                .padding()
            }
        }
    }
}
