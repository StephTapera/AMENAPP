// ExperienceResolverService.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// Priority-stack resolver for the contextual experience layer.
// Calls `resolveContextualExperienceStack` CF with the current user's org
// membership and region, then caches the result for 5 minutes.
//
// Constraints:
//   - @MainActor throughout
//   - No Combine — async/await + @Published
//   - No force-unwrap
//   - Falls back to .defaultResolved on ANY error — never throws to callers
//   - NEVER log prayer content or user PII

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - ExperienceResolverService

@MainActor
final class ExperienceResolverService: ObservableObject {

    static let shared = ExperienceResolverService()

    @Published private(set) var resolved: ResolvedExperience = .defaultResolved
    @Published private(set) var isResolving: Bool = false
    @Published private(set) var lastError: Error?

    private let functions = Functions.functions(region: "us-central1")

    /// Cache fields
    private var cachedResolved: ResolvedExperience?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 5 * 60  // 5 minutes

    private init() {}

    // MARK: - Public API

    /// Resolves the contextual experience stack for the current user.
    ///
    /// - If a fresh cache exists (< 5 min old) the cached value is used and no
    ///   network call is made.
    /// - On CF error the resolved state falls back to `.defaultResolved` and the
    ///   error is surfaced via `lastError` — this method never throws.
    func resolve(organizationIds: [String], region: String) async {
        if let cached = cachedResolved,
           let stamp = cacheTimestamp,
           Date().timeIntervalSince(stamp) < cacheTTL {
            resolved = cached
            dlog("ExperienceResolverService: served from cache")
            return
        }

        await fetchAndApply(organizationIds: organizationIds, region: region)
    }

    /// Forces a cache invalidation then immediately resolves.
    /// Call on app foreground or when org membership changes.
    func invalidateAndResolve(organizationIds: [String], region: String) async {
        cachedResolved = nil
        cacheTimestamp = nil
        await fetchAndApply(organizationIds: organizationIds, region: region)
    }

    // MARK: - Private

    private func fetchAndApply(organizationIds: [String], region: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            dlog("ExperienceResolverService: not authenticated, using default")
            resolved = .defaultResolved
            return
        }

        isResolving = true
        lastError = nil

        defer { isResolving = false }

        let payload: [String: Any] = [
            "userId": uid,
            "orgIds": organizationIds,
            "region": region
        ]

        do {
            let callable = functions.httpsCallable("resolveContextualExperienceStack")
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any] else {
                dlog("ExperienceResolverService: invalid response shape, falling back to default")
                resolved = .defaultResolved
                return
            }

            let parsed = parseResolvedExperience(from: data)
            cachedResolved = parsed
            cacheTimestamp = Date()
            resolved = parsed
            dlog("ExperienceResolverService: resolved layer=\(parsed.sourceLayer.rawValue) expId=\(parsed.activeExperienceId ?? "nil")")
        } catch {
            dlog("ExperienceResolverService: resolve error — \(error.localizedDescription) — using default")
            lastError = error
            resolved = .defaultResolved
        }
    }

    /// Parses the CF response dictionary into a `ResolvedExperience`.
    /// Falls back to `.defaultResolved` for any missing or malformed fields.
    private func parseResolvedExperience(from data: [String: Any]) -> ResolvedExperience {
        let activeExperienceId = data["activeExperienceId"] as? String
        let sourceLayerRaw = data["sourceLayer"] as? String ?? ExperienceLayer.defaultUI.rawValue
        let sourceLayer = ExperienceLayer(rawValue: sourceLayerRaw) ?? .defaultUI
        let activeBannerTitle = data["activeBannerTitle"] as? String
        let activeBannerSubtitle = data["activeBannerSubtitle"] as? String
        let navigationAction = data["navigationAction"] as? String
        let notificationBehavior = data["notificationBehavior"] as? String ?? "normal"
        let safetyBehavior = data["safetyBehavior"] as? String ?? "standard"
        let accessibilityAdjustments = data["accessibilityAdjustments"] as? [String: Bool] ?? [:]
        let debugMetadata = data["debugMetadata"] as? [String: String]

        // Parse allowed modules
        let modulesRaw = data["allowedModules"] as? [String] ?? []
        let allowedModules = modulesRaw.isEmpty
            ? ExperienceModuleType.allCases
            : modulesRaw.compactMap { ExperienceModuleType(rawValue: $0) }

        // Parse theme tokens
        var themeTokens: ExperienceThemeConfig?
        if let themeData = data["themeTokens"] as? [String: Any],
           let accentHex = themeData["accentColorHex"] as? String {
            themeTokens = ExperienceThemeConfig(
                accentColorHex: accentHex,
                motionIntensity: themeData["motionIntensity"] as? Double ?? 0.5,
                glassOpacity: themeData["glassOpacity"] as? Double ?? 0.3,
                backgroundStyle: themeData["backgroundStyle"] as? String ?? "adaptive"
            )
        }

        // Parse secondary experiences
        let secondaryRaw = data["secondaryExperiences"] as? [[String: Any]] ?? []
        let secondary: [ResolvedExperience.SecondaryExperience] = secondaryRaw.compactMap { item in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let layerRaw = item["layer"] as? String,
                  let layer = ExperienceLayer(rawValue: layerRaw) else { return nil }
            return ResolvedExperience.SecondaryExperience(id: id, title: title, layer: layer)
        }

        return ResolvedExperience(
            activeExperienceId: activeExperienceId,
            sourceLayer: sourceLayer,
            themeTokens: themeTokens,
            allowedModules: allowedModules,
            activeBannerTitle: activeBannerTitle,
            activeBannerSubtitle: activeBannerSubtitle,
            navigationAction: navigationAction,
            notificationBehavior: notificationBehavior,
            safetyBehavior: safetyBehavior,
            accessibilityAdjustments: accessibilityAdjustments,
            secondaryExperiences: secondary,
            debugMetadata: debugMetadata
        )
    }
}
