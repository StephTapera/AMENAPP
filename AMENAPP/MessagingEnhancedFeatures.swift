//
//  MessagingEnhancedFeatures.swift
//  AMENAPP
//
//  Enhanced messaging features: Delivery status, failed messages, scroll to bottom,
//  disappearing messages, quick replies, link previews, mentions
//

import SwiftUI
import LinkPresentation
import UIKit
import Combine

// MARK: - Message Delivery Status

enum MessageDeliveryStatus {
    case sending      // Gray clock icon
    case sent         // Single gray checkmark
    case delivered    // Double gray checkmarks
    case read         // Double blue checkmarks
    case failed       // Red exclamation
    
    var icon: String {
        switch self {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .sending: return .secondary
        case .sent: return .secondary
        case .delivered: return .secondary
        case .read: return .blue
        case .failed: return .red
        }
    }
}

struct DeliveryStatusView: View {
    let status: MessageDeliveryStatus
    let timestamp: Date
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formatTime(timestamp))
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
            
            Image(systemName: status.icon)
                .font(.system(size: 12))
                .foregroundStyle(status.color)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Scroll to Bottom Button

struct ScrollToBottomButton: View {
    let unreadCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                        .offset(x: 8, y: -8)
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Failed Message Retry View

struct FailedMessageBanner: View {
    let message: AppMessage
    let onRetry: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Failed to send")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(message.text.prefix(50))
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Retry") {
                onRetry()
            }
            .font(.custom("OpenSans-Bold", size: 14))
            .foregroundStyle(.blue)
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding()
    }
}

// MARK: - Disappearing Messages

class DisappearingMessageTimer: ObservableObject {
    @Published var activeTimers: [String: Timer] = [:]
    
    func scheduleDisappear(messageId: String, after duration: TimeInterval, action: @escaping () -> Void) {
        // Cancel existing timer if any
        activeTimers[messageId]?.invalidate()
        
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            action()
            self?.activeTimers.removeValue(forKey: messageId)
        }
        
        activeTimers[messageId] = timer
    }
    
    func cancelTimer(for messageId: String) {
        activeTimers[messageId]?.invalidate()
        activeTimers.removeValue(forKey: messageId)
    }
    
    func cancelAll() {
        activeTimers.values.forEach { $0.invalidate() }
        activeTimers.removeAll()
    }
}

enum DisappearingMessageDuration: TimeInterval, CaseIterable, Identifiable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case oneHour = 3600
    case oneDay = 86400
    case oneWeek = 604800
    case off = 0
    
    var id: TimeInterval { rawValue }
    
    var displayName: String {
        switch self {
        case .tenSeconds: return "10 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .off: return "Off"
        }
    }
}

struct DisappearingMessageSettingsView: View {
    @Binding var duration: DisappearingMessageDuration
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DisappearingMessageDuration.allCases) { option in
                        Button {
                            duration = option
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if duration == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Auto-delete messages after")
                } footer: {
                    Text("Messages will automatically disappear after being read. This applies to new messages only.")
                }
            }
            .navigationTitle("Disappearing Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Quick Replies (Conversation Templates)

struct QuickReply: Identifiable, Codable {
    let id: String
    let text: String
    let emoji: String?
    let category: QuickReplyCategory
    let usageCount: Int
    
    init(id: String = UUID().uuidString, text: String, emoji: String? = nil, category: QuickReplyCategory = .general, usageCount: Int = 0) {
        self.id = id
        self.text = text
        self.emoji = emoji
        self.category = category
        self.usageCount = usageCount
    }
}

enum QuickReplyCategory: String, Codable, CaseIterable {
    case general = "General"
    case greetings = "Greetings"
    case thanks = "Thanks"
    case questions = "Questions"
    case busy = "Busy"
    case meeting = "Meeting"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .general: return "message"
        case .greetings: return "hand.wave"
        case .thanks: return "heart"
        case .questions: return "questionmark.circle"
        case .busy: return "clock"
        case .meeting: return "calendar"
        case .custom: return "star"
        }
    }
}

class QuickReplyManager: ObservableObject {
    @Published var quickReplies: [QuickReply] = []
    
    private let storageKey = "saved_quick_replies"
    
    init() {
        loadQuickReplies()
    }
    
