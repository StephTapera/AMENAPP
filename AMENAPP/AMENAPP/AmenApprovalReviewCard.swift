// AmenApprovalReviewCard.swift
// AMENAPP
//
// Phase 8: Liquid Glass upgrade for the incoming message request banner.
// Drop-in used when messagingApprovalCardsEnabled is ON.
// All existing callbacks (accept/decline/block/report) are preserved.

import SwiftUI

struct AmenApprovalReviewCard: View {
    let senderName: String
    let senderAvatarURL: String?
    let mutualFollowerCount: Int

    let onAccept: () -> Void
    let onDecline: () -> Void
    let onViewProfile: () -> Void
    let onRestrict: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    var isAccepting: Bool = false
    var isDeclining: Bool = false

    @State private var showMoreMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                avatarView
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(senderName)
                        .font(.callout.weight(.semibold))
                    Text("Wants to send you a message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showMoreMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .accessibilityLabel("More options")
            }

            if mutualFollowerCount > 0 {
                Text("\(mutualFollowerCount) mutual follower\(mutualFollowerCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Group {
                        if isAccepting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Accept")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
                .disabled(isAccepting || isDeclining)

                Button(action: onDecline) {
                    Group {
                        if isDeclining {
                            ProgressView()
                        } else {
                            Text("Decline")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
                .disabled(isAccepting || isDeclining)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.40), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .confirmationDialog("More options", isPresented: $showMoreMenu) {
            Button("View Profile", action: onViewProfile)
            Button("Restrict", action: onRestrict)
            Button("Block", role: .destructive, action: onBlock)
            Button("Report", role: .destructive, action: onReport)
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlStr = senderAvatarURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(Color(.systemGray4))
            Text(String(senderName.prefix(1)).uppercased())
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
