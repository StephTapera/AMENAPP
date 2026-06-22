// SermonStudyPacket.swift — AMEN IntegrationOS
// SermonStudyPacket model and builder for structured sermon media outputs.

import Foundation

struct SermonStudyPacket: Codable, Identifiable {
    var id: String = UUID().uuidString
    let sermonId: String
    let title: String
    let preacher: String?
    let churchName: String?
    let recordedAt: Date?
    let scripture: [String]
    let outline: [SermonOutlinePoint]
    let keyThemes: [String]
    let discussionQuestions: [String]
    let prayerPoints: [String]
    let mediaURL: String?
    let approved: Bool
    let generatedAt: Date
}

struct SermonOutlinePoint: Codable, Identifiable {
    var id: String = UUID().uuidString
    let order: Int
    let heading: String
    let body: String
    let scripture: String?
}

// MARK: - Builder

final class SermonStudyPacketBuilder {
    private var sermonId = UUID().uuidString
    private var title = ""
    private var preacher: String?
    private var churchName: String?
    private var recordedAt: Date?
    private var scripture: [String] = []
    private var outline: [SermonOutlinePoint] = []
    private var keyThemes: [String] = []
    private var discussionQuestions: [String] = []
    private var prayerPoints: [String] = []
    private var mediaURL: String?

    @discardableResult func sermonId(_ id: String) -> Self { sermonId = id; return self }
    @discardableResult func title(_ t: String) -> Self { title = t; return self }
    @discardableResult func preacher(_ p: String?) -> Self { preacher = p; return self }
    @discardableResult func church(_ c: String?) -> Self { churchName = c; return self }
    @discardableResult func recordedAt(_ d: Date?) -> Self { recordedAt = d; return self }
    @discardableResult func scripture(_ refs: [String]) -> Self { scripture = refs; return self }
    @discardableResult func outline(_ pts: [SermonOutlinePoint]) -> Self { outline = pts; return self }
    @discardableResult func themes(_ t: [String]) -> Self { keyThemes = t; return self }
    @discardableResult func questions(_ q: [String]) -> Self { discussionQuestions = q; return self }
    @discardableResult func prayerPoints(_ pp: [String]) -> Self { prayerPoints = pp; return self }
    @discardableResult func mediaURL(_ url: String?) -> Self { mediaURL = url; return self }

    func build() -> SermonStudyPacket {
        SermonStudyPacket(
            id: UUID().uuidString,
            sermonId: sermonId,
            title: title,
            preacher: preacher,
            churchName: churchName,
            recordedAt: recordedAt,
            scripture: scripture,
            outline: outline,
            keyThemes: keyThemes,
            discussionQuestions: discussionQuestions,
            prayerPoints: prayerPoints,
            mediaURL: mediaURL,
            approved: false, // all AI-generated outputs start unapproved
            generatedAt: Date()
        )
    }
}
