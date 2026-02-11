//
//  CommentAIEnhancement.swift
//  AMENAPP
//
//  Enhancement 3: AI-Powered Comment Insights & Moderation
//

import SwiftUI
import NaturalLanguage

// MARK: - Comment Sentiment

enum CommentSentiment: String, Codable {
    case positive = "Positive"
    case negative = "Negative"
    case neutral = "Neutral"
    case thoughtful = "Thoughtful"
    case questioning = "Questioning"
    case encouraging = "Encouraging"
    
    var icon: String {
        switch self {
        case .positive: return "heart.fill"
        case .negative: return "exclamationmark.triangle.fill"
        case .neutral: return "minus.circle"
        case .thoughtful: return "brain.head.profile"
        case .questioning: return "questionmark.circle.fill"
        case .encouraging: return "hands.sparkles.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .positive, .encouraging: return .green
        case .negative: return .red
        case .neutral: return .gray
        case .thoughtful: return .purple
        case .questioning: return .blue
        }
    }
}

// MARK: - Comment Insights

struct CommentInsights {
    var sentiment: CommentSentiment
    var toxicityScore: Double // 0.0 to 1.0
    var containsQuestion: Bool
    var mentionsScripture: Bool
    var isEncouraging: Bool
    var wordCount: Int
    var readingTime: Int // seconds
    
    var shouldWarn: Bool {
        toxicityScore > 0.7
    }
    
    var shouldFlag: Bool {
        toxicityScore > 0.85
    }
}

// MARK: - AI Service

class CommentAIService {
    static let shared = CommentAIService()
    
    private let sentimentPredictor = NLModel(mlModel: try! NLModel(contentsOf: NLModel.sentimentModel))
    
    // Analyze comment text
    func analyzeComment(_ text: String) -> CommentInsights {
        let sentiment = detectSentiment(text)
        let toxicity = detectToxicity(text)
        let hasQuestion = text.contains("?")
        let hasScripture = detectScriptureReference(text)
        let isEncouraging = detectEncouragement(text)
        let words = text.split(separator: " ").count
        let readTime = max(words / 200, 1) // ~200 words per minute
        
        return CommentInsights(
            sentiment: sentiment,
            toxicityScore: toxicity,
            containsQuestion: hasQuestion,
            mentionsScripture: hasScripture,
            isEncouraging: isEncouraging,
            wordCount: words,
            readingTime: readTime
        )
    }
    
    // MARK: - Detection Methods
    
