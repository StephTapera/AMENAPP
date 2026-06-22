// RememberedAccount.swift
// AMENAPP
//
// Non-sensitive display hint stored on-device for the Smart Account Resume screen.
// Contains ONLY name, avatar URL, and provider metadata — never passwords or tokens.

import Foundation

struct RememberedAccount: Codable, Identifiable, Equatable {
    let uid: String
    var displayName: String
    var avatarURL: String?
    var username: String?
    var providerType: String?
    var lastLoginAt: Date
    var isLastActiveAccount: Bool

    var id: String { uid }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    var avatarCacheURL: URL? {
        avatarURL.flatMap { URL(string: $0) }
    }

    var providerDisplayName: String? {
        switch providerType {
        case "google.com":  return "Google"
        case "apple.com":   return "Apple"
        case "phone":       return "Phone"
        case "password":    return "Email"
        default:            return nil
        }
    }
}
