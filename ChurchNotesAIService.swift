//
//  ChurchNotesAIService.swift
//  AMENAPP
//
//  AI assistance for Church Notes with OpenAI integration
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import Security

@MainActor
class ChurchNotesAIService: ObservableObject {
    static let shared = ChurchNotesAIService()
    
    @Published var isProcessing = false
    @Published var lastResult: String?
    @Published var lastError: Error?
    
    // ClaudeService routes church note helpers to Haiku (fast, cost-efficient for summaries).
    private let openAIService = ClaudeService.shared
    
    // Rate limiting: 10 requests per hour per user
    private var requestCounts: [String: (count: Int, resetTime: Date)] = [:]
    
    private init() {
        // P2 #4: Migrate encryption key from UserDefaults to Keychain on first run
        migrateEncryptionKeyIfNeeded()
    }

    // MARK: - Encryption Key Management (Keychain)

    private static let keychainService = "com.amenapp.churchnotes"
    private static let keychainAccount = "encryptionKey"

    /// Returns the church notes encryption key, reading from (and if needed creating in) the Keychain.
    /// P2 #4: Key is stored in Keychain rather than UserDefaults to prevent it from appearing
    /// in iCloud backups or device migration snapshots.
    func loadEncryptionKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        // No key found — generate one and persist it
        let newKey = UUID().uuidString + UUID().uuidString
        saveEncryptionKeyToKeychain(newKey)
        return newKey
    }

    private func saveEncryptionKeyToKeychain(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
            // Only accessible when device is unlocked; not backed up to iCloud
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        // Remove any stale item first to avoid errSecDuplicateItem
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// One-time migration: if an encryption key exists in UserDefaults, move it to Keychain
    /// and delete it from UserDefaults so it is no longer stored in plaintext.
    private func migrateEncryptionKeyIfNeeded() {
        let legacyKey = "churchNotesEncryptionKey"
        if let existingKey = UserDefaults.standard.string(forKey: legacyKey), !existingKey.isEmpty {
            saveEncryptionKeyToKeychain(existingKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    // MARK: - Rate Limiting
    
    private func checkRateLimit(userId: String) throws {
        let now = Date()
        
        if let existing = requestCounts[userId] {
            // Reset if hour has passed
            if now > existing.resetTime {
                requestCounts[userId] = (count: 1, resetTime: now.addingTimeInterval(3600))
                return
            }
            
            // Check if limit exceeded
            if existing.count >= 10 {
                throw AIServiceError.rateLimitExceeded
            }
            
            // Increment count
            requestCounts[userId] = (count: existing.count + 1, resetTime: existing.resetTime)
        } else {
            // First request
            requestCounts[userId] = (count: 1, resetTime: now.addingTimeInterval(3600))
        }
    }
    
    // MARK: - AI Features
    
    /// Summarize sermon notes into 3-5 key bullet points
    func summarizeNotes(_ note: ChurchNote, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        You are a helpful Christian study assistant. Summarize these sermon notes concisely in 3-5 bullet points. Focus on the main message and actionable takeaways.
        
        Title: \(note.title)
        \(note.sermonTitle.map { "Sermon: \($0)" } ?? "")
        \(note.pastor.map { "Pastor: \($0)" } ?? "")
        
        Notes:
        \(note.content)
        
        Format your response as bullet points starting with •
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
    
    /// Generate thoughtful reflection questions based on sermon notes
    func generateReflectionQuestions(_ note: ChurchNote, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Based on these sermon notes, generate 3 thoughtful reflection questions a believer might journal about. Make them personal and actionable.
        
        Title: \(note.title)
        \(note.sermonTitle.map { "Sermon: \($0)" } ?? "")
        
        Notes:
        \(note.content)
        
        Format each question on a new line starting with •
        Keep questions concise and thought-provoking.
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
    
    /// Create a prayer based on the sermon themes
    func generatePrayer(_ note: ChurchNote, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Write a short, heartfelt prayer (3-4 sentences) based on the themes in these sermon notes. Use first-person "I/we" perspective. Be sincere and personal.
        
        Title: \(note.title)
        \(note.sermonTitle.map { "Sermon: \($0)" } ?? "")
        
        Notes:
        \(note.content)
        
        Keep it concise, personal, and focused on the main themes.
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
    
    /// Extract key takeaways from the notes
    func extractKeyTakeaways(_ note: ChurchNote, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Extract 3-5 key takeaways or action steps from these sermon notes. Focus on practical applications and memorable insights.
        
        Title: \(note.title)
        Notes:
        \(note.content)
        
        Format as bullet points starting with •
        Make them actionable and memorable.
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
    
    /// Create a shareable recap (social media friendly)
    func createShareableRecap(_ note: ChurchNote, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Create a short, shareable recap of this sermon (2-3 sentences max). Make it inspiring and social-media friendly while capturing the core message.
        
        Title: \(note.title)
        \(note.sermonTitle.map { "Sermon: \($0)" } ?? "")
        \(note.pastor.map { "Pastor: \($0)" } ?? "")
        
        Notes:
        \(note.content)
        
        Keep it brief, inspiring, and easy to share. No hashtags or emojis.
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
    
    /// Find supporting scripture verses for a topic
    func findSupportingScriptures(topic: String, userId: String) async throws -> String {
        try checkRateLimit(userId: userId)
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Suggest 3-5 relevant Bible verses that relate to this topic: "\(topic)"
        
        Format each as:
        • Book Chapter:Verse - Brief context or relevance
        
        Only provide verse references, not full text. Be specific and relevant.
        """
        
        var result = ""
        
        for try await chunk in openAIService.sendMessage(prompt) {
            result += chunk
        }
        
        lastResult = result
        return result
    }
}

// MARK: - AI Service Errors

enum AIServiceError: LocalizedError {
    case rateLimitExceeded
    case invalidResponse
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded:
            return "You've reached the limit of 10 AI requests per hour. Please try again later."
        case .invalidResponse:
            return "Received an invalid response from the AI service."
        case .networkError:
            return "Network error. Please check your connection and try again."
        }
    }
}

// MARK: - AI Assistant View for Church Notes

struct ChurchNoteAIAssistantView: View {
    let note: ChurchNote
    @ObservedObject private var aiService = ChurchNotesAIService.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State private var selectedFeature: AIFeature?
    @State private var result: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showUpgradeSheet = false
    @Environment(\.dismiss) var dismiss

    enum AIFeature: String, CaseIterable {
        case summarize = "Summarize"
        case reflect = "Reflection Questions"
        case pray = "Create Prayer"
        case takeaways = "Key Takeaways"
        case recap = "Shareable Recap"

        var icon: String {
            switch self {
            case .summarize: return "doc.text.magnifyingglass"
            case .reflect: return "lightbulb.fill"
            case .pray: return "hands.sparkles.fill"
            case .takeaways: return "list.bullet.clipboard"
            case .recap: return "square.and.arrow.up"
            }
        }

        var description: String {
            switch self {
            case .summarize: return "Get a concise summary of your notes"
            case .reflect: return "Generate thoughtful questions for journaling"
            case .pray: return "Create a prayer based on the sermon"
            case .takeaways: return "Extract actionable insights"
            case .recap: return "Create a short, shareable version"
            }
        }

        /// All features require Berean Pro to prevent unmetered AI cost.
        var requiresPro: Bool { true }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.96, green: 0.96, blue: 0.96)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if let result = result {
                        // Show result
                        resultView(result)
                    } else {
                        // Show feature selection
                        featureSelectionView
                    }
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showUpgradeSheet) {
                PremiumUpgradeView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    private var featureSelectionView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What would you like help with?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.top, 24)
                
                VStack(spacing: 12) {
                    ForEach(AIFeature.allCases, id: \.self) { feature in
                        AIFeatureButton(
                            feature: feature,
                            isProcessing: aiService.isProcessing && selectedFeature == feature,
                            isLocked: feature.requiresPro && !premiumManager.hasProAccess
                        ) {
                            runAIFeature(feature)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Free-tier nudge banner
                if !premiumManager.hasProAccess {
                    Button { showUpgradeSheet = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlock AI Church Notes")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Summarize sermons, create prayers & more with Berean Pro")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func resultView(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button {
                        result = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Back")
                                .font(.system(size: 16))
                        }
                        .foregroundStyle(.black.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = text
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                            Text("Copy")
                                .font(.system(size: 16))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.05))
                        .foregroundStyle(.black.opacity(0.8))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
    }
    
    private func runAIFeature(_ feature: AIFeature) {
        // Gate: require Berean Pro before calling AI backend
        if feature.requiresPro && !premiumManager.hasProAccess {
            showUpgradeSheet = true
            return
        }

        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "You must be signed in to use AI features"
            showError = true
            return
        }

        selectedFeature = feature

        Task {
            do {
                let result: String

                switch feature {
                case .summarize:
                    result = try await aiService.summarizeNotes(note, userId: userId)
                case .reflect:
                    result = try await aiService.generateReflectionQuestions(note, userId: userId)
                case .pray:
                    result = try await aiService.generatePrayer(note, userId: userId)
                case .takeaways:
                    result = try await aiService.extractKeyTakeaways(note, userId: userId)
                case .recap:
                    result = try await aiService.createShareableRecap(note, userId: userId)
                }

                await MainActor.run {
                    self.result = result
                    self.selectedFeature = nil
                }

            } catch AIServiceError.rateLimitExceeded {
                await MainActor.run {
                    errorMessage = AIServiceError.rateLimitExceeded.errorDescription ?? "Rate limit reached."
                    showError = true
                    selectedFeature = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "The AI service is temporarily unavailable. Please try again shortly."
                    showError = true
                    selectedFeature = nil
                }
            }
        }
    }
}

struct AIFeatureButton: View {
    let feature: ChurchNoteAIAssistantView.AIFeature
    let isProcessing: Bool
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Image(systemName: feature.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isLocked ? Color(uiColor: .tertiaryLabel) : .blue)
                        .frame(width: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(feature.rawValue)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isLocked ? Color(uiColor: .secondaryLabel) : Color(uiColor: .label))
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                    }

                    Text(isLocked ? "Requires Berean Pro" : feature.description)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                Spacer()

                if isProcessing {
                    ProgressView()
                        .tint(Color(uiColor: .label))
                } else if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            )
            .opacity(isLocked ? 0.75 : 1.0)
        }
        .disabled(isProcessing)
    }
}
