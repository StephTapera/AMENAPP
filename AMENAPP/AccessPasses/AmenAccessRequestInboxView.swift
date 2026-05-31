// AmenAccessRequestInboxView.swift
// AMENAPP — Access Request Review Inbox
//
// Admin reviews pending access requests with approve/deny actions.

import SwiftUI

struct AmenAccessRequestInboxView: View {
    let targetType: AmenAccessTargetType
    let targetId: String
    let targetTitle: String

    @State private var requests: [AmenAccessRequest] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var filter: AmenAccessRequestStatus? = .pending
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var filteredRequests: [AmenAccessRequest] {
        guard let filter else { return requests }
        return requests.filter { $0.status == filter }
    }

    var body: some View {
        List {
            filterPills

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel("Loading access requests")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if filteredRequests.isEmpty {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "tray",
                    description: Text("No \(filter?.displayName.lowercased() ?? "") requests for \(targetTitle).")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRequests) { request in
                    RequestDetailRow(request: request) {
                        Task { await approve(request) }
                    } onDeny: {
                        Task { await deny(request) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Join Requests")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var filterPills: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(nil, label: "All")
                    filterPill(.pending, label: "Pending")
                    filterPill(.approved, label: "Approved")
                    filterPill(.denied, label: "Denied")
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func filterPill(_ status: AmenAccessRequestStatus?, label: String) -> some View {
        let isSelected = filter == status
        return Button(label) {
            withAnimation { filter = status }
        }
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(isSelected
                    ? AnyShapeStyle(Color.primary)
                    : (reduceTransparency
                        ? AnyShapeStyle(Color(.systemFill))
                        : AnyShapeStyle(.ultraThinMaterial)))
        }
        .overlay(isSelected ? nil : Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
        .accessibilityLabel("Filter by \(label)")
    }

    private func load() async {
        isLoading = true
        do {
            requests = try await AmenAccessPassService.shared.listAccessRequestsForTarget(
                targetType: targetType, targetId: targetId
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func approve(_ request: AmenAccessRequest) async {
        do {
            try await AmenAccessPassService.shared.approveAccessRequest(requestId: request.requestId)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deny(_ request: AmenAccessRequest) async {
        do {
            try await AmenAccessPassService.shared.denyAccessRequest(requestId: request.requestId)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Request Detail Row

private struct RequestDetailRow: View {
    let request: AmenAccessRequest
    var onApprove: () -> Void
    var onDeny: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(reduceTransparency
                        ? AnyShapeStyle(Color(.systemFill))
                        : AnyShapeStyle(.ultraThinMaterial))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                    .overlay(
                        Text(initials)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.requesterDisplayName ?? "Someone")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(request.createdAt.formatted(.relative(presentation: .numeric)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RequestStatusBadge(status: request.status)
            }

            if let message = request.requestMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 50)
            }

            if request.status == .pending {
                HStack(spacing: 12) {
                    Spacer()
                    Button("Deny", role: .destructive, action: onDeny)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Deny request from \(request.requesterDisplayName ?? "user")")

                    Button("Approve", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Approve request from \(request.requesterDisplayName ?? "user")")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let name = request.requesterDisplayName ?? "?"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

private struct RequestStatusBadge: View {
    let status: AmenAccessRequestStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch status {
        case .pending:   return .orange
        case .approved:  return .green
        case .denied:    return .red
        case .cancelled: return .secondary
        case .expired:   return .secondary
        }
    }
}
