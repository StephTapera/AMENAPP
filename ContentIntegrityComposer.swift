//
//  ContentIntegrityComposer.swift
//  AMENAPP
//
//  Client-side content integrity guards for all composer surfaces
//  Detects paste events, tracks authenticity signals, enforces rate limits
//

import SwiftUI
import Combine

// MARK: - Composer Integrity Tracker

class ComposerIntegrityTracker: ObservableObject {
    
    // Typing behavior signals
    @Published var totalCharactersTyped: Int = 0
    @Published var totalCharactersPasted: Int = 0
    @Published var pasteEvents: [PasteEvent] = []
    @Published var typingSessionStart: Date?
    @Published var lastKeystrokeTime: Date?
    
    // Moderation state
    @Published var showPersonalizeNudge: Bool = false
    @Published var nudgeMessage: String = ""
    @Published var isRateLimited: Bool = false
    @Published var rateLimitMessage: String = ""
    
    struct PasteEvent {
        let timestamp: Date
        let pastedLength: Int
        let pastedText: String
    }
    
    var typedVsPastedRatio: Double {
        let total = totalCharactersTyped + totalCharactersPasted
        guard total > 0 else { return 1.0 }
        return Double(totalCharactersTyped) / Double(total)
    }
    
    var largestPasteLength: Int {
        pasteEvents.map { $0.pastedLength }.max() ?? 0
    }
    
    var hasLargePaste: Bool {
        largestPasteLength > 200
    }
    
    // MARK: - Tracking Methods
    
    func trackTyping(addedCharacters: Int) {
        if typingSessionStart == nil {
            typingSessionStart = Date()
        }
        totalCharactersTyped += addedCharacters
        lastKeystrokeTime = Date()
    }
    
    func trackPaste(text: String) {
        let pasteLength = text.count
        totalCharactersPasted += pasteLength
        
        pasteEvents.append(PasteEvent(
            timestamp: Date(),
            pastedLength: pasteLength,
            pastedText: text
        ))
        
        // Trigger nudge for large pastes
        if pasteLength > 200 {
            triggerPersonalizeNudge(for: pasteLength)
        }
    }
    
    func triggerPersonalizeNudge(for pasteLength: Int) {
        if pasteLength > 500 {
            nudgeMessage = "That's a lot of pasted text! Consider adding your own reflection to make it more personal."
        } else if pasteLength > 200 {
            nudgeMessage = "Add your own thoughts to make this more meaningful to the community."
        }
        showPersonalizeNudge = true
    }
    
    func reset() {
        totalCharactersTyped = 0
        totalCharactersPasted = 0
        pasteEvents = []
        typingSessionStart = nil
        lastKeystrokeTime = nil
        showPersonalizeNudge = false
        isRateLimited = false
    }
    
    // MARK: - Authenticity Signals Export
    
    func exportAuthenticitySignals() -> AuthenticitySignals {
        let typingDuration = typingSessionStart.map { Date().timeIntervalSince($0) } ?? 0
        
        return AuthenticitySignals(
            typedCharacters: totalCharactersTyped,
            pastedCharacters: totalCharactersPasted,
            typedVsPastedRatio: typedVsPastedRatio,
            largestPasteLength: largestPasteLength,
            pasteEventCount: pasteEvents.count,
            typingDurationSeconds: typingDuration,
            hasLargePaste: hasLargePaste
        )
    }
}

struct AuthenticitySignals: Codable {
    let typedCharacters: Int
    let pastedCharacters: Int
    let typedVsPastedRatio: Double
    let largestPasteLength: Int
    let pasteEventCount: Int
    let typingDurationSeconds: TimeInterval
    let hasLargePaste: Bool
}

// MARK: - Content Integrity Guard (Reusable Modifier)

struct ContentIntegrityGuard: ViewModifier {
    let category: ContentCategory
    @Binding var text: String
    @StateObject private var tracker = ComposerIntegrityTracker()
    @ObservedObject private var rateLimiter = ComposerRateLimiter.shared
    
    @State private var previousText: String = ""
    @State private var showNudgeAlert: Bool = false
    
    func body(content: Content) -> some View {
        content
            .onChange(of: text) { oldValue, newValue in
                handleTextChange(from: oldValue, to: newValue)
            }
            .alert("Add Your Personal Touch", isPresented: $tracker.showPersonalizeNudge) {
                Button("Got it") {
                    tracker.showPersonalizeNudge = false
                }
            } message: {
                Text(tracker.nudgeMessage)
            }
            .alert("Slow Down", isPresented: $tracker.isRateLimited) {
                Button("OK") {
                    tracker.isRateLimited = false
                }
            } message: {
                Text(tracker.rateLimitMessage)
            }
            .onAppear {
                previousText = text
                checkRateLimit()
            }
    }
    
