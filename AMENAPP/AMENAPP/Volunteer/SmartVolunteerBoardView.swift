//  SmartVolunteerBoardView.swift
//  AMEN — Smart Volunteer Board · Wave 0 UI.
//
//  Renders the DERIVED board ("Greeters 2/4 filled", "Worship full", "Media needs 1 backup"),
//  one-tap sign-up, a stubbed Request Swap (Wave 1), and a permission-gated leader panel
//  (approval + private notes). All surfaces are flag-gated OFF by default (VolunteerFeatureFlags).
//
//  The view is presentation-only: every invariant (atomic fill, blackout, leader-only notes)
//  is enforced server-side. The client just renders the server's decisions.

import SwiftUI

struct SmartVolunteerBoardView: View {
    let event: ServiceEvent
    let volunteerId: String
    let isLeader: Bool

    @StateObject private var service = VolunteerBoardService.shared
    @ObservedObject private var flags = VolunteerFlagService.shared

    @State private var board: VolunteerBoard?
    @State private var isLoading = true
    @State private var signingUpRole: String?
    @State private var banner: String?

    var body: some View {
        Group {
            if !flags.isEnabled(.scheduling) || !flags.isEnabled(.board) {
                // Hard gate: nothing volunteer-related renders until Remote Config enables it.
                EmptyView()
            } else {
                content
            }
        }
        .task { await reload() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let banner {
                    Text(banner)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let board, !board.roles.isEmpty {
                    ForEach(board.roles) { role in
                        roleCard(role)
                    }
                } else {
                    Text("No roles are open for this event yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLeader {
                    LeaderPanel(event: event, service: service)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.title2.weight(.semibold))
            Text(event.location).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Role card

    private func roleCard(_ role: VolunteerBoardRole) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(role.role).font(.headline)
                Text(statusText(role))
                    .font(.subheadline)
                    .foregroundStyle(statusColor(role))
            }
            Spacer()

            if role.status == .open {
                signUpButton(for: role)
            } else {
                Text(badgeText(role))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(statusColor(role).opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor(role))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) { requestSwapButton.padding(8) }
    }

    private func signUpButton(for role: VolunteerBoardRole) -> some View {
        Button {
            Task { await signUp(role: role) }
        } label: {
            if signingUpRole == role.role {
                ProgressView()
            } else {
                Text("Sign Up").font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.borderedProminent)
        // One-tap sign-up is itself flag-gated; the board can be visible read-only without it.
        .disabled(!flags.isEnabled(.signup) || signingUpRole != nil)
    }

    /// Request Swap is intentionally a stub in Wave 0 (swap-request state machine is deferred).
    private var requestSwapButton: some View {
        Button {
            banner = "Swap requests arrive in a later update."
        } label: {
            Text("Request Swap")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(true) // Wave 1 — see DEFERRED.
    }

    // MARK: - Actions

    private func reload() async {
        guard flags.isEnabled(.scheduling), flags.isEnabled(.board) else { return }
        isLoading = true
        board = await service.loadBoard(eventId: event.id)
        isLoading = false
    }

    private func signUp(role: VolunteerBoardRole) async {
        guard flags.isEnabled(.signup) else { return }
        signingUpRole = role.role
        defer { signingUpRole = nil }
        let result = await service.signUp(eventId: event.id, role: role.role, volunteerId: volunteerId)
        switch result?.decision {
        case .fill?:             banner = "You're signed up for \(role.role). 🙌"
        case .waitlist?:         banner = "\(role.role) is full — you're on the waitlist."
        case .reject_blackout?:  banner = "You marked this date unavailable, so we didn't sign you up."
        case .reject_duplicate?: banner = "You're already signed up for \(role.role)."
        case nil:                banner = "Couldn't sign up just now. Please try again."
        }
        await reload()
    }

    // MARK: - Presentation helpers

    private func statusText(_ role: VolunteerBoardRole) -> String {
        switch role.status {
        case .open:        return "\(role.filled)/\(role.needed) filled"
        case .full:        return "Full · \(role.filled)/\(role.needed)"
        case .needsBackup: return "Needs backup · \(role.filled)/\(role.needed)"
        case .closed:      return "Closed"
        }
    }

    private func badgeText(_ role: VolunteerBoardRole) -> String {
        switch role.status {
        case .full:        return "Full"
        case .needsBackup: return "Needs backup"
        case .closed:      return "Closed"
        case .open:        return "Open"
        }
    }

    private func statusColor(_ role: VolunteerBoardRole) -> Color {
        switch role.status {
        case .open:        return .blue
        case .full:        return .green
        case .needsBackup: return .orange
        case .closed:      return .secondary
        }
    }
}

// MARK: - Leader panel (permission-gated; notes are leader-only + access-logged server-side)

private struct LeaderPanel: View {
    let event: ServiceEvent
    let service: VolunteerBoardService

    @State private var noteVolunteerId = ""
    @State private var noteText = ""
    @State private var approveAssignmentId = ""
    @State private var statusLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leader tools").font(.headline)
            Text("Private notes are leader-only and every read is logged.")
                .font(.caption).foregroundStyle(.secondary)

            // Approve a signed-up volunteer (signedUp → confirmed).
            VStack(alignment: .leading, spacing: 6) {
                Text("Approve assignment").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("Assignment ID", text: $approveAssignmentId)
                        .textFieldStyle(.roundedBorder)
                    Button("Approve") {
                        Task {
                            let ok = await service.leaderApprove(assignmentId: approveAssignmentId)
                            statusLine = ok ? "Approved." : "Approve failed."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(approveAssignmentId.isEmpty)
                }
            }

            Divider()

            // Private note read/write for a volunteer.
            VStack(alignment: .leading, spacing: 6) {
                Text("Private note").font(.subheadline.weight(.semibold))
                TextField("Volunteer ID", text: $noteVolunteerId)
                    .textFieldStyle(.roundedBorder)
                TextField("Note (leader-only)", text: $noteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack {
                    Button("Load") {
                        Task {
                            let note = await service.getLeaderNote(eventId: event.id, volunteerId: noteVolunteerId)
                            noteText = note?.note ?? ""
                            statusLine = note == nil ? "Couldn't load note." : "Loaded (access logged)."
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(noteVolunteerId.isEmpty)

                    Button("Save") {
                        Task {
                            let ok = await service.setLeaderNote(
                                eventId: event.id, volunteerId: noteVolunteerId, note: noteText)
                            statusLine = ok ? "Saved (access logged)." : "Save failed."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(noteVolunteerId.isEmpty)
                }
            }

            if let statusLine {
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
