//
//  MessagesAPIService.swift
//  AMENAPP
//
//  Backend Integration for Messaging
//

import Foundation
import UIKit

// MARK: - Messages API Service

class MessagesAPIService {
    static let shared = MessagesAPIService()
    
    private let baseURL = "https://api.yourdomain.com/v1" // Replace with your backend URL
    private let session: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Authentication
    
    private var authToken: String? {
        // TODO: Get from UserDefaults or Keychain
        return UserDefaults.standard.string(forKey: "auth_token")
    }
    
    private var currentUserId: String {
        // TODO: Get from your auth system
        return UserDefaults.standard.string(forKey: "user_id") ?? "unknown"
    }
    
    // MARK: - Conversations
    
    /// Fetch all conversations for the current user
    func fetchConversations() async throws -> [ConversationDTO] {
        guard let url = URL(string: "\(baseURL)/conversations") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let conversations = try JSONDecoder().decode([ConversationDTO].self, from: data)
        return conversations
    }
    
    /// Create a new conversation
    func createConversation(participantIds: [String], isGroup: Bool, name: String?) async throws -> ConversationDTO {
        guard let url = URL(string: "\(baseURL)/conversations") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "participant_ids": participantIds,
            "is_group": isGroup,
            "name": name as Any
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let conversation = try JSONDecoder().decode(ConversationDTO.self, from: data)
        return conversation
    }
    
    // MARK: - Messages
    
    /// Fetch messages for a specific conversation
    func fetchMessages(conversationId: String, limit: Int = 50, before: Date? = nil) async throws -> [MessageDTO] {
        var urlComponents = URLComponents(string: "\(baseURL)/conversations/\(conversationId)/messages")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        if let before = before {
            let timestamp = ISO8601DateFormatter().string(from: before)
            queryItems.append(URLQueryItem(name: "before", value: timestamp))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let messages = try JSONDecoder().decode([MessageDTO].self, from: data)
        return messages
    }
    
    /// Send a text message
    func sendMessage(conversationId: String, text: String, replyToId: String? = nil) async throws -> MessageDTO {
        guard let url = URL(string: "\(baseURL)/conversations/\(conversationId)/messages") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "text": text,
            "reply_to_id": replyToId as Any
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let message = try JSONDecoder().decode(MessageDTO.self, from: data)
        return message
    }
    
    /// Send a message with photo attachments
    func sendMessageWithPhotos(conversationId: String, text: String, images: [UIImage]) async throws -> MessageDTO {
        // First, upload images
        let imageURLs = try await uploadImages(images)
        
        guard let url = URL(string: "\(baseURL)/conversations/\(conversationId)/messages") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "text": text,
            "attachments": imageURLs.map { ["type": "photo", "url": $0] }
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let message = try JSONDecoder().decode(MessageDTO.self, from: data)
        return message
    }
    
    /// Upload images to server
    private func uploadImages(_ images: [UIImage]) async throws -> [String] {
        var uploadedURLs: [String] = []
        
        for image in images {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                continue
            }
            
            let url = try await uploadImage(imageData)
            uploadedURLs.append(url)
        }
        
        return uploadedURLs
    }
    
    private func uploadImage(_ imageData: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/upload/image") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let uploadResponse = try JSONDecoder().decode(ImageUploadResponse.self, from: data)
        return uploadResponse.url
    }
    
    /// Add reaction to a message
    func addReaction(messageId: String, emoji: String) async throws {
        guard let url = URL(string: "\(baseURL)/messages/\(messageId)/reactions") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body = ["emoji": emoji]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    /// Mark messages as read
    func markAsRead(conversationId: String, messageIds: [String]) async throws {
        guard let url = URL(string: "\(baseURL)/conversations/\(conversationId)/read") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let body = ["message_ids": messageIds]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    /// Delete a message
    func deleteMessage(messageId: String) async throws {
        guard let url = URL(string: "\(baseURL)/messages/\(messageId)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Contacts
    
    /// Search for users/contacts
    func searchContacts(query: String) async throws -> [ContactDTO] {
        guard let url = URL(string: "\(baseURL)/users/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        let contacts = try JSONDecoder().decode([ContactDTO].self, from: data)
        return contacts
    }
}

// MARK: - Data Transfer Objects (DTOs)

struct ConversationDTO: Codable, Identifiable {
    let id: String
    let name: String?
    let participants: [ParticipantDTO]
    let lastMessage: MessageDTO?
    let unreadCount: Int
    let isGroup: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case participants
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ParticipantDTO: Codable, Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
    }
}

struct MessageDTO: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let senderName: String
    let text: String
    let attachments: [AttachmentDTO]
    let reactions: [ReactionDTO]
    let replyToId: String?
    let timestamp: Date
    let isRead: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case text
        case attachments
        case reactions
        case replyToId = "reply_to_id"
        case timestamp
        case isRead = "is_read"
    }
}

struct AttachmentDTO: Codable, Identifiable {
    let id: String
    let type: String // "photo", "video", "audio", "document"
    let url: String
    let thumbnailUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
        case thumbnailUrl = "thumbnail_url"
    }
}

struct ReactionDTO: Codable, Identifiable {
    let id: String
    let emoji: String
    let userId: String
    let userName: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case emoji
        case userId = "user_id"
        case userName = "user_name"
    }
}

