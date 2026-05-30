// AmenGatheringHostConsoleView.swift
// AMENAPP — Host / Admin Console
//
// Edit, cancel, duplicate, manage access passes,
// view RSVPs, send updates, approve/deny requests.

import SwiftUI

struct AmenGatheringHostConsoleView: View {
    let gathering: AmenGathering

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: HostConsoleViewModel
    @State private var showCancelConfirm = false
    @State private var showSendUpdate = false
    @State private var showGuestList = false
    @State private var showAccessPasses = false
    @State private var showShareSheet = false
    @State private var copiedLink = false

    init(gathering: AmenGathering) {
        self.gathering = gathering
        _vm = StateObject(wrappedValue: HostConsoleViewModel(gathering: gathering))
    }

    var body: some View {
        NavigationStack {
            List {
                statsSection
                accessSection
                attendeeSection
                communicationSection
                dangerSection
            }
            .navigationTitle("Host Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Cancel Gathering?", isPresented: $showCancelConfirm) {
                Button("Cancel Gathering", role: .destructive) { vm.cancelGathering() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("RSVPed attendees will be notified. This cannot be undone.")
            }
            .sheet(isPresented: $showSendUpdate) {
                SendGatheringUpdateSheet(gatheringId: gathering.gatheringId)
            }
            .sheet(isPresented: $showGuestList) {
                AmenGatheringGuestListView(gathering: gathering)
            }
            .sheet(isPresented: $showShareSheet) {
                AmenGatheringShareSheet(gathering: gathering)
            }
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section("Attendance") {
            statsRow(label: "Going", count: gathering.counts.going, icon: "checkmark.circle.fill", color: .green)
            statsRow(label: "Maybe", count: gathering.counts.maybe, icon: "questionmark.circle", color: .orange)
            statsRow(label: "Can't Attend", count: gathering.counts.declined, icon: "xmark.circle", color: .red)
            if gathering.waitlistEnabled {
                statsRow(label: "Waitlisted", count: gathering.counts.waitlisted, icon: "clock.circle", color: .blue)
            }
            if gathering.access.requiresApproval {
                statsRow(label: "Pending Requests", count: gathering.counts.pendingRequests, icon: "hourglass", color: .purple)
            }
            statsRow(label: "Checked In", count: gathering.counts.checkedIn, icon: "qrcode.viewfinder", color: AmenTheme.Colors.amenGold)

            Button {
                showGuestList = true
            } label: {
                Label("View Full Guest List", systemImage: "list.bullet")
            }
        }
    }

    private func statsRow(label: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(label)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(count > 0 ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)
        }
        .accessibilityLabel("\(label): \(count)")
    }

    private var accessSection: some View {
        Section("Access & Invites") {
            Button {
                showShareSheet = true
            } label: {
                Label("Share Link & QR Code", systemImage: "qrcode")
            }

            if let passId = gathering.access.defaultAccessPassId {
                Button {
                    vm.rotateToken(passId: passId)
                } label: {
                    Label("Rotate Invite Token", systemImage: "arrow.clockwise.circle")
                }
                .disabled(vm.isPerformingAction)

                Button {
                    vm.pausePass(passId: passId)
                } label: {
                    Label("Pause Invite Link", systemImage: "pause.circle")
                }
                .disabled(vm.isPerformingAction)

                Button(role: .destructive) {
                    vm.revokePass(passId: passId)
                } label: {
                    Label("Revoke Invite", systemImage: "xmark.circle")
                }
                .disabled(vm.isPerformingAction)
            }
        }
    }

    private var attendeeSection: some View {
        Section("Manage Attendees") {
            Button {
                showGuestList = true
            } label: {
                Label("Approve / Deny Requests (\(gathering.counts.pendingRequests))",
                      systemImage: "person.badge.key")
            }

            Button {
                // Close RSVPs — show confirmation
            } label: {
                Label("Close RSVPs", systemImage: "lock.circle")
            }
        }
    }

    private var communicationSection: some View {
        Section("Communicate") {
            Button {
                showSendUpdate = true
            } label: {
                Label("Send Update to Attendees", systemImage: "bell")
            }

            Button {
                // Duplicate gathering
                vm.duplicateGathering()
            } label: {
                Label("Duplicate Gathering", systemImage: "doc.on.doc")
            }
            .disabled(vm.isPerformingAction)
        }
    }

    private var dangerSection: some View {
        Section {
            if gathering.status != .cancelled {
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Label("Cancel Gathering", systemImage: "xmark.circle")
                }
            }
        }
    }
}

// MARK: - Send Update Sheet

private struct SendGatheringUpdateSheet: View {
    let gatheringId: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Update Title") {
                    TextField("e.g. Location Changed", text: $title)
                        .accessibilityLabel("Update title")
                }
                Section("Message") {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Update message")
                }
                Section {
                    Text("This will send a notification to all RSVPed attendees.")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .navigationTitle("Send Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") { sendUpdate() }
                        .disabled(title.isEmpty || messageBody.isEmpty || isSending)
                        .fontWeight(.semibold)
                }
            }
            .alert("Update Sent", isPresented: $sent) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func sendUpdate() {
        isSending = true
        Task {
            let input = AmenGatheringSendUpdateInput(
                gatheringId: gatheringId,
                title: title,
                body: messageBody
            )
            _ = try? await AmenGatheringService.shared.sendGatheringUpdate(input)
            sent = true
            isSending = false
        }
    }
}

// MARK: - View Model

@MainActor
private final class HostConsoleViewModel: ObservableObject {
    let gathering: AmenGathering
    @Published var isPerformingAction = false
    @Published var actionError: String?

    init(gathering: AmenGathering) {
        self.gathering = gathering
    }

    func cancelGathering() {
        performAction {
            try await AmenGatheringService.shared.cancelGathering(
                gatheringId: self.gathering.gatheringId,
                notifyAttendees: true
            )
        }
    }

    func duplicateGathering() {
        performAction {
            _ = try await AmenGatheringService.shared.duplicateGathering(
                gatheringId: self.gathering.gatheringId
            )
        }
    }

    func rotateToken(passId: String) {
        performAction {
            _ = try await AmenAccessPassService.shared.rotateAccessPassToken(accessPassId: passId)
        }
    }

    func pausePass(passId: String) {
        performAction {
            try await AmenAccessPassService.shared.pauseAccessPass(accessPassId: passId)
        }
    }

    func revokePass(passId: String) {
        performAction {
            try await AmenAccessPassService.shared.revokeAccessPass(accessPassId: passId)
        }
    }

    private func performAction(_ work: @escaping () async throws -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task {
            do {
                try await work()
            } catch {
                actionError = error.localizedDescription
            }
            isPerformingAction = false
        }
    }
}
