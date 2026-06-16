//
//  HeroSurfaceAdapter.swift
//  AMENAPP
//
//  Maps AMEN's real Firestore models to AdaptiveHeroEngine's HeroSurface.
//  Pure factory functions — synchronous, no side effects, no force-unwrap.
//  Every optional field gets a typed fallback; a partial Firestore document
//  never crashes here.
//
//  Kinds wired: .creator (UserModel), .church (ChurchEntity), .space (AMENSpace)
//

import SwiftUI
import AdaptiveHeroEngine

// MARK: - Creator / User

extension HeroSurface {
    /// Build a creator hero surface from an AMEN user profile.
    /// Pass the viewer's relationship from the auth session; the adapter
    /// must not import or touch auth state itself.
    static func fromUser(
        _ user: UserModel,
        relationship: ViewerRelationship = .stranger
    ) -> HeroSurface {
        let uid = user.id ?? UUID().uuidString
        let heroURL = user.profileImageURL.flatMap { URL(string: $0) }
        return HeroSurface(
            id: uid,
            kind: .creator,
            visibility: user.isPrivate ? .followersOnly : .publicAll,
            viewerRelationship: relationship,
            title: LocalizedStringKey(user.displayName),
            subtitle: user.bio.map { LocalizedStringKey($0) },
            hero: HeroImageRef(url: heroURL, cacheKey: "user_\(uid)"),
            avatar: HeroImageRef(url: heroURL, cacheKey: "userAvatar_\(uid)"),
            badges: [],
            trust: .unverified,
            faithTags: heroFaithTags(from: user.interests),
            location: nil,
            modules: []
        )
    }
}

// MARK: - Church

extension HeroSurface {
    static func fromChurch(
        _ church: ChurchEntity,
        relationship: ViewerRelationship = .stranger
    ) -> HeroSurface {
        let heroURL = church.photoURL.flatMap { URL(string: $0) }
        let logoURL = church.logoURL.flatMap { URL(string: $0) }

        let locationParts = [church.city, church.state].compactMap { $0 }
        let locationString = locationParts.isEmpty ? nil : locationParts.joined(separator: ", ")

        let times = church.serviceTimes.map { st -> String in
            let day = heroAbbreviatedDay(for: st.dayOfWeek)
            let typeLabel = st.serviceType.map { " · \($0)" } ?? ""
            return "\(day) \(st.time)\(typeLabel)"
        }
        let links: [URL] = [church.website.flatMap { URL(string: $0) }].compactMap { $0 }
        let about = AboutInfo(
            mission: nil,
            location: church.address,
            serviceTimes: times,
            links: links
        )

        return HeroSurface(
            id: church.id,
            kind: .church,
            visibility: .publicAll,
            viewerRelationship: relationship,
            title: LocalizedStringKey(church.name),
            subtitle: church.denomination.map { LocalizedStringKey($0) },
            hero: HeroImageRef(url: heroURL, cacheKey: "church_\(church.id)"),
            avatar: logoURL.map { HeroImageRef(url: $0, cacheKey: "churchLogo_\(church.id)") },
            badges: [],
            trust: .knownInCommunity,
            faithTags: [.worship, .teaching, .prayer],
            location: locationString.map { LocalizedStringKey($0) },
            modules: [.about(about)]
        )
    }
}

// MARK: - Space

extension HeroSurface {
    static func fromSpace(
        _ space: AMENSpace,
        relationship: ViewerRelationship = .stranger
    ) -> HeroSurface {
        let sid = space.id ?? UUID().uuidString
        let heroURL = space.coverImageURL.flatMap { URL(string: $0) }
        return HeroSurface(
            id: sid,
            kind: .space,
            visibility: .publicAll,
            viewerRelationship: relationship,
            title: LocalizedStringKey(space.name),
            subtitle: LocalizedStringKey("\(space.memberCount) members"),
            hero: HeroImageRef(url: heroURL, cacheKey: "space_\(sid)"),
            avatar: nil,
            badges: [],
            trust: space.memberCount > 50 ? .knownInCommunity : .unverified,
            faithTags: heroFaithTags(from: space.aiDetectedTopics),
            location: nil,
            modules: []
        )
    }
}

// MARK: - Shared private helpers

/// Map a string array (interests / aiDetectedTopics) to known FaithTag cases.
/// Unknown strings are silently dropped — no crash, no invented tags.
private func heroFaithTags(from strings: [String]?) -> [FaithTag] {
    strings?.compactMap { FaithTag(rawValue: $0.lowercased()) } ?? []
}

/// ChurchEntity dayOfWeek convention: 1 = Sunday … 7 = Saturday.
private func heroAbbreviatedDay(for dayOfWeek: Int) -> String {
    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    let index = min(max(dayOfWeek - 1, 0), names.count - 1)
    return names[index]
}
