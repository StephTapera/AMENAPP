//
//  BereanDataManager.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import Foundation
import Combine
import FirebaseDatabase
import FirebaseAuth
import PDFKit
import UIKit

// MARK: - Saved Message Model

struct SavedBereanMessage: Identifiable, Codable {
    let id: UUID
    let message: BereanMessage
    let savedDate: Date
    var tags: [String]
    var note: String?
    
    init(message: BereanMessage, tags: [String] = [], note: String? = nil) {
        self.id = UUID()
        self.message = message
        self.savedDate = Date()
        self.tags = tags
        self.note = note
    }
}

// MARK: - Issue Report Model

struct BereanIssueReport: Codable {
    let id: UUID
    let messageId: UUID
    let messageContent: String
    let issueType: IssueType
    let description: String
    let timestamp: Date
    let userId: String
    
    enum IssueType: String, Codable, CaseIterable {
        case inaccurate = "Inaccurate Information"
        case inappropriate = "Inappropriate Content"
        case technical = "Technical Issue"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .inaccurate: return "exclamationmark.triangle.fill"
            case .inappropriate: return "hand.raised.fill"
            case .technical: return "wrench.and.screwdriver.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
    }
}

// MARK: - Feed Post Model

struct BereanFeedPost: Codable {
    let id: String
    let userId: String
    let userName: String
    let userInitials: String
    let content: String
    let verseReferences: [String]
    let timestamp: Int64
    let source: String // "berean_ai"
    
    var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
}

// MARK: - Berean Data Manager

@MainActor
class BereanDataManager: ObservableObject {
    static let shared = BereanDataManager()
    
    @Published var savedMessages: [SavedBereanMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Lazy to avoid accessing Database.database() before AppDelegate sets isPersistenceEnabled.
    private lazy var database: Database = Database.database()
    private var ref: DatabaseReference {
        database.reference()
    }
    
    private init() {
        loadSavedMessages()
    }
    
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? "anonymous"
    }
    
    var currentUserName: String {
        Auth.auth().currentUser?.displayName ?? "User"
    }
    
    var currentUserInitials: String {
        let name = currentUserName
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return name.prefix(2).uppercased()
    }
    
    // MARK: - Save Messages for Later
    
    func saveMessage(_ message: BereanMessage, tags: [String] = [], note: String? = nil) {
        let savedMessage = SavedBereanMessage(message: message, tags: tags, note: note)
        
        savedMessages.insert(savedMessage, at: 0)
        persistSavedMessages()
        
        dlog("💾 Message saved for later: \(message.content.prefix(50))...")
    }
    
    func unsaveMessage(_ savedMessage: SavedBereanMessage) {
        savedMessages.removeAll { $0.id == savedMessage.id }
        persistSavedMessages()
        
        dlog("🗑️ Message removed from saved")
    }
    
    func updateSavedMessage(_ savedMessage: SavedBereanMessage, tags: [String], note: String?) {
        if let index = savedMessages.firstIndex(where: { $0.id == savedMessage.id }) {
            var updated = savedMessages[index]
            updated.tags = tags
            updated.note = note
            savedMessages[index] = updated
            persistSavedMessages()
            
            dlog("✏️ Saved message updated")
        }
    }
    
    private func persistSavedMessages() {
        do {
            let data = try JSONEncoder().encode(savedMessages)
            UserDefaults.standard.set(data, forKey: "berean_saved_messages")
        } catch {
            dlog("❌ Failed to save messages: \(error)")
        }
    }
    
    private func loadSavedMessages() {
        guard let data = UserDefaults.standard.data(forKey: "berean_saved_messages") else { return }
        
        do {
            savedMessages = try JSONDecoder().decode([SavedBereanMessage].self, from: data)
            dlog("📖 Loaded \(savedMessages.count) saved messages")
        } catch {
            // The stored data is corrupt or the model schema changed.
            // Remove the corrupt key so subsequent launches don't keep failing,
            // and leave savedMessages as its current value (empty default).
            dlog("❌ Failed to load saved messages — clearing corrupt cache: \(error)")
            UserDefaults.standard.removeObject(forKey: "berean_saved_messages")
        }
    }
    
