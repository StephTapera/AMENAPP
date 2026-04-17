//
//  JoinGroupViaLinkView.swift
//  AMENAPP
//
//  Preview and join flow when a user opens a group invite link.
//  Always shows preview first — never auto-joins.
//  Uses AMEN Liquid Glass: white base, black text, subtle translucency, refined depth.
//

import SwiftUI

struct JoinGroupViaLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GroupLinkViewModel()

    let token: String

    /// Called when user successfully joins. Passes the conversationId.
    var onJoined: ((String) -> Void)?

    @State private var contentAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if viewModel.isLoadingPreview {
                    loadingState
                } else if let error = viewModel.previewError {
                    errorState(error)
                } else if let preview = viewModel.preview {
                    if preview.isExpired || preview.isDisabled {
                        unavailableState(preview)
                    } else if preview.isPaused {
                        pausedState
                    } else if preview.isFull {
                        fullState(preview)
                    } else {
                        previewContent(preview)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                await viewModel.loadPreview(token: token)
                await viewModel.evaluateJoin()
                withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                    contentAppeared = true
                }
            }
            .onChange(of: viewModel.joinedConversationId) { _, newId in
                if let id = newId {
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        onJoined?(id)
                    }
                }
            }
        }
    }

    // MARK: - Preview Content

    private func previewContent(_ preview: GroupLinkPreview) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Glass card container
            VStack(spacing: 20) {
                // Group icon
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 80, height: 80)
                    Image(systemName: preview.purpose.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                }

                // Group info
                VStack(spacing: 6) {
                    Text(preview.groupName)
                        .font(.custom("OpenSans-Bold", size: 24))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        Label("\(preview.memberCount) members", systemImage: "person.2")
                        Text("·")
                        Text(preview.purpose.displayName)
                    }
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)

                    if let creator = preview.creatorName {
                        Text("Created by \(creator)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Trust signal
                trustSignalView(preview)

                // Join mode + safety badges
                HStack(spacing: 8) {
                    glassBadge(icon: preview.joinMode.icon, text: preview.joinMode.displayName)
                    if preview.safetyTier == .strict {
                        glassBadge(icon: "shield.checkered", text: "Strict Safety")
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 24)
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 20)

            Spacer()

            // Action area
            VStack(spacing: 12) {
                actionButtons

                // Error display
                if let error = viewModel.joinError {
                    Text(error)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Request submitted confirmation
                if viewModel.requestSubmitted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Request sent — you'll be notified when approved")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.green.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 20)
            .opacity(contentAppeared ? 1 : 0)
        }
    }

    // MARK: - Trust Signal

    @ViewBuilder
    private func trustSignalView(_ preview: GroupLinkPreview) -> some View {
        if let signalText = preview.trustSignalText {
            HStack(spacing: 8) {
                Image(systemName: preview.mutualMemberCount > 0
                      ? "person.2.circle.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(preview.mutualMemberCount > 0
                                    ? Color.black.opacity(0.6) : Color.black.opacity(0.3))
                Text(signalText)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(preview.mutualMemberCount > 0 ? .secondary : .tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(preview.mutualMemberCount > 0
                          ? Color.black.opacity(0.04) : Color.black.opacity(0.02))
            )
        }
    }

    private func glassBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 12))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.03))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if let eval = viewModel.joinEvaluation {
            switch eval.outcome {
            case .allowed:
                primaryActionButton(
                    title: "Join Group",
                    isLoading: viewModel.isJoining
                ) {
                    Task { await viewModel.joinGroup() }
                }
                .disabled(viewModel.isJoining)

            case .requestRequired:
                if !viewModel.requestSubmitted {
                    primaryActionButton(
                        title: "Request to Join",
                        isLoading: viewModel.isRequesting
                    ) {
                        Task { await viewModel.requestToJoin() }
                    }
                    .disabled(viewModel.isRequesting)
                }

            case .alreadyMember:
                secondaryActionButton(title: "Open Conversation") {
                    if let convId = eval.conversationId {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            onJoined?(convId)
                        }
                    }
                }

            case .blocked:
                statusBanner(icon: "xmark.shield.fill", color: .red,
                           text: eval.reason ?? "You cannot join this group.")

            case .expired:
                statusBanner(icon: "clock.badge.xmark", color: .orange,
                           text: "This invite link has expired.")

            case .full:
                statusBanner(icon: "person.crop.circle.badge.xmark", color: .orange,
                           text: "This group has reached its member limit.")

            case .disabled:
                statusBanner(icon: "link.badge.plus", color: .secondary,
                           text: "This invite link is no longer active.")

            case .paused:
                statusBanner(icon: "pause.circle.fill", color: .orange,
                           text: "This invite link is temporarily paused.")
            }
        } else if viewModel.isEvaluating {
            ProgressView("Checking eligibility...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func primaryActionButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.black)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 24)
    }

    private func secondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.black.opacity(0.04))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 24)
    }

    private func statusBanner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 24)
    }

    // MARK: - State Views

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading invite...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load invite")
                .font(.custom("OpenSans-Bold", size: 18))
            Text(error)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func unavailableState(_ preview: GroupLinkPreview) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Invite No Longer Available")
                .font(.custom("OpenSans-Bold", size: 18))
            Text(preview.isExpired ? "This invite link has expired." : "This invite link has been disabled.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var pausedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Invite Paused")
                .font(.custom("OpenSans-Bold", size: 18))
            Text("This invite link is temporarily paused. Try again later.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func fullState(_ preview: GroupLinkPreview) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Group Full")
                .font(.custom("OpenSans-Bold", size: 18))
            Text("\(preview.groupName) has reached its member limit.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