    private func detectSentiment(_ text: String) -> CommentSentiment {
        // Use NaturalLanguage framework
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (sentiment, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        // Check for questions
        if text.contains("?") {
            return .questioning
        }
        
        // Check for encouraging words
        let encouragingWords = ["amen", "blessed", "praise", "glory", "hallelujah", "grateful", "thankful", "encouraged"]
        if encouragingWords.contains(where: { text.lowercased().contains($0) }) {
            return .encouraging
        }
        
        // Check for thoughtful indicators
        let thoughtfulWords = ["because", "therefore", "however", "consider", "reflect", "ponder"]
        if thoughtfulWords.contains(where: { text.lowercased().contains($0) }) {
            return .thoughtful
        }
        
        // Parse sentiment score
        if let sentimentValue = Double(sentiment?.rawValue ?? "0") {
            if sentimentValue > 0.3 {
                return .positive
            } else if sentimentValue < -0.3 {
                return .negative
            }
        }
        
        return .neutral
    }
    
    private func detectToxicity(_ text: String) -> Double {
        let lowercased = text.lowercased()
        
        // Common toxic patterns
        let toxicWords = [
            "hate", "stupid", "dumb", "idiot", "fool", "shut up",
            "damn", "hell", "crap", "suck", "loser", "pathetic"
        ]
        
        // Profanity filter (basic)
        let profanity = [
            // Add profanity list (censored for code)
        ]
        
        var toxicityScore = 0.0
        
        // Check for toxic words
        for word in toxicWords {
            if lowercased.contains(word) {
                toxicityScore += 0.15
            }
        }
        
        // Check for profanity
        for word in profanity {
            if lowercased.contains(word) {
                toxicityScore += 0.3
            }
        }
        
        // Check for ALL CAPS (shouting)
        let uppercaseRatio = Double(text.filter { $0.isUppercase }.count) / Double(text.count)
        if uppercaseRatio > 0.6 && text.count > 10 {
            toxicityScore += 0.1
        }
        
        // Check for excessive punctuation
        let exclamationCount = text.filter { $0 == "!" }.count
        if exclamationCount > 3 {
            toxicityScore += 0.05
        }
        
        return min(toxicityScore, 1.0)
    }
    
    private func detectScriptureReference(_ text: String) -> Bool {
        // Common book names
        let books = [
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
            "Joshua", "Judges", "Ruth", "Samuel", "Kings", "Chronicles",
            "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song", "Isaiah", "Jeremiah", "Lamentations",
            "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah",
            "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai",
            "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John",
            "Acts", "Romans", "Corinthians", "Galatians", "Ephesians",
            "Philippians", "Colossians", "Thessalonians", "Timothy",
            "Titus", "Philemon", "Hebrews", "James", "Peter", "Revelation"
        ]
        
        for book in books {
            if text.contains(book) {
                return true
            }
        }
        
        // Check for chapter:verse pattern (e.g., "3:16")
        let pattern = "\\d+:\\d+"
        if let _ = text.range(of: pattern, options: .regularExpression) {
            return true
        }
        
        return false
    }
    
    private func detectEncouragement(_ text: String) -> Bool {
        let encouragingWords = [
            "encourage", "blessed", "praise", "thankful", "grateful",
            "inspiring", "uplifting", "beautiful", "powerful", "amazing",
            "wonderful", "excellent", "brilliant", "outstanding", "love this"
        ]
        
        let lowercased = text.lowercased()
        return encouragingWords.contains { lowercased.contains($0) }
    }
    
    // Generate summary of comments
    func generateCommentsSummary(_ comments: [Comment]) -> String {
        guard !comments.isEmpty else {
            return "No comments yet"
        }
        
        let total = comments.count
        
        // Analyze sentiments
        var positiveCount = 0
        var questionCount = 0
        var encouragingCount = 0
        
        for comment in comments {
            let insights = analyzeComment(comment.content)
            
            switch insights.sentiment {
            case .positive, .encouraging:
                positiveCount += 1
            case .questioning:
                questionCount += 1
            default:
                break
            }
            
            if insights.isEncouraging {
                encouragingCount += 1
            }
        }
        
        // Build summary
        var parts: [String] = []
        
        if positiveCount > total / 2 {
            parts.append("\(positiveCount) people sharing encouragement")
        }
        
        if questionCount > 0 {
            parts.append("\(questionCount) \(questionCount == 1 ? "question" : "questions") asked")
        }
        
        if encouragingCount > 0 {
            parts.append("\(encouragingCount) uplifting \(encouragingCount == 1 ? "comment" : "comments")")
        }
        
        if parts.isEmpty {
            return "\(total) \(total == 1 ? "comment" : "comments")"
        }
        
        return parts.joined(separator: " • ")
    }
}

// MARK: - AI-Enhanced Comments View

struct AIEnhancedCommentsView: View {
    let post: Post
    
    @StateObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService.shared
    @StateObject private var aiService = CommentAIService.shared
    
    @State private var commentText = ""
    @State private var replyingTo: Comment?
    @State private var commentsWithReplies: [CommentWithReplies] = []
    @State private var commentInsights: CommentInsights?
    @State private var showToxicityWarning = false
    @State private var showAISummary = true
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with AI Summary
            VStack(spacing: 12) {
                HStack {
                    Text("Comments")
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.black)
                    
                    Text("\(commentsWithReplies.count)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.black.opacity(0.6))
                    
                    Spacer()
                    
                    // AI toggle
                    Button {
                        withAnimation {
                            showAISummary.toggle()
                        }
                    } label: {
                        Image(systemName: showAISummary ? "brain.head.profile.fill" : "brain.head.profile")
                            .font(.system(size: 16))
                            .foregroundStyle(.purple)
                    }
                }
                
                // AI Summary
                if showAISummary && !commentsWithReplies.isEmpty {
                    let allComments = commentsWithReplies.flatMap { [$0.comment] + $0.replies }
                    AISummaryBanner(summary: aiService.generateCommentsSummary(allComments))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 0.98, green: 0.98, blue: 0.98))
            
            Divider()
            
            // Comments List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commentsWithReplies) { commentWithReplies in
                        AIEnhancedCommentCell(
                            commentWithReplies: commentWithReplies,
                            onReply: { comment in
                                replyingTo = comment
                                isInputFocused = true
                            },
                            onDelete: { comment in
                                // Delete logic
                            },
                            onAmen: { comment in
                                // Amen logic
                            }
                        )
                        
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            
            Divider()
            
