//
//  PostFeedActions.swift
//  AMENAPP
//
//  Post menu actions for Hey Feed:
//  - Why am I seeing this?
//  - More like this
//  - Less like this
//  - Hide this topic
//  - Mute this author
//

import SwiftUI

// MARK: - Why Am I Seeing This Sheet

struct WhyAmISeeingThisSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: Post
    let reasons: [FeedReason]
    @State private var showFeedControls = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text("Why you're seeing this")
                        .font(.title2.weight(.bold))
                    
                    Text("Based on your activity and preferences")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                Divider()
                
                // Reasons List
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(reasons) { reason in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: reason.icon)
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reasonTitle(for: reason.type))
                                        .font(.subheadline.weight(.medium))
                                    
                                    Text(reason.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Footer Actions
                VStack(spacing: 12) {
                    Button {
                        showFeedControls = true
                    } label: {
                        Text("Adjust Feed Preferences")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Got it")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showFeedControls) {
                HeyFeedControlsSheet()
            }
        }
    }

    private func reasonTitle(for type: FeedReason.ReasonType) -> String {
        switch type {
        case .followedAuthor: return "You follow this person"
        case .topicMatch: return "Matches your interests"
        case .engagement: return "Popular with people you follow"
        case .local: return "From your community"
        case .recency: return "Recent post"
        case .discovery: return "Discovery suggestion"
        case .boosted: return "You boosted similar content"
        }
    }
}

// MARK: - Post Feed Actions Menu

struct PostFeedActionsMenu: View {
    let post: Post
    @ObservedObject private var prefsService = HeyFeedPreferencesService.shared
    @State private var showWhyAmISeeingThis = false
    @State private var showConfirmMute = false
    @State private var showFeedbackToast = false
    @State private var feedbackMessage = ""
    
