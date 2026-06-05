// BroadcastComposerView.swift — AMEN IntegrationOS
// SwiftUI broadcast composer with channel status checking.

import SwiftUI

@MainActor
final class BroadcastComposerViewModel: ObservableObject {
    @Published var selectedChannel: BroadcastChannel = .push
    @Published var subject = ""
    @Published var body = ""
    @Published var scheduledAt: Date?
    @Published var scheduleEnabled = false
    @Published var isSending = false
    @Published var channelStatuses: [MessagingChannelAdapter.ChannelStatus] = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let orgId: String
    private let service = BroadcastService.shared
    private let adapter = MessagingChannelAdapter.shared

    init(orgId: String) { self.orgId = orgId }

    func loadChannelStatuses() async {
        channelStatuses = await adapter.checkAllChannels(orgId: orgId)
    }

    func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await service.send(
                orgId: orgId,
                spaceId: nil,
                channel: selectedChannel,
                subject: subject.isEmpty ? nil : subject,
                body: body,
                scheduledAt: scheduleEnabled ? scheduledAt : nil
            )
            successMessage = "Broadcast \(scheduleEnabled ? "scheduled" : "sent")!"
            body = ""
            subject = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func statusFor(_ channel: BroadcastChannel) -> MessagingChannelAdapter.ChannelStatus? {
        channelStatuses.first { $0.channel == channel }
    }
}

struct BroadcastComposerView: View {
    @StateObject private var viewModel: BroadcastComposerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(orgId: String) {
        _viewModel = StateObject(wrappedValue: BroadcastComposerViewModel(orgId: orgId))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel") {
                    Picker("Channel", selection: $viewModel.selectedChannel) {
                        ForEach(BroadcastChannel.allCases, id: \.self) { ch in
                            Label(ch.displayName, systemImage: ch.icon).tag(ch)
                        }
                    }
                    .pickerStyle(.menu)

                    if let status = viewModel.statusFor(viewModel.selectedChannel) {
                        HStack {
                            Circle()
                                .fill(status.isAvailable ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(status.isAvailable ? "Available" : (status.errorMessage ?? "Unavailable"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let count = status.subscriberCount {
                                Spacer()
                                Text("\(count) recipients")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if viewModel.selectedChannel == .email {
                    Section("Subject") {
                        TextField("Email subject", text: $viewModel.subject)
                    }
                }

                Section("Message") {
                    TextEditor(text: $viewModel.body)
                        .frame(minHeight: 120)
                }

                Section("Schedule") {
                    Toggle("Schedule for later", isOn: $viewModel.scheduleEnabled)
                    if viewModel.scheduleEnabled {
                        DatePicker(
                            "Send at",
                            selection: Binding(
                                get: { viewModel.scheduledAt ?? Date().addingTimeInterval(3600) },
                                set: { viewModel.scheduledAt = $0 }
                            ),
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let success = viewModel.successMessage {
                    Section {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        Task { await viewModel.send() }
                    }
                    .disabled(viewModel.body.isEmpty || viewModel.isSending)
                    .fontWeight(.semibold)
                }
            }
            .task { await viewModel.loadChannelStatuses() }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }
}
