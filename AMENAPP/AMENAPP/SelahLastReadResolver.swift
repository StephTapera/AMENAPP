import Foundation

struct SelahLastReadEntry: Equatable {
    let reference: String
    let sessionTitle: String
    let sessionId: String?
}

enum SelahLastReadResolver {
    static func resolve(
        sessions: [SelahSession],
        excluding excludedReferences: [String] = [],
        now: Date = Date(),
        maxAge: TimeInterval = 30 * 24 * 60 * 60
    ) -> SelahLastReadEntry? {
        let excluded = Set(excludedReferences.map(normalize))

        return sessions
            .filter { now.timeIntervalSince($0.createdAt) <= maxAge }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { session -> SelahLastReadEntry? in
                guard let rawReference = session.scriptureRefs.first,
                      let reference = trimmed(rawReference),
                      !excluded.contains(normalize(reference)) else {
                    return nil
                }
                let title = trimmed(session.title) ?? reference
                return SelahLastReadEntry(reference: reference, sessionTitle: title, sessionId: session.id)
            }
            .first
    }

    private static func trimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
