//
//  QuietModeTooltip.swift
//  AMENAPP
//
//  Contextual tooltip explaining muted/hidden state with revert action.
//  Shows when the user views a muted or hidden user's profile.
//

import SwiftUI

struct QuietModeTooltip: View {
    let isMuted: Bool
    let isHidden: Bool
    let userName: String
    var onUnmute: (() -> Void)? = nil
    var onUnhide: (() -> Void)? = nil

    var body: some View {
        if isMuted || isHidden {
            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "eye.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isMuted ? "You muted \(firstName)" : "You hid \(firstName)'s posts")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(isMuted
                         ? "Their posts won't appear in your feed"
                         : "Their content is hidden from your view")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if isMuted { onUnmute?() }
                    else { onUnhide?() }
                } label: {
                    Text("Undo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var firstName: String {
        userName.components(separatedBy: " ").first ?? userName
    }
}
