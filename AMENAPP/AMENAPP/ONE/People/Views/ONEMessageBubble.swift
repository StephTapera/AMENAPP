// ONEMessageBubble.swift
// ONE — E2E-aware message bubble with consent DNA badge.
// Matte content rule: no glassEffect on bubbles — only chrome surfaces get glass.

import SwiftUI

struct ONEMessageBubble: View {
    let message: ONEThreadMessage
    let plaintext: String?          // nil = decryption not yet complete
    let isFromCurrentUser: Bool
    let senderName: String
    let permissions: ONEMomentPermissions

    private var bodyText: String {
        guard let pt = plaintext else {
            return message.ciphertext.isEmpty ? "" : "Decrypting…"
        }
        return pt
    }

    private var isDecrypting: Bool { plaintext == nil && !message.ciphertext.isEmpty }

    var body: some View {
        VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 3) {
            if !isFromCurrentUser {
                Text(senderName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, ONE.Spacing.sm)
            }

            HStack {
                if isFromCurrentUser { Spacer(minLength: 56) }

                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundStyle(isDecrypting ? Color.secondary : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(bubbleFill)
                    .overlay(bubbleBorder)

                if !isFromCurrentUser { Spacer(minLength: 56) }
            }

            if isFromCurrentUser {
                HStack {
                    Spacer()
                    ONEConsentBadgeView(permissions: permissions)
                        .padding(.trailing, ONE.Spacing.sm)
                }
            }

            if message.expiresAt != nil {
                ephemeralRow
                    .padding(.horizontal, ONE.Spacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isFromCurrentUser ? "You" : senderName): \(plaintext ?? "Encrypted message")")
    }

    // MARK: Shapes

    private var bubbleFill: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                isFromCurrentUser
                    ? ONE.Colors.privateIndigo.opacity(0.18)
                    : Color.primary.opacity(0.07)
            )
    }

    private var bubbleBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isFromCurrentUser
                    ? ONE.Colors.privateIndigo.opacity(0.28)
                    : Color.primary.opacity(0.08),
                lineWidth: 0.5
            )
    }

    // MARK: Ephemeral countdown

    private var ephemeralRow: some View {
        HStack(spacing: 3) {
            if isFromCurrentUser { Spacer() }
            Image(systemName: "flame.fill").font(.system(size: 9))
            if let exp = message.expiresAt {
                Text(exp, style: .relative).font(.system(size: 9))
            }
            if !isFromCurrentUser { Spacer() }
        }
        .foregroundStyle(ONE.Colors.ephemeralRed.opacity(0.75))
        .accessibilityLabel(message.expiresAt.map { "Expires \($0.formatted(.relative(presentation: .named)))" } ?? "")
    }
}
