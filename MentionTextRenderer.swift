//
//  MentionTextRenderer.swift
//  AMENAPP
//
//  Created by AI Assistant on 2/12/26.
//

import SwiftUI

// MARK: - Mention Text Renderer

/// Renders text with clickable mentions highlighted
struct MentionText: View {
    let text: String
    let mentions: [MentionedUser]?
    let font: Font
    let color: Color
    let mentionColor: Color
    let onMentionTap: ((String) -> Void)?
    
    init(
        _ text: String,
        mentions: [MentionedUser]? = nil,
        font: Font = .body,
        color: Color = .primary,
        mentionColor: Color = .blue,
        onMentionTap: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.mentions = mentions
        self.font = font
        self.color = color
        self.mentionColor = mentionColor
        self.onMentionTap = onMentionTap
    }
    
    var body: some View {
        if let mentions = mentions, !mentions.isEmpty {
            renderWithMentions()
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
        }
    }
    
    @ViewBuilder
    private func renderWithMentions() -> some View {
        let attributedText = createAttributedText()
        Text(attributedText)
    }
    
    private func createAttributedText() -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Detect all @mentions in text
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return attributedString
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches.reversed() { // Process in reverse to maintain indices
            let matchRange = match.range
            let username = nsString.substring(with: match.range(at: 1))
            
            // Check if this username is in our mentions list
            if mentions?.contains(where: { $0.username == username }) == true {
                // Convert NSRange to String.Index range
                if let range = Range(matchRange, in: text) {
                    let attributedRange = AttributedString.Index(range.lowerBound, within: attributedString)
                    let attributedEndRange = AttributedString.Index(range.upperBound, within: attributedString)
                    
                    if let start = attributedRange, let end = attributedEndRange {
                        attributedString[start..<end].foregroundColor = mentionColor
                    }
                }
            }
        }
        
        return attributedString
    }
}

// MARK: - Text View Extension for Mentions

extension Text {
    /// Create a Text view with highlighted mentions
    static func withMentions(
        _ text: String,
        mentions: [MentionedUser]?,
        font: Font = .body,
        textColor: Color = .primary,
        mentionColor: Color = .blue
    ) -> Text {
        guard let mentions = mentions, !mentions.isEmpty else {
            return Text(text).font(font).foregroundStyle(textColor)
        }
        
        // Detect all @mentions in text
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return Text(text).font(font).foregroundStyle(textColor)
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var result = Text("")
        var lastIndex = 0
        
        for match in matches {
            let matchRange = match.range
            let username = nsString.substring(with: match.range(at: 1))
            
            // Add text before mention
            if matchRange.location > lastIndex {
                let beforeRange = NSRange(location: lastIndex, length: matchRange.location - lastIndex)
                let beforeText = nsString.substring(with: beforeRange)
                result = result + Text(beforeText).font(font).foregroundStyle(textColor)
            }
            
            // Check if this username is in our mentions list
            if mentions.contains(where: { $0.username == username }) {
                let mentionText = nsString.substring(with: matchRange)
                result = result + Text(mentionText)
                    .font(font)
                    .fontWeight(.semibold)
                    .foregroundStyle(mentionColor)
            } else {
                let mentionText = nsString.substring(with: matchRange)
                result = result + Text(mentionText).font(font).foregroundStyle(textColor)
            }
            
            lastIndex = matchRange.location + matchRange.length
        }
        
        // Add remaining text
        if lastIndex < nsString.length {
            let remainingRange = NSRange(location: lastIndex, length: nsString.length - lastIndex)
            let remainingText = nsString.substring(with: remainingRange)
            result = result + Text(remainingText).font(font).foregroundStyle(textColor)
        }
        
        return result
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        Text.withMentions(
            "Hey @john and @jane, check this out!",
            mentions: [
                MentionedUser(userId: "1", username: "john", displayName: "John Doe"),
                MentionedUser(userId: "2", username: "jane", displayName: "Jane Smith")
            ],
            font: .body,
            textColor: .primary,
            mentionColor: .blue
        )
        
        Text.withMentions(
            "Thanks @sarah for the prayer!",
            mentions: [
                MentionedUser(userId: "3", username: "sarah", displayName: "Sarah")
            ],
            font: .custom("OpenSans-Regular", size: 15),
            textColor: .black,
            mentionColor: .purple
        )
        
        Text.withMentions(
            "No mentions here",
            mentions: nil,
            font: .body,
            textColor: .primary,
            mentionColor: .blue
        )
    }
    .padding()
}
