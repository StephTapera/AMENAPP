//
//  MutualConnection.swift
//  AMENAPP
//
//  Lightweight model for a mutual connection (someone both the viewer
//  and the profile owner follow).
//

import Foundation

struct MutualConnection: Identifiable, Equatable {
    let id: String              // Firebase UID
    let displayName: String
    let username: String
    let profilePhotoURL: URL?

    /// String-based image URL used by MutualConnectionsFeature views.
    var profileImageURL: String? { profilePhotoURL?.absoluteString }

    /// Initials derived from displayName for avatar fallback.
    var initials: String {
        let parts = displayName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }

    init(id: String, displayName: String, username: String, profilePhotoURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profilePhotoURL = profilePhotoURL
    }

    /// Convenience initializer accepting a string URL.
    init(id: String, displayName: String, username: String, profileImageURL: String?) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profilePhotoURL = profileImageURL.flatMap { URL(string: $0) }
    }
}