    var body: some View {
        Group {
            // Why am I seeing this?
            Button {
                showWhyAmISeeingThis = true
            } label: {
                Label("Why am I seeing this?", systemImage: "lightbulb")
            }
            
            Divider()
            
            // More like this
            Button {
                Task {
                    await prefsService.recordMoreLikeThis(
                        postId: post.firebaseId ?? post.id.uuidString,
                        authorId: post.authorId
                    )
                    showFeedback("We'll show you more like this")
                }
            } label: {
                Label("More like this", systemImage: "hand.thumbsup")
            }
            
            // Less like this
            Button {
                Task {
                    await prefsService.recordLessLikeThis(
                        postId: post.firebaseId ?? post.id.uuidString,
                        authorId: post.authorId
                    )
                    showFeedback("We'll show you less like this")
                }
            } label: {
                Label("Less like this", systemImage: "hand.thumbsdown")
            }
            
            Divider()
            
            // Hide this post
            Button(role: .destructive) {
                Task {
                    await prefsService.hidePost(post.firebaseId ?? post.id.uuidString)
                    showFeedback("Post hidden")
                }
            } label: {
                Label("Hide this post", systemImage: "eye.slash")
            }
            
            // Mute author
            Button(role: .destructive) {
                showConfirmMute = true
            } label: {
                Label("Mute @\(post.authorUsername ?? post.authorName)", systemImage: "speaker.slash")
            }
        }
        .sheet(isPresented: $showWhyAmISeeingThis) {
            WhyAmISeeingThisSheet(
                post: post,
                reasons: generateReasons(for: post)
            )
        }
        .confirmationDialog(
            "Mute \(post.authorName)?",
            isPresented: $showConfirmMute,
            titleVisibility: .visible
        ) {
            Button("Mute", role: .destructive) {
                Task {
                    await prefsService.muteAuthor(post.authorId)
                    showFeedback("@\(post.authorUsername ?? post.authorName) muted")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see posts from this person in your feed")
        }
        .overlay(alignment: .top) {
            if showFeedbackToast {
                FeedbackToast(message: feedbackMessage)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private func showFeedback(_ message: String) {
        feedbackMessage = message
        withAnimation(.spring(response: 0.3)) {
            showFeedbackToast = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.3)) {
                showFeedbackToast = false
            }
        }
    }
    
    private func generateReasons(for post: Post) -> [FeedReason] {
        var reasons: [FeedReason] = []
        let algorithm = HomeFeedAlgorithm.shared
        let prefs = HeyFeedPreferencesService.shared.preferences
        let interests = algorithm.userInterests
        let followingIds = FollowService.shared.following

        // Reason: followed author
        if followingIds.contains(post.authorId) {
            reasons.append(FeedReason(
                type: .followedAuthor,
                description: "You follow \(post.authorName)"
            ))
        }

        // Reason: topic/interest match
        if let topicTag = post.topicTag,
           let score = interests.engagedTopics[topicTag], score > 50 {
            reasons.append(FeedReason(
                type: .topicMatch,
                description: "You often engage with #\(topicTag) content"
            ))
        } else {
            // Fall back to category-level interest
            let categoryKey = post.category.rawValue
            if let pref = interests.preferredCategories[categoryKey], pref > 50 {
                reasons.append(FeedReason(
                    type: .topicMatch,
                    description: "You often engage with \(post.category.displayName) content"
                ))
            }
        }

        // Reason: goal alignment
        for goal in interests.onboardingGoals {
            let goalKeywords: [String: [String]] = [
                "Consistent Prayer": ["prayer", "pray"],
                "Daily Bible Reading": ["scripture", "bible", "verse"],
                "Build Community": ["community", "fellowship", "church"],
                "Grow in Faith": ["faith", "spiritual", "testimony"],
                "Share the Gospel": ["gospel", "witness", "testimony"],
                "Serve Others": ["serve", "service", "ministry"]
            ]
            if let kws = goalKeywords[goal],
               kws.contains(where: { post.content.lowercased().contains($0) }) {
                reasons.append(FeedReason(
                    type: .topicMatch,
                    description: "Aligns with your goal: \(goal)"
                ))
                break
            }
        }

        // Reason: engagement by people you follow
        let engagementCount = post.amenCount + post.commentCount
        if engagementCount > 5 {
            reasons.append(FeedReason(
                type: .engagement,
                description: "Popular in your community (\(engagementCount) interactions)"
            ))
        }

        // Reason: recency
        let hoursSince = Date().timeIntervalSince(post.createdAt) / 3600
        if hoursSince < 6 {
            reasons.append(FeedReason(
                type: .recency,
                description: "Posted \(hoursSince < 1 ? "just now" : "\(Int(hoursSince))h ago")"
            ))
        }

        // Reason: boosted author
        if prefs.boostedAuthors.contains(post.authorId) {
            reasons.append(FeedReason(
                type: .boosted,
                description: "You boosted content from \(post.authorName)"
            ))
        }

        // Fallback: discovery
        if reasons.isEmpty {
            reasons.append(FeedReason(
                type: .discovery,
                description: "Suggested based on what's popular in the AMEN community"
            ))
        }

        return reasons
    }
}

// MARK: - Feedback Toast

struct FeedbackToast: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Think First Guardrail Prompt

struct ThinkFirstPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let checkResult: ThinkFirstGuardrailsService.ContentCheckResult
    let originalText: String
    let onRevise: (String) -> Void
    let onProceed: () -> Void
    
    @State private var revisedText: String
    
    init(
        checkResult: ThinkFirstGuardrailsService.ContentCheckResult,
        originalText: String,
        onRevise: @escaping (String) -> Void,
        onProceed: @escaping () -> Void
    ) {
        self.checkResult = checkResult
        self.originalText = originalText
        self.onRevise = onRevise
        self.onProceed = onProceed
        _revisedText = State(initialValue: originalText)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon based on action type
                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundColor(iconColor)
                    .padding(.top, 24)
                
                // Title
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                
                // Message
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Violations
                if !checkResult.violations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(checkResult.violations.enumerated()), id: \.offset) { _, violation in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(violationColor(violation.severity))
                                Text(violation.message)
                                    .font(.caption)
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Redactions (one-tap fix for PII)
                if !checkResult.redactions.isEmpty {
                    VStack(spacing: 12) {
                        Text("Suggested fixes:")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        
                        Button {
                            let redactedText = ThinkFirstGuardrailsService.shared.applyRedactions(
                                originalText,
                                redactions: checkResult.redactions
                            )
                            revisedText = redactedText
                        } label: {
                            Label("Remove personal information", systemImage: "checkmark.shield")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Suggestions
                if !checkResult.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(checkResult.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(suggestion)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    if checkResult.action == .block {
                        // Can't proceed
                        Button {
                            dismiss()
                        } label: {
                            Text("Go back")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    } else {
                        // Can proceed
                        if checkResult.action == .softPrompt {
                            Button {
                                dismiss()
                                onProceed()
                            } label: {
                                Text("Post anyway")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        
                        Button {
                            dismiss()
                            onRevise(revisedText)
                        } label: {
                            Text(checkResult.action == .requireEdit ? "Edit" : "Revise")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var iconName: String {
        switch checkResult.action {
        case .allow: return "checkmark.circle.fill"
        case .softPrompt: return "exclamationmark.triangle.fill"
        case .requireEdit: return "pencil.circle.fill"
        case .block: return "xmark.octagon.fill"
        }
    }
    
    private var iconColor: Color {
        switch checkResult.action {
        case .allow: return .green
        case .softPrompt: return .orange
        case .requireEdit: return .yellow
        case .block: return .red
        }
    }
    
    private var title: String {
        switch checkResult.action {
        case .allow: return "Looks good!"
        case .softPrompt: return "Want to rephrase?"
        case .requireEdit: return "Please revise"
        case .block: return "Can't post this"
        }
    }
    
    private var message: String {
        switch checkResult.action {
        case .allow:
            return "Your post is ready to share"
        case .softPrompt:
            return "This might come across differently than you intended"
        case .requireEdit:
            return "A few things to fix before posting"
        case .block:
            return "This content violates our community guidelines"
        }
    }
    
    private func violationColor(_ severity: ThinkFirstGuardrailsService.ContentCheckResult.Violation.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .red
        }
    }
}
