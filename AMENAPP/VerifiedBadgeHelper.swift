//
//  VerifiedBadgeHelper.swift
//  AMENAPP
//
//  Enhanced verification system for Church and Business accounts
//

import SwiftUI
import FirebaseFirestore
import Combine

// MARK: - Verification Types

enum VerificationType: String, Codable {
    case church         // Verified church/ministry (purple badge)
    case business       // Verified faith-based business/creator (orange badge)
    case none           // Not verified or personal account
}

// MARK: - Verified Badge Helper

@MainActor
class VerifiedBadgeHelper: ObservableObject {
    static let shared = VerifiedBadgeHelper()
    
    // Cache of verified users to avoid repeated Firestore queries
    @Published private var verifiedUsersCache: [String: VerificationType] = [:]
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Check if a user is verified (checks cache first, then Firestore)
    func isVerified(userId: String) -> Bool {
        return verifiedUsersCache[userId] != nil && verifiedUsersCache[userId] != .none
    }
    
    /// Get verification type for a user
    func getVerificationType(userId: String) -> VerificationType {
        return verifiedUsersCache[userId] ?? .none
    }
    
    /// Load verification status from Firestore
    func loadVerificationStatus(for userId: String) async {
        // Check cache first
        if verifiedUsersCache[userId] != nil {
            return
        }
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            
            if let statusString = doc.data()?["verificationStatus"] as? String,
               statusString == "verified",
               let typeString = doc.data()?["verificationType"] as? String {
                if let type = VerificationType(rawValue: typeString) {
                    verifiedUsersCache[userId] = type
                } else {
                    verifiedUsersCache[userId] = .none
                }
            } else {
                verifiedUsersCache[userId] = .none
            }
        } catch {
            dlog("❌ Failed to load verification status for \(userId): \(error)")
            verifiedUsersCache[userId] = .none
        }
    }
    
    /// Preload verification statuses for multiple users (batch loading)
    func preloadVerificationStatuses(for userIds: [String]) async {
        let uncachedIds = userIds.filter { verifiedUsersCache[$0] == nil }
        
        guard !uncachedIds.isEmpty else { return }
        
        // Batch load in chunks of 10
        for chunk in uncachedIds.chunked(into: 10) {
            await withTaskGroup(of: Void.self) { group in
                for userId in chunk {
                    group.addTask {
                        await self.loadVerificationStatus(for: userId)
                    }
                }
            }
        }
    }
}

// MARK: - Verified Badge View

struct VerifiedBadge: View {
    let type: VerificationType
    var size: CGFloat = 16
    
    init(type: VerificationType = .church, size: CGFloat = 16) {
        self.type = type
        self.size = size
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: size, height: size)
            
            Image(systemName: iconName)
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: badgeColor.opacity(0.3), radius: 2, x: 0, y: 1)
    }
    
    private var badgeColor: Color {
        switch type {
        case .church:
            return Color.black // Black for churches
        case .business:
            return Color(red: 0.85, green: 0.15, blue: 0.15) // Red for businesses
        case .none:
            return Color.black // Black (fallback, won't be shown)
        }
    }
    
    private var iconName: String {
        "checkmark.seal.fill"
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
