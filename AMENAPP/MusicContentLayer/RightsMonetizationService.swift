// RightsMonetizationService.swift
// AMENAPP — MusicContentLayer
//
// Rights enforcement, access policy checks, and monetization display helpers.
// Works on raw String policy values matching MusicContentContracts raw values.
// No payment processing in v1 — policy-check only.

import SwiftUI

// MARK: - Access Result

enum ContentAccessResult: Sendable {
    case granted
    case denied(reason: ContentAccessDeniedReason)
}

enum ContentAccessDeniedReason: String, Sendable {
    case paidRequired, membershipRequired, childRestricted
    case pendingModeration, blocked, privateContent, adminOnly, regionRestricted

    var shortLabel: String {
        switch self {
        case .paidRequired:       return "Paid content"
        case .membershipRequired: return "Members only"
        case .childRestricted:    return "Age restricted"
        case .pendingModeration:  return "Under review"
        case .blocked:            return "Blocked"
        case .privateContent:     return "Private"
        case .adminOnly:          return "Admins only"
        case .regionRestricted:   return "Not available in your region"
        }
    }

    var icon: String {
        switch self {
        case .paidRequired:       return "dollarsign.circle.fill"
        case .membershipRequired: return "star.circle.fill"
        case .childRestricted:    return "shield.fill"
        case .pendingModeration:  return "clock.fill"
        case .blocked:            return "slash.circle.fill"
        case .privateContent:     return "lock.fill"
        case .adminOnly:          return "person.badge.shield.checkmark.fill"
        case .regionRestricted:   return "globe"
        }
    }
}

// MARK: - Rights Check Input

struct RightsCheckInput: Sendable {
    let contentID: String
    let rightsPolicy: String       // raw value from RightsPolicy enum
    let visibilityPolicy: String   // raw value from VisibilityPolicy enum
    let moderationStatus: String   // raw value from MusicContentModerationStatus enum
    let isChildAccount: Bool
    let hasActiveMembership: Bool
    let hasPaidAccess: Bool
    let isAdmin: Bool
}

// MARK: - Music Platform Rulings
// These constants encode the standing music policy decisions for AMEN.
// Enforced by RightsMonetizationService — DO NOT bypass.

enum MusicPlatformRuling {
    /// MusicKit (Apple Music) is the PRIMARY licensed catalog source.
    /// Stream-only via MusicKit API — no download, no offline cache, no lyrics storage.
    static let musicKitPolicy: String = "stream_only"

    /// Spotify content may only be surface-linked (unfurl card showing artwork/title).
    /// No audio preview, no embed, no stream through AMEN player.
    static let spotifyPolicy: String = "unfurl_only"

    /// Lyrics are NEVER displayed, stored, cached, or transmitted by AMEN.
    /// Attempting to display lyrics requires a separate sync license — none exists in v1.
    static let lyricsPolicy: String = "never_display"

    /// Licensed content (any content with `rightsPolicy == "licensed"`) is display-only:
    /// artwork + title + artist + duration. No download, no stream, no lyrics.
    static let licensedDisplayPolicy: String = "display_only"

    /// Verified Clean tracks may be previewed via MusicKit 30s preview URL only.
    /// Full streams require active MusicKit subscription.
    static let verifiedCleanPreviewPolicy: String = "preview_30s_only"
}

// MARK: - Service
// @unchecked Sendable: no mutable stored state.

final class RightsMonetizationService: @unchecked Sendable {

    func checkAccess(_ input: RightsCheckInput) -> ContentAccessResult {
        let mod = input.moderationStatus
        let rights = input.rightsPolicy
        let vis = input.visibilityPolicy

        // 1. Blocked / removed — always denied
        if mod == "blocked" || mod == "removed" { return .denied(reason: .blocked) }

        // 2. Pending review — denied unless admin
        if (mod == "pending" || mod == "pending_review" || mod == "under_review"), !input.isAdmin {
            return .denied(reason: .pendingModeration)
        }

        // 3. Admin-only rights — denied unless admin
        if rights == "admin_only" || rights == "adminOnly", !input.isAdmin {
            return .denied(reason: .adminOnly)
        }

        // 4. Private visibility — denied unless admin (used as creator proxy in v1)
        if vis == "private", !input.isAdmin { return .denied(reason: .privateContent) }

        // 5. Members-only visibility — denied without membership
        if (vis == "members_only" || vis == "membersOnly"), !input.hasActiveMembership {
            return .denied(reason: .membershipRequired)
        }

        // 6. Paid rights — denied without paid access
        if rights == "paid", !input.hasPaidAccess { return .denied(reason: .paidRequired) }

        // 7. Members-only rights — denied without membership
        if (rights == "member_only" || rights == "memberOnly" || rights == "members_only"), !input.hasActiveMembership {
            return .denied(reason: .membershipRequired)
        }

        // 8. Child-restricted — denied for child accounts
        if (rights == "child_restricted" || rights == "childRestricted"), input.isChildAccount {
            return .denied(reason: .childRestricted)
        }

        // 9. Region-restricted — always denied in v1 (no geo-check)
        if rights == "region_restricted" || rights == "regionRestricted" {
            return .denied(reason: .regionRestricted)
        }

        return .granted
    }