    func loadQuickReplies() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([QuickReply].self, from: data) {
            quickReplies = decoded
        } else {
            // Load default quick replies
            quickReplies = QuickReply.defaultReplies
        }
    }
    
    func saveQuickReply(_ reply: QuickReply) {
        quickReplies.append(reply)
        saveToStorage()
    }
    
    func deleteQuickReply(_ reply: QuickReply) {
        quickReplies.removeAll { $0.id == reply.id }
        saveToStorage()
    }
    
    func incrementUsage(for replyId: String) {
        if let index = quickReplies.firstIndex(where: { $0.id == replyId }) {
            let updatedReply = QuickReply(
                id: quickReplies[index].id,
                text: quickReplies[index].text,
                emoji: quickReplies[index].emoji,
                category: quickReplies[index].category,
                usageCount: quickReplies[index].usageCount + 1
            )
            quickReplies[index] = updatedReply
            saveToStorage()
        }
    }
    
    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(quickReplies) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}

extension QuickReply {
    static let defaultReplies: [QuickReply] = [
        QuickReply(text: "Thanks! 🙏", emoji: "🙏", category: .thanks),
        QuickReply(text: "On my way!", emoji: "🚗", category: .general),
        QuickReply(text: "Sounds good!", emoji: "👍", category: .general),
        QuickReply(text: "Can we talk later?", emoji: "⏰", category: .busy),
        QuickReply(text: "In a meeting, will respond soon", emoji: "📅", category: .meeting),
        QuickReply(text: "Amen!", emoji: "🙌", category: .general),
        QuickReply(text: "Praying for you! 🙏", emoji: "🙏", category: .general),
        QuickReply(text: "See you at church!", emoji: "⛪", category: .general),
    ]
}

struct QuickReplyPickerView: View {
    @StateObject private var manager = QuickReplyManager()
    @Binding var selectedText: String
    @Environment(\.dismiss) private var dismiss
    @State private var showAddReply = false
    @State private var searchText = ""
    
    var filteredReplies: [QuickReply] {
        if searchText.isEmpty {
            return manager.quickReplies.sorted { $0.usageCount > $1.usageCount }
        }
        return manager.quickReplies.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search quick replies", text: $searchText)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Quick replies list
                List {
                    ForEach(QuickReplyCategory.allCases, id: \.self) { category in
                        let categoryReplies = filteredReplies.filter { $0.category == category }
                        
                        if !categoryReplies.isEmpty {
                            Section(header: Label(category.rawValue, systemImage: category.icon)) {
                                ForEach(categoryReplies) { reply in
                                    Button {
                                        selectedText = reply.text
                                        manager.incrementUsage(for: reply.id)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            if let emoji = reply.emoji {
                                                Text(emoji)
                                                    .font(.title2)
                                            }
                                            Text(reply.text)
                                                .foregroundStyle(.primary)
                                            
                                            Spacer()
                                            
                                            if reply.usageCount > 0 {
                                                Text("\(reply.usageCount)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            manager.deleteQuickReply(reply)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Replies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddReply = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddReply) {
                AddQuickReplyView(manager: manager)
            }
        }
    }
}

struct AddQuickReplyView: View {
    @ObservedObject var manager: QuickReplyManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var text = ""
    @State private var emoji = ""
    @State private var category: QuickReplyCategory = .custom
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Quick reply text", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Message")
                }
                
                Section {
                    TextField("Emoji (optional)", text: $emoji)
                } header: {
                    Text("Icon")
                }
                
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(QuickReplyCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                } header: {
                    Text("Category")
                }
            }
            .navigationTitle("New Quick Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let reply = QuickReply(
                            text: text,
                            emoji: emoji.isEmpty ? nil : emoji,
                            category: category
                        )
                        manager.saveQuickReply(reply)
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}

// MARK: - Link Previews

class LinkPreviewLoader: ObservableObject {
    @Published var preview: LinkPreview?
    @Published var isLoading = false
    
    private var metadataProvider = LPMetadataProvider()
    
    func loadPreview(for url: URL) {
        isLoading = true
        
        metadataProvider.startFetchingMetadata(for: url) { [weak self] metadata, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let metadata = metadata {
                    self?.preview = LinkPreview(
                        url: url,
                        title: metadata.title,
                        description: metadata.url?.host,
                        imageURL: metadata.imageProvider != nil ? url : nil
                    )
                }
            }
        }
    }
}

struct LinkPreview: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
    let description: String?
    let imageURL: URL?
}

struct LinkPreviewCard: View {
    let preview: LinkPreview
    @State private var image: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let title = preview.title {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .lineLimit(2)
                }
                
