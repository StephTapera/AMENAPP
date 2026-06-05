// PrayerPartnerRow.swift
// AMEN App — Community OS / Prayer OS (A7)
//
// A compact row showing prayer partners as an overlapping avatar stack.
// Partners are identified by UID; avatars are loaded asynchronously.
// The "+ Invite" button calls `onInvitePartner` to trigger the partner invitation flow.
//
// Design contract (C3):
//   - White card background, AmenShadow.card spec
//   - Circular avatar stack (overlapping), 32pt diameter
//   - Overflow shown as "+N" circle in secondarySystemFill
//   - 28pt continuous corner radius
//   - 44x44pt touch target minimum

import SwiftUI

// MARK: - PrayerPartnerRow

/// Compact row showing prayer partners with an overlapping avatar stack and an invite button.
/// Used inside PrayerRoomView to show who is actively interceding.
struct PrayerPartnerRow: View {

    /// UIDs of prayer partners actively interceding for this prayer
    let partnerIds: [String]
    /// Maximum number of avatars shown before showing the "+N" overflow circle
    var maxVisible: Int = 5
    /// Called when the user taps the "+ Invite" button
    var onInvitePartner: (() -> Void)?

    private var visibleIds: [String] {
        Array(partnerIds.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, partnerIds.count - maxVisible)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left label
            VStack(alignment: .leading, spacing: 2) {
                Label("Prayer Partners", systemImage: "hands.sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: .label))

                if partnerIds.isEmpty {
                    Text("No partners yet")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                } else {
                    Text("\(partnerIds.count) praying")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }

            Spacer()

            // Avatar stack
            if !partnerIds.isEmpty {
                avatarStack
            }

            // Invite button
            inviteButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.07), radius: 24, x: 0, y: 5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            partnerIds.isEmpty
                ? "Prayer partners. No partners yet. Double tap to invite a partner."
                : "Prayer partners. \(partnerIds.count) praying. Double tap to invite a partner."
        )
    }

    // MARK: - Avatar Stack

    private var avatarStack: some View {
        HStack(spacing: -10) {
            ForEach(Array(visibleIds.enumerated()), id: \.element) { index, uid in
                PartnerAvatarCircle(uid: uid, index: index)
            }

            if overflowCount > 0 {
                overflowCircle
            }
        }
    }

    private var overflowCircle: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )

            Text("+\(overflowCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .accessibilityLabel("\(overflowCount) more prayer partners")
    }

    // MARK: - Invite Button

    private var inviteButton: some View {
        Button {
            onInvitePartner?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Invite")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Invite a prayer partner")
    }
}

// MARK: - PartnerAvatarCircle

/// Individual avatar circle for a prayer partner.
/// Shows user initials as fallback while the avatar URL resolves.
private struct PartnerAvatarCircle: View {
    let uid: String
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            // Initials fallback — replace with AsyncImage once avatar URL resolution is wired
            Text(initials)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .zIndex(Double(index) * -1)
        .accessibilityLabel("Prayer partner")
    }

    private var initials: String {
        // Generate placeholder initials from UID prefix until real user data is loaded
        let prefix = uid.prefix(2).uppercased()
        return prefix.isEmpty ? "?" : String(prefix)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With partners") {
    VStack(spacing: 20) {
        PrayerPartnerRow(
            partnerIds: ["uid_A", "uid_B", "uid_C", "uid_D", "uid_E", "uid_F"],
            maxVisible: 4,
            onInvitePartner: { }
        )
        .padding(.horizontal, 20)

        PrayerPartnerRow(
            partnerIds: ["uid_A", "uid_B"],
            maxVisible: 5,
            onInvitePartner: { }
        )
        .padding(.horizontal, 20)

        PrayerPartnerRow(
            partnerIds: [],
            maxVisible: 5,
            onInvitePartner: { }
        )
        .padding(.horizontal, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif
