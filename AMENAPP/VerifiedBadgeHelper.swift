//
//  VerifiedBadgeHelper.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/12/26.
//

import SwiftUI

// MARK: - Verified Badge Helper

struct VerifiedBadgeHelper {
    // ✅ Verified user IDs
    static let verifiedUserIds: Set<String> = [
        "9GxZ0yenWaWz4CBSyGbPveobYS12"  // Main verified account
    ]

    static func isVerified(userId: String) -> Bool {
        return verifiedUserIds.contains(userId)
    }
}

// MARK: - Verified Badge View

struct VerifiedBadge: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            // Black background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.15),  // Dark gray/black
                            Color(red: 0.05, green: 0.05, blue: 0.05)   // Darker black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // White checkmark
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            Text("Username")
                .font(.system(size: 16, weight: .semibold))
            VerifiedBadge(size: 16)
        }

        HStack(spacing: 8) {
            Text("Display Name")
                .font(.system(size: 20, weight: .bold))
            VerifiedBadge(size: 20)
        }

        HStack(spacing: 8) {
            Text("Small Badge")
                .font(.system(size: 12))
            VerifiedBadge(size: 14)
        }
    }
    .padding()
}