            // Enhanced Input Area with AI
            VStack(spacing: 0) {
                // AI Insights Bar
                if let insights = commentInsights {
                    AIInsightsBar(insights: insights)
                }
                
                // Toxicity Warning
                if showToxicityWarning {
                    ToxicityWarningBanner()
                }
                
                // Replying indicator
                if let replyingTo = replyingTo {
                    ReplyIndicator(username: replyingTo.authorUsername, onDismiss: {
                        self.replyingTo = nil
                    })
                }
                
                // Input field
                HStack(alignment: .bottom, spacing: 12) {
                    Circle()
                        .fill(.black.opacity(0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(userService.currentUser?.initials ?? "??")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.black.opacity(0.6))
                        )
                    
                    TextField(replyingTo != nil ? "Write a reply..." : "Add a comment...", text: $commentText, axis: .vertical)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .onChange(of: commentText) { oldValue, newValue in
                            analyzeCommentInRealTime(newValue)
                        }
                    
                    Button {
                        submitComment()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(commentText.isEmpty ? .black.opacity(0.3) : .black)
                    }
                    .disabled(commentText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
            }
        }
        .background(Color.white)
    }
    
    // MARK: - Actions
    
    private func analyzeCommentInRealTime(_ text: String) {
        guard !text.isEmpty else {
            commentInsights = nil
            showToxicityWarning = false
            return
        }
        
        commentInsights = aiService.analyzeComment(text)
        
        if let insights = commentInsights, insights.shouldWarn {
            withAnimation {
                showToxicityWarning = true
            }
        } else {
            withAnimation {
                showToxicityWarning = false
            }
        }
    }
    
    private func submitComment() {
        guard !commentText.isEmpty else { return }
        
        // Check if should be flagged
        if let insights = commentInsights, insights.shouldFlag {
            // Show confirmation dialog
            return
        }
        
        // Submit comment
        let text = commentText
        commentText = ""
        commentInsights = nil
        showToxicityWarning = false
        
        // ... submit logic
    }
}

// MARK: - AI Summary Banner

struct AISummaryBanner: View {
    let summary: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
            
            Text(summary)
                .font(.custom("OpenSans-Medium", size: 13))
                .foregroundStyle(.black.opacity(0.7))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - AI Insights Bar

struct AIInsightsBar: View {
    let insights: CommentInsights
    
    var body: some View {
        HStack(spacing: 12) {
            // Sentiment indicator
            HStack(spacing: 4) {
                Image(systemName: insights.sentiment.icon)
                    .font(.system(size: 12))
                Text(insights.sentiment.rawValue)
                    .font(.custom("OpenSans-Medium", size: 11))
            }
            .foregroundStyle(insights.sentiment.color)
            
            Divider()
                .frame(height: 16)
            
            // Word count
            Text("\(insights.wordCount) words")
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.black.opacity(0.5))
            
            if insights.mentionsScripture {
                Divider()
                    .frame(height: 16)
                
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 11))
                    Text("Scripture")
                        .font(.custom("OpenSans-Medium", size: 11))
                }
                .foregroundStyle(.blue)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
}

// MARK: - Toxicity Warning

struct ToxicityWarningBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Consider revising your comment")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.black)
                
                Text("Your message may come across as negative or hurtful")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.black.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - AI-Enhanced Comment Cell

struct AIEnhancedCommentCell: View {
    let commentWithReplies: CommentWithReplies
    let onReply: (Comment) -> Void
    let onDelete: (Comment) -> Void
    let onAmen: (Comment) -> Void
    
    @State private var insights: CommentInsights?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main comment with sentiment indicator
            HStack(alignment: .top, spacing: 0) {
                // Sentiment indicator dot
                if let insights = insights {
                    Circle()
                        .fill(insights.sentiment.color)
                        .frame(width: 6, height: 6)
                        .padding(.leading, 16)
                        .padding(.top, 20)
                }
                
                // Comment content (your existing PostCommentRow)
                VStack(alignment: .leading, spacing: 0) {
                    // ... existing comment UI
                    
                    // AI badges
                    if let insights = insights {
                        HStack(spacing: 8) {
                            if insights.mentionsScripture {
                                InsightBadge(icon: "book.fill", text: "Scripture", color: .blue)
                            }
                            
                            if insights.isEncouraging {
                                InsightBadge(icon: "sparkles", text: "Encouraging", color: .green)
                            }
                            
                            if insights.containsQuestion {
                                InsightBadge(icon: "questionmark.circle", text: "Question", color: .purple)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            
            // Replies
            ForEach(commentWithReplies.replies, id: \.id) { reply in
                // ... existing reply UI
            }
        }
        .padding(.vertical, 12)
        .task {
            insights = CommentAIService.shared.analyzeComment(commentWithReplies.comment.content)
        }
    }
}

// MARK: - Insight Badge

struct InsightBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 10))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Reply Indicator

struct ReplyIndicator: View {
    let username: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Text("Replying to \(username.hasPrefix("@") ? username : "@\(username)")")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.6))
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
    }
}