    // MARK: - Report Issue
    
    func reportIssue(
        message: BereanMessage,
        issueType: BereanIssueReport.IssueType,
        description: String
    ) async throws {
        // Check network connectivity first
        guard AMENNetworkMonitor.shared.isConnected else {
            dlog("❌ Cannot report issue - no network connection")
            throw BereanError.networkUnavailable
        }
        
        let report = BereanIssueReport(
            id: UUID(),
            messageId: message.id,
            messageContent: message.content,
            issueType: issueType,
            description: description,
            timestamp: Date(),
            userId: currentUserId
        )
        
        // Save to Firebase
        let reportRef = ref.child("bereanIssueReports").childByAutoId()
        
        let reportData: [String: Any] = [
            "id": report.id.uuidString,
            "messageId": report.messageId.uuidString,
            "messageContent": report.messageContent,
            "issueType": report.issueType.rawValue,
            "description": report.description,
            "timestamp": ServerValue.timestamp(),
            "userId": report.userId
        ]
        
        try await reportRef.setValue(reportData)
        
        dlog("✅ Issue report submitted: \(issueType.rawValue)")
        
        // Also send email notification (optional - would need backend)
        await sendIssueReportEmail(report: report)
    }
    
    private func sendIssueReportEmail(report: BereanIssueReport) async {
        // In production, call your backend API to send email
        // For now, just log
        dlog("📧 Email notification would be sent for issue: \(report.issueType.rawValue)")
    }
    
    // MARK: - Share to Feed
    
    func shareToFeed(
        message: BereanMessage,
        personalNote: String? = nil,
        communityId: String? = nil
    ) async throws {
        // Check network connectivity first
        guard AMENNetworkMonitor.shared.isConnected else {
            dlog("❌ Cannot share to feed - no network connection")
            throw BereanError.networkUnavailable
        }
        
        let postId = UUID().uuidString
        
        // Combine personal note with AI response
        var content = message.content
        if let note = personalNote, !note.isEmpty {
            content = "\(note)\n\n---\n\n💡 *Berean AI Insight:*\n\n\(message.content)"
        } else {
            content = "💡 *Berean AI Insight:*\n\n\(message.content)"
        }
        
        let post = BereanFeedPost(
            id: postId,
            userId: currentUserId,
            userName: currentUserName,
            userInitials: currentUserInitials,
            content: content,
            verseReferences: message.verseReferences,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            source: "berean_ai"
        )
        
        // Save to Firebase
        let postRef = ref.child("posts").child(postId)
        
        let postData: [String: Any] = [
            "id": post.id,
            "userId": post.userId,
            "userName": post.userName,
            "userInitials": post.userInitials,
            "content": post.content,
            "verseReferences": post.verseReferences,
            "timestamp": ServerValue.timestamp(),
            "source": post.source,
            "type": "berean_insight",
            "lightbulbs": 0,
            "amens": 0,
            "comments": 0
        ]
        
        try await postRef.setValue(postData)
        
        // Log activity
        ActivityFeedService.shared.logPostCreated(
            postId: postId,
            postContent: content,
            communityId: communityId
        )
        
        dlog("✅ Shared to feed: \(postId)")
    }
    
    // MARK: - Export Conversations
    
    func exportConversationAsText(_ conversation: SavedConversation) -> String {
        var text = """
        Berean AI Conversation
        ======================
        Title: \(conversation.title)
        Date: \(conversation.date.formatted(date: .complete, time: .shortened))
        Translation: \(conversation.translation)
        
        
        """
        
        for message in conversation.messages {
            let sender = message.role == .user ? "You" : "Berean AI"
            text += """
            \(sender) (\(message.timestamp.formatted(date: .omitted, time: .shortened))):
            \(message.content)
            
            
            """
            
            if !message.verseReferences.isEmpty {
                text += "References: \(message.verseReferences.joined(separator: ", "))\n\n"
            }
        }
        
        return text
    }
    