    /// Returns false if the requested action violates platform rulings.
    /// Always call this before attempting audio playback or lyrics display.
    func checkMusicPlatformCompliance(attachmentType: String, requestedAction: String) -> Bool {
        switch requestedAction {
        case "display_lyrics", "cache_lyrics", "store_lyrics":
            return false // MusicPlatformRuling.lyricsPolicy = "never_display"
        case "spotify_stream", "spotify_embed", "spotify_preview":
            return false // MusicPlatformRuling.spotifyPolicy = "unfurl_only"
        case "download", "offline_cache":
            return false // No offline rights in v1
        case "stream":
            // Only allowed for MusicKit-backed content
            return attachmentType == "musickit" || attachmentType == "song"
        default:
            return true
        }
    }

    /// Returns a display label, tint color, and SF Symbol for a visibility/rights policy string.
    func visibilityBadge(for policy: String) -> (label: String, color: Color, icon: String) {
        switch policy {
        case "public":                          return ("Public",    .green,    "globe")
        case "private":                         return ("Private",   .secondary,"lock.fill")
        case "members_only", "membersOnly":     return ("Members",   .purple,   "star.fill")
        case "unlisted":                        return ("Unlisted",  .orange,   "eye.slash.fill")
        case "child_safe", "childSafe":         return ("Kids Safe", .blue,     "shield.fill")
        case "admin_only", "adminOnly":         return ("Admin",     .red,      "person.badge.shield.checkmark.fill")
        case "community_only", "communityOnly": return ("Community", .blue,     "person.3.fill")
        default:                                return ("Public",    .green,    "globe")
        }
    }

    /// Returns a short human-readable label for a rights/monetization policy string.
    func monetizationLabel(for policy: String) -> String {
        switch policy {
        case "free":                            return "Free"
        case "paid":                            return "Paid"
        case "member_only", "memberOnly",
             "members_only", "membersOnly":     return "Members Only"
        case "donation_supported":              return "Donation"
        case "licensed":                        return "Licensed"
        case "stream_only", "streamOnly":       return "Stream Only"
        case "downloadable":                    return "Download"
        case "private":                         return "Private"
        case "unlisted":                        return "Unlisted"
        case "restricted":                      return "Restricted"
        case "pending_review", "pendingReview": return "Pending Review"
        case "admin_only", "adminOnly":         return "Admin Only"
        case "child_restricted":                return "Age Restricted"
        default:                                return "Free"
        }
    }
}

// MARK: - MonetizationStatusPill

struct MonetizationStatusPill: View {
    let policy: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let service = RightsMonetizationService()

    var body: some View {
        let badge = service.visibilityBadge(for: policy)
        HStack(spacing: 4) {
            Image(systemName: badge.icon).font(.system(size: 10, weight: .semibold))
            Text(badge.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(badge.color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if reduceTransparency {
                Capsule().fill(badge.color.opacity(0.12))
            } else {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(badge.color.opacity(0.10))
                    .overlay(Capsule().stroke(badge.color.opacity(0.25), lineWidth: 1))
            }
        }
        .shadow(color: badge.color.opacity(0.08), radius: 3, y: 1)
        .accessibilityLabel("Visibility: \(badge.label)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - ResourceAccessBadge

struct ResourceAccessBadge: View {
    let accessResult: ContentAccessResult
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch accessResult {
        case .granted:
            EmptyView()
        case .denied(let reason):
            HStack(spacing: 5) {
                Image(systemName: reason.icon).font(.system(size: 11, weight: .semibold))
                Text(reason.shortLabel).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(.secondarySystemBackground))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Color.white.opacity(0.04))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .accessibilityLabel("Access restricted: \(reason.shortLabel)")
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Preview

#Preview("Rights & Monetization") {
    let service = RightsMonetizationService()
    let cases: [(String, RightsCheckInput)] = [
        ("Free + Public",          RightsCheckInput(contentID: "c1", rightsPolicy: "free",        visibilityPolicy: "public",      moderationStatus: "approved",     isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Paid – no access",       RightsCheckInput(contentID: "c2", rightsPolicy: "paid",        visibilityPolicy: "public",      moderationStatus: "approved",     isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Members only",           RightsCheckInput(contentID: "c3", rightsPolicy: "member_only", visibilityPolicy: "members_only",moderationStatus: "approved",     isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Pending – not admin",    RightsCheckInput(contentID: "c4", rightsPolicy: "free",        visibilityPolicy: "public",      moderationStatus: "pending",      isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Blocked",                RightsCheckInput(contentID: "c5", rightsPolicy: "free",        visibilityPolicy: "public",      moderationStatus: "blocked",      isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: false)),
        ("Admin bypass pending",   RightsCheckInput(contentID: "c6", rightsPolicy: "free",        visibilityPolicy: "public",      moderationStatus: "pending",      isChildAccount: false, hasActiveMembership: false, hasPaidAccess: false, isAdmin: true)),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monetization Pills").font(.headline).padding(.horizontal)
            HStack(spacing: 8) {
                MonetizationStatusPill(policy: "public")
                MonetizationStatusPill(policy: "private")
                MonetizationStatusPill(policy: "members_only")
                MonetizationStatusPill(policy: "paid")
            }.padding(.horizontal)
            Divider()
            Text("Access Badge Examples").font(.headline).padding(.horizontal)
            ForEach(cases, id: \.0) { label, input in
                let result = service.checkAccess(input)
                HStack {
                    Text(label).font(.subheadline)
                    Spacer()
                    ResourceAccessBadge(accessResult: result)
                    if case .granted = result {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Granted")
                    }
                }.padding(.horizontal)
            }
        }.padding(.vertical, 20)
    }.background(Color(.systemGroupedBackground))
}
