// NotifPrefs.swift
// AMENAPP — Settings
//
// Persists per-action notification style overrides and injects them into
// NotificationCoordinator so the engine honours user preferences.
//
// Conformance: NotifPrefsProtocol (defined in Notifications/Engine/NotificationCoordinator.swift)
// Injection:   NotificationCoordinator.shared.prefs = NotifPrefs.shared  (done in init)
//
// Persistence: overrides dict is JSON-encoded and stored under the
//              "NotifPrefs.styles" UserDefaults key via @AppStorage.

import SwiftUI

// MARK: - NotifStyleOverride + RawRepresentable

// NotifStyleOverride is defined in NotificationCoordinator.swift (Agent B).
// We extend it here to add Codable / RawRepresentable support so it can be
// persisted without touching the Engine files.

extension NotifStyleOverride: RawRepresentable {
    public typealias RawValue = String

    public init?(rawValue: String) {
        switch rawValue {
        case "smart":      self = .smart
        case "alwaysCard": self = .alwaysCard
        case "toastOnly":  self = .toastOnly
        case "off":        self = .off
        default:           return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .smart:      return "smart"
        case .alwaysCard: return "alwaysCard"
        case .toastOnly:  return "toastOnly"
        case .off:        return "off"
        }
    }
}

// Codable conformance via the RawRepresentable bridge above.
extension NotifStyleOverride: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = NotifStyleOverride(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown NotifStyleOverride rawValue: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - NotifPrefs

/// Observable store for per-action notification style preferences.
///
/// - Persists to `UserDefaults` via `@AppStorage` (JSON-encoded dict).
/// - Conforms to `NotifPrefsProtocol` and self-injects into
///   `NotificationCoordinator.shared.prefs` on first access.
/// - All mutations are performed on the `@MainActor`.
@MainActor
final class NotifPrefs: ObservableObject, NotifPrefsProtocol {

    // MARK: - Singleton

    static let shared = NotifPrefs()

    // MARK: - Persistence backing

    /// Raw JSON storage — [AmenAction.rawValue: NotifStyleOverride.rawValue]
    @AppStorage("NotifPrefs.styles") private var stored: Data = Data()

    // MARK: - In-memory overrides

    /// Live copy kept in memory; written back to `stored` on every mutation.
    private var overrides: [String: NotifStyleOverride] = [:] {
        didSet { persist() }
    }

    // MARK: - Init

    private init() {
        load()
        // Inject into the coordinator so engine honours user prefs immediately.
        NotificationCoordinator.shared.prefs = self
    }

    // MARK: - NotifPrefsProtocol

    /// Returns the user's preferred display style for `action`.
    /// Defaults to `.smart` when no override has been set.
    func style(for action: AmenAction) -> NotifStyleOverride {
        overrides[action.rawValue] ?? .smart
    }

    // MARK: - Mutation

    /// Persists a style choice for the given action and notifies SwiftUI observers.
    func set(_ style: NotifStyleOverride, for action: AmenAction) {
        overrides[action.rawValue] = style
        objectWillChange.send()
    }

    // MARK: - Private persistence helpers

    private func persist() {
        // Flatten to [String: String] for JSON compatibility.
        let flat = overrides.mapValues(\.rawValue)
        if let data = try? JSONEncoder().encode(flat) {
            stored = data
        }
    }

    private func load() {
        guard !stored.isEmpty,
              let flat = try? JSONDecoder().decode([String: String].self, from: stored)
        else { return }

        // Reconstruct overrides, silently dropping any stale / unknown keys.
        overrides = flat.compactMapValues { NotifStyleOverride(rawValue: $0) }
    }
}

// MARK: - AmenAction + displayName

extension AmenAction {
    /// User-facing display name used throughout Settings and accessibility labels.
    var displayName: String {
        switch self {
        case .amen:   return "Amen"
        case .repost: return "Repost"
        case .save:   return "Save"
        case .join:   return "Join Sanctuary"
        case .give:   return "Give"
        }
    }
}
