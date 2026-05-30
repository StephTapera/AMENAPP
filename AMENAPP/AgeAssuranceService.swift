//
//  AgeAssuranceService.swift
//  AMENAPP
//
//  Layered age assurance service following Meta's Instagram/Threads pattern:
//  1. Declared age (DOB at sign-up)
//  2. Triggered verification (ID/selfie when suspicious)
//  3. AI age detection (background risk scoring)
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
class AgeAssuranceService: ObservableObject {
    static let shared = AgeAssuranceService()
    
    // MARK: - Published Properties
    
    @Published var currentUserTier: AMENAgeAssuranceTier = .adult
    @Published var currentUserAge: Int = 0
    @Published var needsVerification: Bool = false
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()
    private var config = AgeGateConfig.default
    private var ageProfileCache: [String: (profile: UserAgeProfile, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = 300  // 5 minutes
    
    private init() {}
    
    // MARK: - Public API
    
    /// Load age tier for user (called on app launch and sign-in)
    func loadTier(for userId: String) async {
        do {
            let profile = try await getAgeProfile(userId: userId)
            await MainActor.run {
                currentUserTier = profile.tier
                currentUserAge = profile.age
                needsVerification = profile.needsVerification
            }
            dlog("✅ Age tier loaded: \(profile.tier.rawValue), age: \(profile.age)")
        } catch let error as AgeAssuranceError where error == .profileNotFound {
            // MIGRATION: User pre-dates the age assurance system or skipped DOB entry.
            // SECURITY FIX (C-02): previously auto-upgraded to .adult using a synthetic
            // DOB, allowing actual minors to receive full adult DM access. Now we default
            // to .teen and set needsVerification=true so the app prompts for DOB on next
            // session. All restricted features stay blocked until the user provides their
            // real date of birth via setDateOfBirth().
            dlog("⚠️ Age profile not found for user — defaulting to teen tier, prompting for DOB")
            await createUnverifiedMigrationProfile(userId: userId)
            await MainActor.run {
                currentUserTier = .teen
                needsVerification = true
            }
        } catch {
            dlog("⚠️ Failed to load age tier: \(error.localizedDescription)")
            // Transient network errors: preserve the last-known tier rather than
            // defaulting to adult. If no tier has ever been set, .teen is safe default.
            await MainActor.run {
                if currentUserTier == .adult && currentUserAge == 0 {
                    // Never loaded before — fail closed
                    currentUserTier = .teen
                }
                // Otherwise preserve existing cached tier across transient errors
            }
        }
    }
    
    /// Store user's date of birth during sign-up (BEFORE account creation)
    func setDateOfBirth(
        userId: String,
        dateOfBirth: Date,
        countryCode: String = "US"
    ) async throws {
        // Validate age meets minimum requirement
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        guard age >= AppConfig.Legal.minimumAge else {
            throw AgeAssuranceError.underMinimumAge(minimum: AppConfig.Legal.minimumAge, actual: age)
        }
        
        // Create age profile
        let profile = UserAgeProfile(
            dateOfBirth: dateOfBirth,
            countryCode: countryCode,
            verificationMethod: .dateOfBirth
        )
        
        // Store in private subcollection (encrypted at rest by Firestore)
        try await db.collection("users")
            .document(userId)
            .collection("private")
            .document("age_assurance")
            .setData(try Firestore.Encoder().encode(profile))
        
        // Log event
        try await logVerificationEvent(
            AgeVerificationEvent(
                userId: userId,
                eventType: .ageCollected,
                method: .dateOfBirth,
                newTier: profile.tier
            )
        )
        
        // Update cache
        ageProfileCache[userId] = (profile, Date())
        
        // Update published properties
        await MainActor.run {
            currentUserTier = profile.tier
            currentUserAge = profile.age
        }
        
        dlog("✅ Date of birth stored for user \(userId): tier=\(profile.tier.rawValue)")
    }
    
    /// Creates a placeholder age profile for pre-existing users with no DOB on file.
    /// Defaults to .teen (restricted) and marks needsVerification=true so the app
    /// prompts for a real date of birth. Never grants adult access speculatively.
    private func createUnverifiedMigrationProfile(userId: String) async {
        // Use a placeholder DOB of exactly 16 years ago — firmly in the teen tier.
        // This keeps the account usable for non-DM features while blocking adult-only
        // access until the user provides their real DOB.
        let sixteenYearsAgo = Calendar.current.date(
            byAdding: .year, value: -16, to: Date()
        ) ?? Date()

        var profile = UserAgeProfile(
            dateOfBirth: sixteenYearsAgo,
            countryCode: "US",
            verificationMethod: .dateOfBirth
        )
        profile.verificationStatus = .pending

        do {
            try await db.collection("users")
                .document(userId)
                .collection("private")
                .document("age_assurance")
                .setData(try Firestore.Encoder().encode(profile))

            // Write tierB (teen) so Firestore rules restrict DMs until real DOB provided.
            try await db.collection("users")
                .document(userId)
                .setData(["ageTier": "tierB", "needsAgeVerification": true], merge: true)

            ageProfileCache[userId] = (profile, Date())

            await MainActor.run {
                currentUserAge = profile.age
            }
            dlog("⚠️ Age migration: user \(userId) defaulted to teen (tierB), DOB required")
        } catch {
            dlog("⚠️ Age migration failed (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Get age profile for user
    func getAgeProfile(userId: String) async throws -> UserAgeProfile {
        // Check cache first
        if let cached = ageProfileCache[userId],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.profile
        }
        
        // Fetch from Firestore
        let doc = try await db.collection("users")
            .document(userId)
            .collection("private")
            .document("age_assurance")
            .getDocument()
        
        guard let profile = try? doc.data(as: UserAgeProfile.self) else {
            throw AgeAssuranceError.profileNotFound
        }
        
        // Update cache
        ageProfileCache[userId] = (profile, Date())
        
        return profile
    }
    
    /// Check if user can access a feature (age-gated)
    func canAccess(feature: AgeRestrictedFeature, userId: String? = nil) async -> Bool {
        // Use cached tier if available
        if userId == nil || userId == Auth.auth().currentUser?.uid {
            return currentUserTier.canAccess(feature: feature)
        }
        
        // Fetch tier for other user
        guard let userId = userId else { return false }
        do {
            let profile = try await getAgeProfile(userId: userId)
            return profile.canAccess(feature: feature)
        } catch {
            dlog("⚠️ Failed to check feature access: \(error.localizedDescription)")
            return false  // Fail closed for safety
        }
    }
    
    /// Request age verification (triggered by suspicious activity or age change)
    func requestVerification(
        userId: String,
        reason: String,
        method: AgeVerificationMethod = .governmentID
    ) async throws {
        var profile = try await getAgeProfile(userId: userId)
        
        // Check verification cooldown
        if let lastAttempt = profile.lastVerificationAttempt {
            let elapsed = Date().timeIntervalSince(lastAttempt)
            if elapsed < config.verificationCooldown {
                let remaining = Int(config.verificationCooldown - elapsed)
                throw AgeAssuranceError.verificationCooldown(remainingSeconds: remaining)
            }
        }
        
        // Check max attempts
        if profile.verificationAttempts >= config.maxVerificationAttempts {
            throw AgeAssuranceError.maxAttemptsExceeded
        }
        
        // Update profile
        profile.verificationStatus = AMENAgeVerificationStatus.pending
        profile.verificationAttempts += 1
        profile.lastVerificationAttempt = Date()
        profile.updatedAt = Date()
        
        // Save to Firestore
        try await db.collection("users")
            .document(userId)
            .collection("private")
            .document("age_assurance")
            .setData(try Firestore.Encoder().encode(profile))
        
        // Log event
        try await logVerificationEvent(
            AgeVerificationEvent(
                userId: userId,
                eventType: .verificationRequested,
                method: method,
                success: true
            )
        )
        
        // Invalidate cache
        ageProfileCache.removeValue(forKey: userId)
        
        dlog("📋 Age verification requested for user \(userId): \(reason)")
    }
    
    /// Update AI risk score (background detection)
    func updateAIRiskScore(userId: String, score: Double) async throws {
        var profile = try await getAgeProfile(userId: userId)
        
        let previousScore = profile.aiRiskScore
        profile.aiRiskScore = score
        profile.updatedAt = Date()
        
        // If score crosses threshold, trigger verification
        if score > config.aiRiskThreshold && previousScore <= config.aiRiskThreshold {
            profile.verificationStatus = AMENAgeVerificationStatus.flagged
            
            try await logVerificationEvent(
                AgeVerificationEvent(
                    userId: userId,
                    eventType: .aiFlagged,
                    success: true
                )
            )
            
            dlog("🚨 AI flagged user \(userId) as potentially underage (score: \(score))")
        }
        
        // Save to Firestore
        try await db.collection("users")
            .document(userId)
            .collection("private")
            .document("age_assurance")
            .setData(try Firestore.Encoder().encode(profile))
        
        // Invalidate cache
        ageProfileCache.removeValue(forKey: userId)
    }
    
    /// Handle age change request (triggers verification for teen→adult)
    func requestAgeChange(
        userId: String,
        newDateOfBirth: Date
    ) async throws {
        let profile = try await getAgeProfile(userId: userId)
        
        let oldAge = profile.age
        let newAge = Calendar.current.dateComponents([.year], from: newDateOfBirth, to: Date()).year ?? 0
        
        // Validate new age
        guard newAge >= AppConfig.Legal.minimumAge else {
            throw AgeAssuranceError.underMinimumAge(minimum: AppConfig.Legal.minimumAge, actual: newAge)
        }
        
        // If changing from teen to adult, require verification
        if oldAge < 18 && newAge >= 18 {
            try await requestVerification(
                userId: userId,
                reason: "Age change from \(oldAge) to \(newAge)",
                method: .governmentID
            )
            throw AgeAssuranceError.verificationRequired
        }
        
        // Otherwise allow change
        // CRITICAL-2 FIX: Update the stored DOB so the computed age property stays
        // consistent with the tier. Previously this was commented out because
        // dateOfBirth was `let`; it is now `var` in UserAgeProfile.
        var updatedProfile = profile
        updatedProfile.dateOfBirth = newDateOfBirth
        // Recompute tier from the updated DOB rather than hardcoding 18 as the only threshold.
        if newAge < AppConfig.Legal.minimumAge {
            updatedProfile.tier = .underMinimum
        } else if newAge < 18 {
            updatedProfile.tier = .teen
        } else {
            updatedProfile.tier = .adult
        }
        updatedProfile.updatedAt = Date()
        
        try await db.collection("users")
            .document(userId)
            .collection("private")
            .document("age_assurance")
            .setData(try Firestore.Encoder().encode(updatedProfile))
        
        // Log event
        try await logVerificationEvent(
            AgeVerificationEvent(
                userId: userId,
                eventType: .ageChanged,
                previousTier: profile.tier,
                newTier: updatedProfile.tier
            )
        )
        
        // Invalidate cache
        ageProfileCache.removeValue(forKey: userId)
        
        dlog("✅ Age changed for user \(userId): \(oldAge) → \(newAge)")
    }
    
    /// Log feature block event (for analytics)
    func logFeatureBlocked(
        userId: String,
        feature: AgeRestrictedFeature
    ) async {
        do {
            try await logVerificationEvent(
                AgeVerificationEvent(
                    userId: userId,
                    eventType: .featureBlocked,
                    success: false,
                    failureReason: "Blocked: \(feature)"
                )
            )
        } catch {
            dlog("⚠️ Failed to log feature block: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func logVerificationEvent(_ event: AgeVerificationEvent) async throws {
        // Store in Firestore age_verification_events collection for audit trail
        try await db.collection("age_verification_events")
            .document(UUID().uuidString)
            .setData(try Firestore.Encoder().encode(event))
    }
    
    /// Clear cache (called on sign-out)
    func clearCache() {
        ageProfileCache.removeAll()
        // Reset to .teen (restricted) rather than .adult so the next signed-in
        // user always loads their real tier before gaining adult feature access.
        currentUserTier = .teen
        currentUserAge = 0
        needsVerification = false
    }
}

// MARK: - Age Assurance Errors

enum AgeAssuranceError: LocalizedError, Equatable {
    case profileNotFound
    case underMinimumAge(minimum: Int, actual: Int)
    case verificationRequired
    case verificationCooldown(remainingSeconds: Int)
    case maxAttemptsExceeded
    case invalidDateOfBirth
    
    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Age profile not found. Please contact support."
        case .underMinimumAge(let minimum, let actual):
            return "You must be at least \(minimum) years old to use AMEN. You are \(actual) years old."
        case .verificationRequired:
            return "Age verification required. Please verify your age to continue."
        case .verificationCooldown(let remaining):
            let hours = remaining / 3600
            return "Please wait \(hours) hours before requesting verification again."
        case .maxAttemptsExceeded:
            return "Maximum verification attempts exceeded. Please contact support."
        case .invalidDateOfBirth:
            return "Invalid date of birth. Please enter a valid date."
        }
    }
}

// MARK: - Age Tier Extension

extension AMENAgeAssuranceTier {
    func canAccess(feature: AgeRestrictedFeature) -> Bool {
        switch feature {
        case .directMessages:
            return self.canAccessDMs
        case .publicProfile:
            return self != .underMinimum
        case .sensitiveContent, .commerce, .liveStreaming:
            return self == .adult
        case .bereanAI:
            // COPPA: Berean AI requires minimum age (13+); block underMinimum users.
            return self != .underMinimum
        }
    }
}

// MARK: - Age Gating View Modifier

import SwiftUI

struct AgeGatedModifier: ViewModifier {
    let feature: AgeRestrictedFeature
    
    @StateObject private var ageService = AgeAssuranceService.shared
    @State private var canAccess: Bool = false
    @State private var showBlockedAlert: Bool = false
    
    func body(content: Content) -> some View {
        content
            .task {
                canAccess = await ageService.canAccess(feature: feature)
            }
            .onChange(of: ageService.currentUserTier) { _, _ in
                Task {
                    canAccess = await ageService.canAccess(feature: feature)
                }
            }
            .disabled(!canAccess)
            .opacity(canAccess ? 1.0 : 0.5)
            .overlay {
                if !canAccess {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showBlockedAlert = true
                            Task {
                                if let userId = Auth.auth().currentUser?.uid {
                                    await ageService.logFeatureBlocked(userId: userId, feature: feature)
                                }
                            }
                        }
                }
            }
            .alert("Feature Restricted", isPresented: $showBlockedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(getBlockedMessage())
            }
    }
    
    private func getBlockedMessage() -> String {
        switch feature {
        case .directMessages:
            return "Direct messaging is only available for users 18 and older."
        case .publicProfile:
            return "You must be at least \(AppConfig.Legal.minimumAge) to have a public profile."
        case .sensitiveContent:
            return "This content is only available for users 18 and older."
        case .commerce:
            return "Commerce features are only available for users 18 and older."
        case .liveStreaming:
            return "Live streaming is only available for users 18 and older."
        case .bereanAI:
            return "Berean AI is only available for users \(AppConfig.Legal.minimumAge) and older."
        }
    }
}

extension View {
    func ageGated(feature: AgeRestrictedFeature) -> some View {
        modifier(AgeGatedModifier(feature: feature))
    }
}
