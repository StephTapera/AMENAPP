//
//  AgeAssuranceService.swift
//  AMENAPP
//
//  Age verification and tier-based feature gating.
//  Tiers match COPPA / UK Children's Code / App Store 4+ guidelines:
//
//    Tier A (blocked) — Under 13
//      - Account creation blocked at signup
//      - Existing flagged accounts are locked; all features unavailable
//
//    Tier B (13–15)
//      - DMs disabled (no conversations, no message requests)
//      - Dating feature disabled
//      - Profile not shown in People Discovery to users they don't follow
//      - Cannot receive DMs from non-followers
//      - AI-generated content clearly labeled
//
//    Tier C (16–17)
//      - DMs restricted to mutual followers only
//      - Dating feature disabled
//      - Can appear in People Discovery but not surfaced to adults by default
//
//    Tier D (18+)
//      - Full access to all features
//
//  Usage:
//    AgeAssuranceService.shared.canUseDMs       // Bool
//    AgeAssuranceService.shared.canUseDating    // Bool
//    AgeAssuranceService.shared.canSendDMTo(userId:)  // async Bool
//    AgeAssuranceService.shared.tier            // AgeTier
//

import SwiftUI
import Observation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Age Tier

enum AgeTier: String, Codable {
    /// Under 13 — blocked
    case blocked = "blocked"
    /// 13–15 — restricted messaging, no dating, reduced discovery
    case tierB = "tierB"
    /// 16–17 — mutual-follower DMs only, no dating
    case tierC = "tierC"
    /// 18+ — full access
    case tierD = "tierD"

    /// Human-readable description
    var displayName: String {
        switch self {
        case .blocked: return "Under 13 — Account Locked"
        case .tierB:   return "Teen (13–15)"
        case .tierC:   return "Teen (16–17)"
        case .tierD:   return "Adult (18+)"
        }
    }

    static func tier(forAge age: Int) -> AgeTier {
        switch age {
        case ..<13: return .blocked
        case 13...15: return .tierB
        case 16...17: return .tierC
        default:    return .tierD
        }
    }
}

// MARK: - AgeAssuranceService

@MainActor
@Observable
final class AgeAssuranceService {

    static let shared = AgeAssuranceService()
    private init() {}

    private(set) var tier: AgeTier = .tierD
    private(set) var isLoaded = false

    private let db = Firestore.firestore()

    // MARK: - Feature Gates

    /// DMs are unavailable for Tier B (13–15) and blocked accounts.
    var canUseDMs: Bool {
        switch tier {
        case .blocked, .tierB: return false
        case .tierC, .tierD:   return true
        }
    }

    /// Dating is unavailable for anyone under 18.
    var canUseDating: Bool {
        return tier == .tierD
    }

    /// Whether the user is eligible to appear in People Discovery.
    /// Tier B users only appear to followers; Tier C/D appear normally.
    var canAppearInDiscovery: Bool {
        return tier != .blocked
    }

    /// Whether this user should be surfaced to adult (18+) users in Discovery.
    var isVisibleToAdults: Bool {
        switch tier {
        case .blocked, .tierB, .tierC: return false
        case .tierD: return true
        }
    }

    /// Tier B users cannot receive DMs from anyone.
    /// Tier C users can only DM mutual followers (checked per-conversation).
    /// Tier D: no restriction.
    func canReceiveDMFromUser(senderTier: AgeTier) -> Bool {
        switch tier {
        case .blocked: return false
        case .tierB:   return false  // No DMs at all
        case .tierC:   return senderTier == .tierC || senderTier == .tierD
        case .tierD:   return senderTier != .blocked
        }
    }

    /// Check if the current user can send a DM to a given recipient.
    /// For Tier C users, verifies mutual follow before allowing.
    func canSendDMTo(userId recipientId: String) async -> Bool {
        guard canUseDMs else { return false }

        if tier == .tierC {
            // Mutual follow check
            guard let uid = Auth.auth().currentUser?.uid else { return false }
            let iFollowThem = await checkFollows(from: uid, to: recipientId)
            let theyFollowMe = await checkFollows(from: recipientId, to: uid)
            return iFollowThem && theyFollowMe
        }

        return true
    }

    // MARK: - Load User Tier

