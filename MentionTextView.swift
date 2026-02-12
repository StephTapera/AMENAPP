//
//  MentionTextView.swift
//  AMENAPP
//
//  SwiftUI view for rendering text with clickable @mentions
//

import SwiftUI

/// Renders text with clickable @mention links
struct MentionTextView: View {
    let text: String
    let mentions: [MentionedUser]?
    let font: Font
    let lineSpacing: CGFloat
    let onMentionTap: (MentionedUser) -> Void
    
    init(
        text: String,
        mentions: [MentionedUser]? = nil,
        font: Font = .body,
        lineSpacing: CGFloat = 4,
        onMentionTap: @escaping (MentionedUser) -> Void = { _ in }
    ) {
        self.text = text
        self.mentions = mentions
        self.font = font
        self.lineSpacing = lineSpacing
        self.onMentionTap = onMentionTap
    }
    
    var body: some View {
        if let mentions = mentions, !mentions.isEmpty {
            // Text with clickable mentions
            Text(attributedText)
                .font(font)
                .lineSpacing(lineSpacing)
                .environment(\.openURL, OpenURLAction { url in
                    if let mention = mentions.first(where: { "@\($0.username)" == url.absoluteString }) {
                        onMentionTap(mention)
                        return .handled
                    }
                    return .systemAction
                })
        } else {
            // Plain text (no mentions)
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
        }
    }
    
    private var attributedText: AttributedString {
        var result = AttributedString(text)
        
        guard let mentions = mentions else {
            return result
        }
        
        // Find and style each mention
        for mention in mentions {
            let mentionText = "@\(mention.username)"
            
            // Find all occurrences of this mention
            var searchStartIndex = result.startIndex
            while searchStartIndex < result.endIndex {
                if let range = result[searchStartIndex...].range(of: mentionText) {
                    // Style the mention
                    result[range].foregroundColor = .blue
                    result[range].font = .body.bold()
                    result[range].link = URL(string: mentionText)
                    
                    // Continue searching after this match
                    searchStartIndex = range.upperBound
                } else {
                    break
                }
            }
        }
        
        return result
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        // Example 1: Text with mentions
        MentionTextView(
            text: "Hey @john and @sarah, check out this amazing feature! Thanks @david for the help.",
            mentions: [
                MentionedUser(userId: "1", username: "john", displayName: "John Doe"),
                MentionedUser(userId: "2", username: "sarah", displayName: "Sarah Smith"),
                MentionedUser(userId: "3", username: "david", displayName: "David Chen")
            ],
            font: .custom("OpenSans-Regular", size: 16),
            lineSpacing: 6
        ) { mention in
            print("Tapped mention: @\(mention.username)")
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        
        // Example 2: Text without mentions
        MentionTextView(
            text: "This is a regular post without any mentions.",
            font: .custom("OpenSans-Regular", size: 16),
            lineSpacing: 6
        )
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        
        // Example 3: Single mention
        MentionTextView(
            text: "Just wanted to say thanks to @alex for everything!",
            mentions: [
                MentionedUser(userId: "4", username: "alex", displayName: "Alex Johnson")
            ],
            font: .custom("OpenSans-Regular", size: 16),
            lineSpacing: 6
        ) { mention in
            print("Tapped: \(mention.displayName)")
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
