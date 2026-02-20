//
//  ThreadSummaryView.swift
//  AMENAPP
//
//  AI-powered thread summary display for long comment threads
//

import SwiftUI

struct ThreadSummaryView: View {
    let summary: AIThreadSummarizationService.ThreadSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with sentiment emoji
            HStack(spacing: 8) {
                Text(summary.sentimentEmoji)
                    .font(.system(size: 18))
                
                Text("Thread Summary")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(summary.totalReplies) replies")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            // Summary text
            Text(summary.summary)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(2)
            
            // Key points
            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.keyPoints, id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                    }
                }
            }
            
            // Key participants
            if !summary.keyParticipants.isEmpty {
                HStack(spacing: 4) {
                    Text("Key voices:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    
                    Text(summary.keyParticipants.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
