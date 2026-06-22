//
//  SelahVerseEngagements.swift
//  AMENAPP
//
//  Private verse-level engagement signals: reactions and "Prayed through this"
//  markers. Both are local-only by default (UserDefaults). A future Firestore
//  sync layer can mirror these via `SelahSavedScriptureFirestoreService`.
//
//  Design rules:
//   * Private by default — never shared without an explicit user action.
//   * Calm, not gamified: reactions are emotional, not numeric.
//   * Per-verse, indexed by (translationId, bookId, chapter, verseNumber).
//

import Foundation
import SwiftUI
import CryptoKit
import Security

// MARK: - Reactions

enum SelahVerseReactionKind: String, CaseIterable, Codable, Identifiable {
    case amen
    case convicted
    case encouraged
    case peace
    case hope
    case wisdom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .amen:       return "Amen"
        case .convicted:  return "Convicted"
        case .encouraged: return "Encouraged"
        case .peace:      return "Peace"
        case .hope:       return "Hope"
        case .wisdom:     return "Wisdom"
        }
    }

    var icon: String {
        switch self {
        case .amen:       return "hands.sparkles.fill"
        case .convicted:  return "heart.fill"
        case .encouraged: return "sun.max.fill"
        case .peace:      return "leaf.fill"
        case .hope:       return "sparkle"
        case .wisdom:     return "book.closed.fill"
        }
    }

    var tone: SelahHighlightTone {
        switch self {
        case .amen:       return .prayer
        case .convicted:  return .faith
        case .encouraged: return .hope
        case .peace:      return .peace
        case .hope:       return .hope
        case .wisdom:     return .wisdom
        }
    }
}

struct SelahVerseReactionEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let reference: SelahScriptureReference
    let translationId: String
    let kind: SelahVerseReactionKind
    let createdAt: Date

    init(id: UUID = UUID(),
         reference: SelahScriptureReference,
         translationId: String,
         kind: SelahVerseReactionKind,
         createdAt: Date = Date()) {
        self.id = id
        self.reference = reference
        self.translationId = translationId
        self.kind = kind
        self.createdAt = createdAt
    }
}

// MARK: - Prayed Through

