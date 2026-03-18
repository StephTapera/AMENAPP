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

    init(id: String, displayName: String, username: String, profilePhotoURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.username = username
        self.profilePhotoURL = profilePhotoURL
    }
}