    private func handleTextChange(from oldValue: String, to newValue: String) {
        let addedLength = newValue.count - oldValue.count
        
        // Detect paste (large sudden increase)
        if addedLength > 50 {
            // Likely a paste event
            let pastedText = String(newValue.suffix(addedLength))
            tracker.trackPaste(text: pastedText)
        }
        else if addedLength > 0 {
            // Likely typing
            tracker.trackTyping(addedCharacters: addedLength)
        }
        
        previousText = newValue
    }
    
    private func checkRateLimit() {
        if rateLimiter.isRateLimited(for: category) {
            tracker.isRateLimited = true
            tracker.rateLimitMessage = "You're posting quite frequently. Take a moment to reflect before sharing more."
        }
    }
}

extension View {
    func withContentIntegrityGuard(
        category: ContentCategory,
        text: Binding<String>
    ) -> some View {
        self.modifier(ContentIntegrityGuard(category: category, text: text))
    }
}

// MARK: - Rate Limiter

class ComposerRateLimiter: ObservableObject {
    static let shared = ComposerRateLimiter()
    
    private var postTimestamps: [ContentCategory: [Date]] = [:]
    private let windowDuration: TimeInterval = 300 // 5 minutes
    
    // Rate limit thresholds
    private let limits: [ContentCategory: Int] = [
        .post: 5,           // 5 posts per 5 min
        .comment: 10,       // 10 comments per 5 min
        .reply: 15,         // 15 replies per 5 min
        .profileBio: 3,     // 3 bio updates per 5 min
        .caption: 10        // 10 captions per 5 min
    ]
    
    func trackPost(category: ContentCategory) {
        let now = Date()
        if postTimestamps[category] == nil {
            postTimestamps[category] = []
        }
        postTimestamps[category]?.append(now)
        cleanupOldTimestamps(for: category)
    }
    
    func isRateLimited(for category: ContentCategory) -> Bool {
        cleanupOldTimestamps(for: category)
        let recentCount = postTimestamps[category]?.count ?? 0
        let limit = limits[category] ?? 10
        return recentCount >= limit
    }
    
    func getRemainingPosts(for category: ContentCategory) -> Int {
        cleanupOldTimestamps(for: category)
        let recentCount = postTimestamps[category]?.count ?? 0
        let limit = limits[category] ?? 10
        return max(0, limit - recentCount)
    }
    
    /// Returns the Date when the oldest post in the window expires and posting is unlocked again.
    func getUnlockTime(for category: ContentCategory) -> Date? {
        guard let timestamps = postTimestamps[category], !timestamps.isEmpty else { return nil }
        let oldest = timestamps.min() ?? Date()
        return oldest.addingTimeInterval(windowDuration)
    }
    
    private func cleanupOldTimestamps(for category: ContentCategory) {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        postTimestamps[category] = postTimestamps[category]?.filter { $0 > cutoff }
    }
}

// MARK: - Personalize Nudge Banner View

struct PersonalizeNudgeBanner: View {
    let message: String
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make it personal")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    Text(message)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Rate Limit Warning View

struct RateLimitWarning: View {
    let remainingPosts: Int
    let category: ContentCategory
    
    var body: some View {
        if remainingPosts <= 2 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                Text("You can post \(remainingPosts) more \(category.rawValue)\(remainingPosts == 1 ? "" : "s") in the next 5 minutes")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

// MARK: - Moderation Decision UI

struct ModerationDecisionView: View {
    let decision: ModerationDecision
    let onRevise: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon based on action
            Image(systemName: iconForAction(decision.action))
                .font(.system(size: 50))
                .foregroundStyle(colorForAction(decision.action))
            
            // Title
            Text(titleForAction(decision.action))
                .font(.custom("OpenSans-Bold", size: 20))
            
            // Message
            Text(decision.userMessage)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Suggested revisions
            if let suggestions = decision.suggestedRevisions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try adding:")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.blue)
                            Text(suggestion)
                                .font(.custom("OpenSans-Regular", size: 13))
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Button("Revise") {
                    onRevise()
                }
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
        .padding(24)
    }
    
    private func iconForAction(_ action: ContentIntegrityAction) -> String {
        switch action {
        case .nudgeRewrite: return "lightbulb.fill"
        case .requireRevision: return "pencil.circle.fill"
        case .holdForReview: return "clock.fill"
        case .rateLimit: return "hourglass.fill"
        case .reject: return "xmark.circle.fill"
        default: return "checkmark.circle.fill"
        }
    }
    
    private func colorForAction(_ action: ContentIntegrityAction) -> Color {
        switch action {
        case .nudgeRewrite: return .orange
        case .requireRevision: return .blue
        case .holdForReview: return .purple
        case .rateLimit: return .orange
        case .reject: return .red
        default: return .green
        }
    }
    
    private func titleForAction(_ action: ContentIntegrityAction) -> String {
        switch action {
        case .nudgeRewrite: return "Add Your Voice"
        case .requireRevision: return "Needs Personal Touch"
        case .holdForReview: return "Under Review"
        case .rateLimit: return "Slow Down"
        case .reject: return "Cannot Post"
        default: return "All Set"
        }
    }
}