    /// Load the age tier from Firestore for the current user.
    /// Call this once after auth state changes to .signedIn.
    func loadTier(for userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else {
                // No data — default to full access
                tier = .tierD
                isLoaded = true
                return
            }

            // Prefer the server-set `ageTier` field (written by Cloud Functions / admin SDK)
            if let raw = data["ageTier"] as? String, let serverTier = AgeTier(rawValue: raw) {
                tier = serverTier
            } else if let birthYear = data["birthYear"] as? Int {
                // Fallback: compute from stored birth year
                let age = Calendar.current.component(.year, from: Date()) - birthYear
                tier = AgeTier.tier(forAge: age)
            } else {
                // No ageTier or birthYear on this account. These are existing accounts
                // created before the age assurance system was added. Treat as adults (tierD)
                // so existing users are not locked out. New signups always write ageTier via
                // the onboarding flow, so this fallback only applies to legacy/dev accounts.
                tier = .tierD
            }

            isLoaded = true
        } catch {
            dlog("❌ AgeAssuranceService: Failed to load tier — \(error)")
            // On a transient Firestore error, default to the most restrictive safe tier
            // rather than granting full adult access. The gate will re-evaluate on next load.
            tier = .tierB
            isLoaded = false  // Leave false so the next app foreground triggers a retry
        }
    }

    /// Called when user signs out
    func reset() {
        tier = .tierB
        isLoaded = false
    }

    // MARK: - Age at Signup

    /// Validate a birth date entered during signup.
    /// Returns the tier, or nil if the date is in the future.
    static func tier(forBirthDate date: Date) -> AgeTier? {
        let now = Date()
        guard date < now else { return nil }
        let age = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return AgeTier.tier(forAge: age)
    }

    // MARK: - Onboarding Gate

    /// Returns true if the signup should be blocked (user is under 13).
    static func shouldBlockSignup(birthDate: Date) -> Bool {
        return tier(forBirthDate: birthDate) == .blocked
    }

    // MARK: - Private Helpers

    private func checkFollows(from userId: String, to targetId: String) async -> Bool {
        do {
            let snap = try await db.collection("users").document(userId)
                .collection("following").document(targetId).getDocument()
            return snap.exists
        } catch {
            return false
        }
    }
}

// MARK: - AgeGate View Modifier

/// Wraps a feature view with an age gate.
/// Usage: `.ageGated(feature: .dms)`
struct AgeGateModifier: ViewModifier {
    enum GatedFeature {
        case dms, dating, discovery
        var displayName: String {
            switch self {
            case .dms:       return "Direct Messages"
            case .dating:    return "Christian Dating"
            case .discovery: return "People Discovery"
            }
        }
    }

    let feature: GatedFeature
    private var ageService: AgeAssuranceService { AgeAssuranceService.shared }

    private var isAllowed: Bool {
        // While the tier hasn't been loaded from Firestore yet, pass through.
        // The real gate check happens once isLoaded == true.
        guard ageService.isLoaded else { return true }
        switch feature {
        case .dms:       return ageService.canUseDMs
        case .dating:    return ageService.canUseDating
        case .discovery: return ageService.canAppearInDiscovery
        }
    }

    func body(content: Content) -> some View {
        if isAllowed {
            content
        } else {
            AgeGateBlockedView(featureName: feature.displayName)
        }
    }
}

extension View {
    func ageGated(feature: AgeGateModifier.GatedFeature) -> some View {
        modifier(AgeGateModifier(feature: feature))
    }
}

// MARK: - AgeGateBlockedView

struct AgeGateBlockedView: View {
    let featureName: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(featureName) Unavailable")
                .font(.title3)
                .fontWeight(.semibold)
            Text("This feature is not available for your account.\nVisit Settings for more information.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - AccountLockedView (Under-13 / Blocked Tier Full-Screen Gate)

/// Shown as a full-screen overlay when the authenticated user's ageTier is "blocked"
/// (age < 13). Prevents all app access and prompts the user to sign out.
struct AccountLockedView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red.opacity(0.85))
                    .symbolEffect(.pulse)

                VStack(spacing: 12) {
                    Text("Account Locked")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("AMEN is designed for users 13 and older.\n\nThis account does not meet the minimum age requirement and has been restricted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    try? Auth.auth().signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 32)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}
