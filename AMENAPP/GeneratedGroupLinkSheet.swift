//
//  GeneratedGroupLinkSheet.swift
//  AMENAPP
//
//  Shown after a group link is created. Displays the link with copy/share actions.
//  Uses AMEN Liquid Glass: white base, black text, subtle translucency, refined depth.
//

import SwiftUI

struct GeneratedGroupLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: GroupLink
    let groupName: String

    @State private var copied = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                successCard
                Spacer()
                doneButton
            }
            .background(Color(.systemBackground))
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
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Success Card

    private var successCard: some View {
        VStack(spacing: 24) {
            successIcon
            titleSection
            linkURLSection
            actionButtons
            metadataBadges
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 20, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 72, height: 72)
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .scaleEffect(appeared ? 1.0 : 0.5)
        .opacity(appeared ? 1 : 0)
    }

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text("Group Created")
                .font(.custom("OpenSans-Bold", size: 22))
            Text(groupName)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var linkURLSection: some View {
        if let url = link.shareURL {
            Text(url.absoluteString)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                        )
                )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            copyButton
            shareButton
        }
    }

    private var copyButton: some View {
        Button {
            if let url = link.shareURL {
                UIPasteboard.general.string = url.absoluteString
                withAnimation(AmenMotion.micro) { copied = true }
                HapticManager.notification(type: .success)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(AmenMotion.micro) { copied = false }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                Text(copied ? "Copied" : "Copy Link")
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.black)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = link.shareURL {
            ShareLink(item: url) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                    Text("Share")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.black.opacity(0.04))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
            }
        }
    }

    private var metadataBadges: some View {
        HStack(spacing: 8) {
            if let expiry = link.expiresAt {
                metadataBadge(icon: "clock", text: expiryText(for: expiry))
            }
            if let limit = link.memberLimit {
                metadataBadge(icon: "person.2", text: "\(limit) limit")
            }
            metadataBadge(icon: link.joinMode.icon, text: link.joinMode.displayName)
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.custom("OpenSans-Bold", size: 16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.black.opacity(0.04))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func expiryText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Expires \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func metadataBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.custom("OpenSans-Regular", size: 11))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.02))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                )
        )
    }
}
