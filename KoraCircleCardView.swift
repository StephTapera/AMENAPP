// KoraCircleCardView.swift
// AMENAPP
//
// Glass card for a single Kora circle in the root feed.

import SwiftUI

struct KoraCircleCardView: View {
    let circle: KoraCircle
    let hasOpenCheckIn: Bool

    private var daysUntilNextCheckIn: String {
        let diff = circle.nextCheckInAt.timeIntervalSinceNow
        let days = Int(ceil(diff / 86400))
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days) days"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: circle.coverColorHex))
                .frame(width: 4)
                .padding(.vertical, 16)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 12) {
                // Top row: name + purpose badge
                HStack(spacing: 10) {
                    Text(circle.name)
                        .font(AMENFont.bold(17))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    purposeBadge
                }

                // Member avatar stack
                memberAvatarStack

                // Next check-in row
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                    Text("Next check-in: \(daysUntilNextCheckIn)")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    if hasOpenCheckIn {
                        openCheckInBadge
                    }
                }

                // AI summary preview
                if let summary = circle.lastCheckInAt.map({ _ in "Last summary" }) {
                    Text(summary)
                        .font(.system(size: 12).italic())
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                } else {
                    Text("No summary yet")
                        .font(.system(size: 12).italic())
                        .foregroundColor(.white.opacity(0.25))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Subviews

    private var purposeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: circle.purpose.icon)
                .font(.system(size: 10))
            Text(circle.purpose.label)
                .font(AMENFont.regular(11))
        }
        .foregroundColor(Color(hex: circle.coverColorHex))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: circle.coverColorHex).opacity(0.12))
        .clipShape(Capsule())
    }

    private var memberAvatarStack: some View {
        HStack(spacing: -8) {
            let visibleCount = min(circle.memberIds.count, 5)
            let overflow = circle.memberIds.count - visibleCount

            ForEach(0..<visibleCount, id: \.self) { index in
                initialsCircle(for: circle.memberIds[index])
            }

            if overflow > 0 {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color(hex: "0A0A0F"), lineWidth: 1.5))
                    Text("+\(overflow)")
                        .font(AMENFont.semiBold(9))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            Text("\(circle.memberCount) member\(circle.memberCount == 1 ? "" : "s")")
                .font(AMENFont.regular(11))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private func initialsCircle(for uid: String) -> some View {
        let initial = String(uid.prefix(1)).uppercased()
        return ZStack {
            Circle()
                .fill(Color(hex: circle.coverColorHex).opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color(hex: "0A0A0F"), lineWidth: 1.5))
            Text(initial)
                .font(AMENFont.bold(11))
                .foregroundColor(Color(hex: circle.coverColorHex))
        }
    }

    private var openCheckInBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: "F59E0B"))
                .frame(width: 6, height: 6)
            Text("Open check-in")
                .font(AMENFont.semiBold(10))
                .foregroundColor(Color(hex: "F59E0B"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(hex: "F59E0B").opacity(0.12))
        .clipShape(Capsule())
    }
}
