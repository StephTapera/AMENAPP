// PathProgressCard.swift
// AMENAPP
import SwiftUI

struct PathProgressCard: View {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String
    let progress: Double
    let animatedProgress: Double
    let isLocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isLocked ? Color(.systemGray5) : iconBg)
                        .frame(width: 44, height: 44)
                    Image(systemName: isLocked ? "lock.fill" : icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isLocked ? Color.black.opacity(0.4) : .white)
                }
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isLocked ? .secondary : Color(red: 0.07, green: 0.07, blue: 0.07))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(.systemGray5))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(isLocked ? Color(.systemGray4) : Color.black)
                                .frame(width: geo.size.width * animatedProgress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                Spacer()
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isLocked ? Color.black.opacity(0.4) : Color.secondary)
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .opacity(isLocked ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
