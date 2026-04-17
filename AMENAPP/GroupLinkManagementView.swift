//
//  GroupLinkManagementView.swift
//  AMENAPP
//
//  Admin view for managing group invite links and pending join requests.
//  Uses AMEN Liquid Glass: white base, black text, subtle translucency, refined depth.
//

import SwiftUI

struct GroupLinkManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GroupLinkViewModel()

    let conversationId: String
    let groupName: String

    @State private var copied = false
    @State private var showRegenerateConfirm = false
    @State private var showDisableConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let link = viewModel.activeLink {
                        linkHealthCard(link)
                        linkInfoCard(link)
                        linkActionsCard(link)
                    } else if !viewModel.isLoadingManagement {
                        noLinkCard
                    }

                    if !viewModel.pendingRequests.isEmpty {
                        pendingRequestsCard
                    }

                    if let error = viewModel.managementError {
                        Text(error)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.red.opacity(0.04))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Invite Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .overlay {
                if viewModel.isLoadingManagement {
                    ProgressView()
                }
            }
            .task {
                await viewModel.loadManagementData(conversationId: conversationId)
            }
            .confirmationDialog("Regenerate Link?", isPresented: $showRegenerateConfirm) {
                Button("Regenerate", role: .destructive) {
                    Task { await viewModel.regenerateLink(conversationId: conversationId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current link will stop working. A new link will be generated.")
            }
            .confirmationDialog("Disable Link?", isPresented: $showDisableConfirm) {
                Button("Disable", role: .destructive) {
                    Task { await viewModel.disableLink(conversationId: conversationId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("No one will be able to join using this link. You can generate a new one later.")
            }
        }
    }

    // MARK: - Link Health Card

    private func linkHealthCard(_ link: GroupLink) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Link Health")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(link.status)
            }

            HStack(spacing: 16) {
                healthMetric(value: "\(link.joinCount)", label: "Joined", icon: "person.badge.plus")
                if let limit = link.memberLimit {
                    healthMetric(value: "\(limit - link.joinCount)", label: "Remaining", icon: "person.2")
                }
                if let expiry = link.expiresAt {
                    let isExpiringSoon = expiry.timeIntervalSinceNow < 3600
                    healthMetric(
                        value: isExpiringSoon ? "Soon" : timeRemainingShort(expiry),
                        label: "Expires",
                        icon: "clock",
                        alert: isExpiringSoon
                    )
                }
            }
        }
        .padding(18)
        .background(glassCardBackground)
    }

    private func healthMetric(value: String, label: String, icon: String, alert: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(alert ? .orange : Color.gray.opacity(0.5))
            Text(value)
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(alert ? .orange : .primary)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Link Info Card

    private func linkInfoCard(_ link: GroupLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = link.shareURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LINK".uppercased())
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.tertiary)
                        .kerning(0.8)
                    Text(url.absoluteString)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider().opacity(0.3)

            infoRow(label: "Join mode", value: link.joinMode.displayName)
            infoRow(label: "Safety", value: link.safetyTier.displayName)

            if let expiry = link.expiresAt {
                HStack {
                    Text("Expires")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(expiry, style: .relative)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(expiry < Date() ? .red : Color.gray.opacity(0.5))
                }
            }
        }
        .padding(18)
        .background(glassCardBackground)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Link Actions Card

    private func linkActionsCard(_ link: GroupLink) -> some View {
        VStack(spacing: 0) {
            // Copy
            actionRow(icon: copied ? "checkmark" : "doc.on.doc",
                      label: copied ? "Copied" : "Copy Link") {
                if let url = link.shareURL {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation(AmenMotion.micro) { copied = true }
                    HapticManager.notification(type: .success)
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(AmenMotion.micro) { copied = false }
                    }
                }
            }

            thinDivider

            // Share
            if let url = link.shareURL {
                ShareLink(item: url) {
                    actionRowLabel(icon: "square.and.arrow.up", label: "Share Link")
                }
                .buttonStyle(.plain)

                thinDivider
            }

            // Pause / Resume
            if link.status == .active {
                actionRow(icon: "pause.circle", label: "Pause Link") {
                    Task { await viewModel.pauseLink(conversationId: conversationId) }
                }
            } else if link.status == .paused {
                actionRow(icon: "play.circle", label: "Resume Link") {
                    Task { await viewModel.resumeLink(conversationId: conversationId) }
                }
            }

            thinDivider

            // Regenerate
            actionRow(
                icon: "arrow.triangle.2.circlepath",
                label: viewModel.isRegenerating ? "Regenerating..." : "Regenerate Link"
            ) {
                showRegenerateConfirm = true
            }
            .disabled(viewModel.isRegenerating)

            if link.status != .disabled {
                thinDivider

                // Disable (destructive)
                Button {
                    showDisableConfirm = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 16))
                            .frame(width: 24)
                        Text("Disable Link")
                            .font(.custom("OpenSans-Regular", size: 15))
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(glassCardBackground)
    }

    // MARK: - No Link

    private var noLinkCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No active invite link")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)

            Button {
                Task {
                    let link = try? await GroupLinkService.shared.generateLink(
                        conversationId: conversationId
                    )
                    if link != nil {
                        await viewModel.loadManagementData(conversationId: conversationId)
                    }
                }
            } label: {
                Text("Generate Link")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(Color.black)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(glassCardBackground)
    }

    // MARK: - Pending Requests

    private var pendingRequestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PENDING REQUESTS (\(viewModel.pendingRequests.count))")
                .font(.custom("OpenSans-Bold", size: 11))
                .foregroundStyle(.tertiary)
                .kerning(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            ForEach(viewModel.pendingRequests) { request in
                HStack(spacing: 12) {
                    // Avatar
                    if let photoURL = request.userPhotoURL, let url = URL(string: photoURL) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                        } placeholder: {
                            initialsCircle(name: request.userName)
                        }
                    } else {
                        initialsCircle(name: request.userName)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.userName)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text(request.requestedAt, style: .relative)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Approve
                    Button {
                        Task {
                            await viewModel.respondToRequest(
                                conversationId: conversationId,
                                requestId: request.id ?? "",
                                approve: true
                            )
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    // Deny
                    Button {
                        Task {
                            await viewModel.respondToRequest(
                                conversationId: conversationId,
                                requestId: request.id ?? "",
                                approve: false
                            )
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                if request.id != viewModel.pendingRequests.last?.id {
                    thinDivider
                }
            }
            .padding(.bottom, 8)
        }
        .background(glassCardBackground)
    }

    // MARK: - Shared Components

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
            )
    }

    private var thinDivider: some View {
        Divider()
            .padding(.leading, 50)
            .opacity(0.3)
    }

    private func actionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionRowLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func actionRowLabel(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func statusBadge(_ status: GroupLinkStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            Text(status.rawValue.capitalized)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor(status).opacity(0.08))
        )
    }

    private func statusColor(_ status: GroupLinkStatus) -> Color {
        switch status {
        case .active: return .green
        case .paused: return .orange
        case .disabled: return .red
        case .expired: return .secondary
        }
    }

    private func initialsCircle(name: String) -> some View {
        let words = name.split(separator: " ")
        let initials = words.count >= 2
            ? "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
            : String(name.prefix(2)).uppercased()

        return Circle()
            .fill(Color.black.opacity(0.04))
            .frame(width: 38, height: 38)
            .overlay(
                Text(initials)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.tertiary)
            )
    }

    private func timeRemainingShort(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
