// TableCardView.swift
// AMEN — Table Card UI
//
// Displays a Table with name, anchor, member initials (up to 12),
// sunset countdown, and join/leave controls.
// No vanity counters. No urgency language. Sunset is warm, not alarming.
// Flag-gated: AMENFeatureFlags.shared.tables

import SwiftUI

struct TableCardView: View {

    // MARK: - Input

    let table: Table
    let currentUid: String
    /// Display names keyed by uid.
    let displayNames: [String: String]
    let onJoin: () async throws -> Void
    let onLeave: () async throws -> Void

    // MARK: - State

    @State private var isJoining = false
    @State private var joinError: String?

    // MARK: - Computed

    private var isMember: Bool {
        table.members.contains(currentUid)
    }

    private var isAtCap: Bool {
        table.members.count >= table.memberLimit
    }

    private var seatsRemaining: Int {
        max(0, table.memberLimit - table.members.count)
    }

    private var sunsetDays: Int {
        let diff = table.sunsetAt.timeIntervalSince(Date())
        return max(0, Int(diff / 86400))
    }

    private var isSunsetApproaching: Bool {
        sunsetDays <= 7
    }

    private var sunsetText: String {
        if isSunsetApproaching {
            return "This Table is drawing to a close."
        } else if sunsetDays == 1 {
            return "1 day remaining"
        } else {
            return "\(sunsetDays) days remaining"
        }
    }

    private var anchorLabel: String {
        switch table.anchor {
        case .study(let ref):
            return "Study: \(ref)"
        case .season(let ref):
            return "Season: \(ref)"
        case .topic(let t):
            return t
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.tables {
                cardContent
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(table.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(anchorLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Member initials row (up to 12)
            memberInitialsRow

            // Seat availability — informational only, no urgency
            if seatsRemaining == 1 && !isMember {
                Text("1 seat remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sunset countdown
            HStack(spacing: 6) {
                Image(systemName: isSunsetApproaching ? "hourglass" : "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sunsetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sunsetText)

            // Error feedback
            if let errorMessage = joinError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Action button
            if isMember {
                Button {
                    Task { try? await onLeave() }
                } label: {
                    Text("Leave Table")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await attemptJoin() }
                } label: {
                    Text("Join Table")
                        .font(.callout)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAtCap || isJoining)
                .accessibilityLabel(isAtCap ? "This Table is full." : "Join Table")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var memberInitialsRow: some View {
        let visibleMembers = Array(table.members.prefix(table.memberLimit))
        HStack(spacing: -6) {
            ForEach(visibleMembers, id: \.self) { uid in
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(displayNames[uid]?.prefix(1) ?? "?"))
                            .font(.caption)
                            .fontWeight(.semibold)
                    )
                    .accessibilityLabel(displayNames[uid] ?? "member")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table members")
    }

    // MARK: - Actions

    private func attemptJoin() async {
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            try await onJoin()
        } catch TableServiceError.tableFull {
            joinError = "This Table has reached its limit. Another Table may have room."
        } catch {
            joinError = "Something went wrong. Please try again."
        }
    }
}
