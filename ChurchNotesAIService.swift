//
//  ChurchNotesAIService.swift
//  AMENAPP
//
//  AI assistance for Church Notes with OpenAI integration
//

import Foundation
import SwiftUI

@MainActor
class ChurchNotesAIService: ObservableObject {
    static let shared = ChurchNotesAIService()
    
    @Published var isProcessing = false
    @Published var lastResult: String?
    @Published var lastError: Error?
    
    private let openAIService = OpenAIService.shared
    
    // Rate limiting: 10 requests per hour per user
    private var requestCounts: [String: (count: Int, resetTime: Date)] = [:]
    
    private init() {}
    
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
    @StateObject private var aiService = ChurchNotesAIService.shared
    @State private var selectedFeature: AIFeature?
    @State private var result: String?
    @State private var showError = false
    @State private var errorMessage = ""
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
                            isProcessing: aiService.isProcessing && selectedFeature == feature
                        ) {
                            runAIFeature(feature)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
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
        guard let userId = FirebaseAuth.Auth.auth().currentUser?.uid else {
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
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                    
                    Text(feature.description)
                        .font(.system(size: 14))
                        .foregroundStyle(.black.opacity(0.6))
                }
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
        }
        .disabled(isProcessing)
    }
}