                if let description = preview.description {
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Text(preview.url.host ?? preview.url.absoluteString)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let imageURL = preview.imageURL else { return }
        
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            if let data = data, let loadedImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }.resume()
    }
}

// MARK: - @Mentions

struct MentionSuggestion: Identifiable {
    let id: String
    let name: String
    let username: String
    let avatarColor: Color
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

struct MentionSuggestionsView: View {
    let suggestions: [MentionSuggestion]
    let onSelect: (MentionSuggestion) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(suggestion.avatarColor.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(suggestion.initials)
                                        .font(.custom("OpenSans-Bold", size: 12))
                                        .foregroundStyle(suggestion.avatarColor)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                    .font(.custom("OpenSans-Bold", size: 13))
                                    .foregroundStyle(.primary)
                                
                                Text("@\(suggestion.username)")
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

class MentionParser {
    static func detectMentions(in text: String) -> [String] {
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
    
    static func highlightMentions(in text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let mentions = detectMentions(in: text)
        
        for mention in mentions {
            let searchText = "@\(mention)"
            if let range = attributed.range(of: searchText) {
                attributed[range].foregroundColor = .blue
                attributed[range].font = .custom("OpenSans-Bold", size: 16)
            }
        }
        
        return attributed
    }
}

// MARK: - Enhanced Chat Input with Features

struct EnhancedChatInputBar: View {
    @Binding var messageText: String
    @FocusState var isInputFocused: Bool
    @Binding var selectedImages: [UIImage]
    @State private var showQuickReplies = false
    @State private var showMentions = false
    @State private var mentionSuggestions: [MentionSuggestion] = []
    
    let conversationParticipants: [MentionSuggestion]
    let onSend: () -> Void
    let onPhotoPicker: () -> Void
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mention suggestions
            if showMentions && !mentionSuggestions.isEmpty {
                MentionSuggestionsView(suggestions: mentionSuggestions) { suggestion in
                    insertMention(suggestion)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Selected images preview
            if !selectedImages.isEmpty {
                selectedImagesPreview
            }
            
            // Input bar
            HStack(spacing: 12) {
                // Quick replies button
                Button {
                    showQuickReplies = true
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                
                // Photo button
                Button(action: onPhotoPicker) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                
                // Text field
                HStack(spacing: 8) {
                    TextField("Message", text: $messageText, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                        .onChange(of: messageText) { _, newValue in
                            checkForMentions(in: newValue)
                        }
                    
                    if !messageText.isEmpty {
                        Button {
                            messageText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                )
                
                // Send button
                Button(action: {
                    guard canSend else { return }
                    onSend()
                }) {
                    Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? .blue : .white.opacity(0.3))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)
        }
        .sheet(isPresented: $showQuickReplies) {
            QuickReplyPickerView(selectedText: $messageText)
        }
    }
    
    private var selectedImagesPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedImages.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: selectedImages[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button {
                            withAnimation {
                                let _ = selectedImages.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 16, height: 16)
                                )
                        }
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0, opacity: 0.8))
    }
    
    private func checkForMentions(in text: String) {
        // Check if user is typing @
        guard let lastWord = text.split(separator: " ").last,
              lastWord.hasPrefix("@") else {
            showMentions = false
            return
        }
        
        let query = String(lastWord.dropFirst()).lowercased()
        
        if query.isEmpty {
            mentionSuggestions = conversationParticipants
            showMentions = true
        } else {
            mentionSuggestions = conversationParticipants.filter {
                $0.name.lowercased().contains(query) || $0.username.lowercased().contains(query)
            }
            showMentions = !mentionSuggestions.isEmpty
        }
    }
    
    private func insertMention(_ suggestion: MentionSuggestion) {
        // Replace the @query with @username
        let components = messageText.components(separatedBy: " ")
        if let lastComponent = components.last, lastComponent.hasPrefix("@") {
            let withoutLast = components.dropLast().joined(separator: " ")
            messageText = withoutLast.isEmpty ? "@\(suggestion.username) " : "\(withoutLast) @\(suggestion.username) "
        }
        showMentions = false
    }
}