struct ContactDTO: Codable, Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let isOnline: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case isOnline = "is_online"
    }
}

struct ImageUploadResponse: Codable {
    let url: String
}

// MARK: - WebSocket for Real-Time Messaging

/// For real-time message delivery, you'll need WebSocket support
/// This is a basic example - consider using Socket.IO or your backend's WebSocket
class MessagesWebSocketService {
    static let shared = MessagesWebSocketService()
    
    private var webSocket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    
    var onMessageReceived: ((MessageDTO) -> Void)?
    var onTypingStatusChanged: ((String, Bool) -> Void)? // conversationId, isTyping
    
    func connect(token: String) {
        guard let url = URL(string: "wss://api.yourdomain.com/ws?token=\(token)") else {
            return
        }
        
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
    
    func sendTypingStatus(conversationId: String, isTyping: Bool) {
        let message = [
            "type": "typing",
            "conversation_id": conversationId,
            "is_typing": isTyping
        ] as [String : Any]
        
        if let data = try? JSONSerialization.data(withJSONObject: message),
           let json = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(json)) { error in
                if let error = error {
                    print("WebSocket send error: \(error)")
                }
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "message":
            if let messageData = try? JSONSerialization.data(withJSONObject: json["data"] as Any),
               let message = try? JSONDecoder().decode(MessageDTO.self, from: messageData) {
                onMessageReceived?(message)
            }
            
        case "typing":
            if let conversationId = json["conversation_id"] as? String,
               let isTyping = json["is_typing"] as? Bool {
                onTypingStatusChanged?(conversationId, isTyping)
            }
            
        default:
            break
        }
    }
}

// MARK: - Usage Example

/*
 
 ## How to Integrate with Your MessagesView:
 
 ### 1. Replace the sample data with API calls
 
 ```swift
 struct MessagesView: View {
     @State private var conversations: [Conversation] = []
     @State private var isLoading = true
     
     var body: some View {
         // ... existing UI
     }
     
     func loadConversations() async {
         isLoading = true
         do {
             let dtos = try await MessagesAPIService.shared.fetchConversations()
             conversations = dtos.map { dto in
                 Conversation(
                     id: dto.id,
                     name: dto.name ?? dto.participants.first?.name ?? "Unknown",
                     lastMessage: dto.lastMessage?.text ?? "",
                     timestamp: formatTimestamp(dto.lastMessage?.timestamp ?? dto.updatedAt),
                     isGroup: dto.isGroup,
                     unreadCount: dto.unreadCount,
                     avatarColor: .random() // Or based on user
                 )
             }
         } catch {
             print("Error loading conversations: \(error)")
         }
         isLoading = false
     }
 }
 ```
 
 ### 2. Send messages to backend
 
 ```swift
 private func sendMessage() {
     guard !messageText.isEmpty else { return }
     
     Task {
         do {
             let messageDTO: MessageDTO
             
             if !selectedImages.isEmpty {
                 messageDTO = try await MessagesAPIService.shared.sendMessageWithPhotos(
                     conversationId: conversation.id,
                     text: messageText,
                     images: selectedImages
                 )
             } else {
                 messageDTO = try await MessagesAPIService.shared.sendMessage(
                     conversationId: conversation.id,
                     text: messageText,
                     replyToId: replyingTo?.id
                 )
             }
             
             // Convert DTO to local Message model and add to array
             let newMessage = Message(
                 text: messageDTO.text,
                 isFromCurrentUser: true,
                 timestamp: messageDTO.timestamp,
                 isRead: messageDTO.isRead
             )
             
             withAnimation {
                 messages.append(newMessage)
                 messageText = ""
                 selectedImages = []
             }
         } catch {
             print("Error sending message: \(error)")
             // Show error to user
         }
     }
 }
 ```
 
 ### 3. Setup WebSocket for real-time messages
 
 ```swift
 .onAppear {
     // Setup WebSocket
     MessagesWebSocketService.shared.onMessageReceived = { messageDTO in
         // Add new message to UI
         let newMessage = convertDTOToMessage(messageDTO)
         withAnimation {
             messages.append(newMessage)
         }
     }
     
     MessagesWebSocketService.shared.onTypingStatusChanged = { conversationId, isTyping in
         if conversationId == conversation.id {
             self.isTyping = isTyping
         }
     }
     
     MessagesWebSocketService.shared.connect(token: authToken)
 }
 .onDisappear {
     MessagesWebSocketService.shared.disconnect()
 }
 ```
 
 ## Backend Requirements:
 
 You'll need endpoints for:
 - ✅ GET /conversations - List all conversations
 - ✅ POST /conversations - Create new conversation
 - ✅ GET /conversations/:id/messages - Get messages
 - ✅ POST /conversations/:id/messages - Send message
 - ✅ POST /messages/:id/reactions - Add reaction
 - ✅ DELETE /messages/:id - Delete message
 - ✅ POST /conversations/:id/read - Mark as read
 - ✅ GET /users/search - Search contacts
 - ✅ POST /upload/image - Upload images
 - ✅ WebSocket /ws - Real-time updates
 
 ## Backend Frameworks to Consider:
 
 - **Firebase** - Easiest (Firestore + Cloud Functions)
 - **Node.js + Express** - Flexible
 - **Django + Channels** - Python
 - **Rails + ActionCable** - Ruby
 - **Vapor** - Swift (if you want same language)
 
 */
