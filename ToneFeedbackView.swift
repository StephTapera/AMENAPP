//
//  ToneFeedbackView.swift
//  AMENAPP
//
//  Real-time tone guidance feedback for comment input
//

import SwiftUI

struct ToneFeedbackView: View {
    let feedback: AIToneGuidanceService.ToneFeedback
    let onUseSuggestion: (() -> Void)?
    
    init(feedback: AIToneGuidanceService.ToneFeedback, onUseSuggestion: (() -> Void)? = nil) {
        self.feedback = feedback
        self.onUseSuggestion = onUseSuggestion
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack(spacing: 8) {
                Image(systemName: feedback.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(feedbackColor)
                
                Text(feedback.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }
            
            // Suggestion (if present)
            if let suggestion = feedback.suggestion {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestion:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if onUseSuggestion != nil {
                            Button {
                                onUseSuggestion?()
                            } label: {
                                Text("Use")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            
            // Scripture reference (if present)
            if let scripture = feedback.scriptureReference {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
                    Text(scripture)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
    
    private var feedbackColor: Color {
        switch feedback.type {
        case .warning:
            return .orange
        case .caution:
            return .blue
        case .encouragement:
            return .green
        case .flagged:
            return .red
        }
    }
    
    private var backgroundColor: Color {
        switch feedback.type {
        case .warning:
            return Color.orange.opacity(0.05)
        case .caution:
            return Color.blue.opacity(0.05)
        case .encouragement:
            return Color.green.opacity(0.05)
        case .flagged:
            return Color.red.opacity(0.05)
        }
    }
    
    private var borderColor: Color {
        switch feedback.type {
        case .warning:
            return Color.orange.opacity(0.2)
        case .caution:
            return Color.blue.opacity(0.2)
        case .encouragement:
            return Color.green.opacity(0.2)
        case .flagged:
            return Color.red.opacity(0.2)
        }
    }
}