struct SelahPrayedThroughEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let reference: SelahScriptureReference
    let translationId: String
    let note: String?
    let createdAt: Date

    init(id: UUID = UUID(),
         reference: SelahScriptureReference,
         translationId: String,
         note: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.reference = reference
        self.translationId = translationId
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Engagement Store

@MainActor
final class SelahVerseEngagementStore: ObservableObject {
    static let shared = SelahVerseEngagementStore()

    @Published private(set) var reactions: [SelahVerseReactionEntry] = []
    @Published private(set) var prayedThrough: [SelahPrayedThroughEntry] = []

    private let defaults: UserDefaults
    private let reactionsKey = "selah.engagement.reactions.v1"
    private let prayedKey = "selah.engagement.prayedThrough.v1"

    // NG-3 / C-2 remediation (2026-06-19): free-text prayer notes are sensitive
    // spiritual reflection. They were stored in plaintext UserDefaults; they are now
    // encrypted (AES-GCM, Keychain-held key) and written to file-protected storage.
    private let symmetricKey: SymmetricKey
    private let reactionsFileURL: URL
    private let prayedFileURL: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let dir = SelahVerseEngagementStore.storageDirectory()
        self.reactionsFileURL = dir.appendingPathComponent("selah_reactions.enc")
        self.prayedFileURL = dir.appendingPathComponent("selah_prayed.enc")
        self.symmetricKey = SelahVerseEngagementStore.loadOrCreateKey()

        var migrated = false
        // Preferred: encrypted, file-protected store.
        if let decoded: [SelahVerseReactionEntry] =
            SelahVerseEngagementStore.decryptedLoad(reactionsFileURL, key: symmetricKey) {
            self.reactions = decoded
        } else if let data = defaults.data(forKey: reactionsKey),
                  let decoded = try? JSONDecoder().decode([SelahVerseReactionEntry].self, from: data) {
            // Migrate legacy plaintext blob, then scrub it.
            self.reactions = decoded
            defaults.removeObject(forKey: reactionsKey)
            migrated = true
        }
        if let decoded: [SelahPrayedThroughEntry] =
            SelahVerseEngagementStore.decryptedLoad(prayedFileURL, key: symmetricKey) {
            self.prayedThrough = decoded
        } else if let data = defaults.data(forKey: prayedKey),
                  let decoded = try? JSONDecoder().decode([SelahPrayedThroughEntry].self, from: data) {
            self.prayedThrough = decoded
            defaults.removeObject(forKey: prayedKey)
            migrated = true
        }
        if migrated {
            persistReactions()
            persistPrayed()
        }
    }

    // MARK: Reactions

    func reactions(for reference: SelahScriptureReference, translationId: String) -> [SelahVerseReactionEntry] {
        reactions.filter { $0.reference == reference && $0.translationId == translationId }
    }

    func addReaction(_ kind: SelahVerseReactionKind,
                     to reference: SelahScriptureReference,
                     translationId: String) {
        // Idempotent — adding the same reaction twice is a no-op.
        if reactions.contains(where: {
            $0.reference == reference && $0.translationId == translationId && $0.kind == kind
        }) { return }
        let entry = SelahVerseReactionEntry(reference: reference, translationId: translationId, kind: kind)
        reactions.append(entry)
        persistReactions()
    }

    func removeReaction(_ kind: SelahVerseReactionKind,
                        from reference: SelahScriptureReference,
                        translationId: String) {
        reactions.removeAll {
            $0.reference == reference && $0.translationId == translationId && $0.kind == kind
        }
        persistReactions()
    }

    // MARK: Prayed Through

    func hasPrayedThrough(_ reference: SelahScriptureReference, translationId: String) -> Bool {
        prayedThrough.contains { $0.reference == reference && $0.translationId == translationId }
    }

    func togglePrayedThrough(_ reference: SelahScriptureReference,
                              translationId: String,
                              note: String? = nil) {
        if hasPrayedThrough(reference, translationId: translationId) {
            prayedThrough.removeAll {
                $0.reference == reference && $0.translationId == translationId
            }
        } else {
            prayedThrough.append(
                SelahPrayedThroughEntry(reference: reference, translationId: translationId, note: note)
            )
        }
        persistPrayed()
    }

    // MARK: Persistence

    private func persistReactions() {
        SelahVerseEngagementStore.encryptedSave(reactions, to: reactionsFileURL, key: symmetricKey)
    }

    private func persistPrayed() {
        SelahVerseEngagementStore.encryptedSave(prayedThrough, to: prayedFileURL, key: symmetricKey)
    }

    // MARK: - Encrypted storage helpers

    private static func storageDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SelahEngagement", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func decryptedLoad<T: Decodable>(_ url: URL, key: SymmetricKey) -> T? {
        guard let data = try? Data(contentsOf: url),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: plain)
    }

    private static func encryptedSave<T: Encodable>(_ value: T, to url: URL, key: SymmetricKey) {
        guard let plain = try? JSONEncoder().encode(value),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? sealed.write(to: url, options: [.atomic, .completeFileProtection])
    }

    // MARK: Keychain key (device-only)

    private static let keychainAccount = "amen.selahEngagements.keySeed"

    private static func loadOrCreateKey() -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(loadOrCreateSeed().utf8)))
    }

    private static func loadOrCreateSeed() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let seed = String(data: data, encoding: .utf8) {
            return seed
        }
        let newSeed = UUID().uuidString
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = Data(newSeed.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
        return newSeed
    }
}

// MARK: - Reaction Picker Sheet

struct SelahVerseReactionPickerSheet: View {

    let reference: SelahScriptureReference
    let translationId: String
    @ObservedObject var store: SelahVerseEngagementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("React to")
                        .font(.systemScaled(10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text(reference.displayString)
                        .font(.systemScaled(16, weight: .semibold))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(SelahVerseReactionKind.allCases) { kind in
                    let selected = store
                        .reactions(for: reference, translationId: translationId)
                        .contains { $0.kind == kind }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if selected {
                            store.removeReaction(kind, from: reference, translationId: translationId)
                        } else {
                            store.addReaction(kind, to: reference, translationId: translationId)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.icon)
                                .font(.systemScaled(18, weight: .medium))
                                .foregroundStyle(selected ? Color.accentColor : .primary.opacity(0.8))
                            Text(kind.label)
                                .font(.systemScaled(11, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selected ? kind.tone.fill : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    selected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.label) reaction")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

            Text("Private to you unless you share it.")
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(20)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}