    func exportConversationAsPDF(_ conversation: SavedConversation) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let titleFont    = UIFont.systemFont(ofSize: 20, weight: .bold)
        let metaFont     = UIFont.systemFont(ofSize: 11, weight: .regular)
        let senderFont   = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont     = UIFont.systemFont(ofSize: 13, weight: .regular)
        let verseFont    = UIFont.italicSystemFont(ofSize: 11)

        let margin: CGFloat = 48
        let lineSpacing: CGFloat = 6
        let blockSpacing: CGFloat = 20
        let textWidth = pageRect.width - margin * 2

        func attrs(_ font: UIFont, color: UIColor = .black, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.alignment = alignment
            para.lineSpacing = lineSpacing
            return [.font: font, .foregroundColor: color, .paragraphStyle: para]
        }

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            var page = 1

            func newPage() {
                ctx.beginPage()
                y = margin
                page += 1
            }

            func checkPageBreak(needing height: CGFloat) {
                if y + height > pageRect.height - margin {
                    newPage()
                }
            }

            func draw(_ string: NSAttributedString, maxWidth: CGFloat) -> CGFloat {
                let size = string.boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).size
                checkPageBreak(needing: ceil(size.height) + 4)
                string.draw(in: CGRect(x: margin, y: y, width: maxWidth, height: ceil(size.height) + 4))
                return ceil(size.height) + 4
            }

            ctx.beginPage()

            // Title
            let titleStr = NSAttributedString(string: conversation.title, attributes: attrs(titleFont, alignment: .center))
            y += draw(titleStr, maxWidth: textWidth)
            y += 8

            // Meta
            let dateStr = conversation.date.formatted(date: .complete, time: .shortened)
            let metaStr = NSAttributedString(
                string: "\(dateStr)  |  \(conversation.translation)  |  \(conversation.messages.count) messages",
                attributes: attrs(metaFont, color: .darkGray, alignment: .center)
            )
            y += draw(metaStr, maxWidth: textWidth)
            y += blockSpacing

            // Divider
            checkPageBreak(needing: 2)
            UIColor.lightGray.setStroke()
            let divider = UIBezierPath()
            divider.move(to: CGPoint(x: margin, y: y))
            divider.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            divider.lineWidth = 0.5
            divider.stroke()
            y += blockSpacing

            // Messages
            for msg in conversation.messages where msg.role != .system {
                let sender = msg.isFromUser ? "You" : "Berean AI"
                let senderColor: UIColor = msg.isFromUser ? .systemBlue : UIColor(red: 0.85, green: 0.38, blue: 0.22, alpha: 1)
                let time = msg.timestamp.formatted(date: .omitted, time: .shortened)

                let headerStr = NSAttributedString(
                    string: "\(sender) · \(time)",
                    attributes: attrs(senderFont, color: senderColor)
                )
                y += draw(headerStr, maxWidth: textWidth)

                let bodyStr = NSAttributedString(string: msg.content, attributes: attrs(bodyFont))
                y += draw(bodyStr, maxWidth: textWidth)

                if !msg.verseReferences.isEmpty {
                    let refs = "References: " + msg.verseReferences.joined(separator: ", ")
                    let refStr = NSAttributedString(string: refs, attributes: attrs(verseFont, color: .darkGray))
                    y += draw(refStr, maxWidth: textWidth)
                }
                y += blockSpacing
            }

            // Footer
            let footerStr = NSAttributedString(
                string: "Exported from Berean AI — AMEN App",
                attributes: attrs(metaFont, color: .lightGray, alignment: .center)
            )
            let footerY = pageRect.height - margin
            footerStr.draw(in: CGRect(x: margin, y: footerY - 16, width: textWidth, height: 16))
        }

        return data
    }
}
