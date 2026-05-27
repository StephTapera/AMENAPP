import Foundation
import UIKit

// MARK: - Pending Share Draft model

/// Serialized by the Share Extension, consumed by the main app on `amen://draft/from-share`.
public struct PendingShareDraft: Codable {
    public let id: String
    public let createdAt: Date
    public let text: String?
    public let url: URL?
    public let imageRelativePaths: [String]
    public let sourceBundleId: String?

    /// Resolves relative image paths against the App Group container.
    /// Files are moved to the main app's temp directory by `PendingDraftLoader.consume()`.
    public var resolvedImageURLs: [URL] {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PendingDraftLoader.suiteName)
        else { return [] }
        return imageRelativePaths.compactMap { path in
            let url = container.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }
}

// MARK: - Loader

/// One-shot reader for the draft written by the Share Extension into the App Group.
/// Calling `consume()` reads, moves image files, then deletes the draft — safe to call once.
@MainActor
public enum PendingDraftLoader {

    // MARK: - PUBLIC INTERFACE

    static let suiteName = "group.com.amenapp.shared"
    private static let defaultsKey = "pendingShareDraft"

    /// Returns the pending draft (if any) and clears it from shared storage.
    /// Images are moved from the App Group container to the app's temp directory.
    public static func consume() -> PendingShareDraft? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }

        let draft = try? JSONDecoder().decode(PendingShareDraft.self, from: data)
        defaults.removeObject(forKey: defaultsKey)
        defaults.synchronize()

        if let draft {
            moveImages(for: draft)
        }
        return draft
    }

    /// Returns true if there is a pending draft without consuming it.
    public static func hasDraft() -> Bool {
        UserDefaults(suiteName: suiteName)?.data(forKey: defaultsKey) != nil
    }

    // MARK: - Private

    private static func moveImages(for draft: PendingShareDraft) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)
        else { return }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareExtensionImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for path in draft.imageRelativePaths {
            let source = container.appendingPathComponent(path)
            let dest = tmpDir.appendingPathComponent(source.lastPathComponent)
            // Move; if move fails (e.g. across volumes), copy + delete.
            if (try? FileManager.default.moveItem(at: source, to: dest)) == nil {
                try? FileManager.default.copyItem(at: source, to: dest)
                try? FileManager.default.removeItem(at: source)
            }
        }
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let amenOpenShareDraft = Notification.Name("amenOpenShareDraft")
}
