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
    
    private let database = Database.database()
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
        
        print("💾 Message saved for later: \(message.content.prefix(50))...")
    }
    
    func unsaveMessage(_ savedMessage: SavedBereanMessage) {
        savedMessages.removeAll { $0.id == savedMessage.id }
        persistSavedMessages()
        
        print("🗑️ Message removed from saved")
    }
    
    func updateSavedMessage(_ savedMessage: SavedBereanMessage, tags: [String], note: String?) {
        if let index = savedMessages.firstIndex(where: { $0.id == savedMessage.id }) {
            var updated = savedMessages[index]
            updated.tags = tags
            updated.note = note
            savedMessages[index] = updated
            persistSavedMessages()
            
            print("✏️ Saved message updated")
        }
    }
    
    private func persistSavedMessages() {
        do {
            let data = try JSONEncoder().encode(savedMessages)
            UserDefaults.standard.set(data, forKey: "berean_saved_messages")
        } catch {
            print("❌ Failed to save messages: \(error)")
        }
    }
    
    private func loadSavedMessages() {
        guard let data = UserDefaults.standard.data(forKey: "berean_saved_messages") else { return }
        
        do {
            savedMessages = try JSONDecoder().decode([SavedBereanMessage].self, from: data)
            print("📖 Loaded \(savedMessages.count) saved messages")
        } catch {
            print("❌ Failed to load saved messages: \(error)")
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
            print("❌ Cannot report issue - no network connection")
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
        
        print("✅ Issue report submitted: \(issueType.rawValue)")
        
        // Also send email notification (optional - would need backend)
        await sendIssueReportEmail(report: report)
    }
    
    private func sendIssueReportEmail(report: BereanIssueReport) async {
        // In production, call your backend API to send email
        // For now, just log
        print("📧 Email notification would be sent for issue: \(report.issueType.rawValue)")
    }
    
    // MARK: - Share to Feed
    
    func shareToFeed(
        message: BereanMessage,
        personalNote: String? = nil,
        communityId: String? = nil
    ) async throws {
        // Check network connectivity first
        guard AMENNetworkMonitor.shared.isConnected else {
            print("❌ Cannot share to feed - no network connection")
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
        
        print("✅ Shared to feed: \(postId)")
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
        // In production, use PDFKit to generate proper PDF
        // For now, return plain text data
        let text = exportConversationAsText(conversation)
        return text.data(using: .utf8)
    }
}
