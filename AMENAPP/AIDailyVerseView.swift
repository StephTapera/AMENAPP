//
//  AIDaily VerseView.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  AI-powered daily verse display with personalized reflections
//

import SwiftUI

// MARK: - AI Daily Verse Card

struct AIDailyVerseCard: View {
    @StateObject private var verseService = DailyVerseGenkitService.shared
    @State private var isExpanded = false
    @State private var showThemePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.blue)
                    
                    Text("Your Daily Verse")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                }
                
                Spacer()
                
                Menu {
                    Button {
                        refreshVerse()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Button {
                        showThemePicker = true
                    } label: {
                        Label("Choose Theme", systemImage: "list.bullet")
                    }
                    
                    Button {
                        shareVerse()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            // Verse Content
            if let verse = verseService.todayVerse {
                verseContent(verse)
            } else if verseService.isGenerating {
                loadingView
            } else {
                emptyStateView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        )
        .padding(.horizontal)
        .sheet(isPresented: $showThemePicker) {
            ThemePickerSheet { theme in
                loadThemedVerse(theme: theme)
            }
        }
        .task {
            if verseService.todayVerse == nil {
                await loadDailyVerse()
            }
        }
    }
    
    // MARK: - Verse Content
    
    @ViewBuilder
    private func verseContent(_ verse: PersonalizedDailyVerse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Theme Tag
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
                
                Text(verse.theme)
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.purple)
                
                Spacer()
                
                Text(verse.date, style: .date)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Verse Text
            VStack(alignment: .leading, spacing: 8) {
                Text(verse.text)
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                
                Text("— \(verse.reference)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
            )
            .padding(.horizontal)
            
            // Reflection Section
            if isExpanded {
                expandedContent(verse)
            } else {
                // Show More Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("See AI Reflection & Action")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.purple)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.05))
                    )
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }
    
    @ViewBuilder
    private func expandedContent(_ verse: PersonalizedDailyVerse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.horizontal)
            
            // AI Reflection
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                    Text("AI Reflection")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
                
                Text(verse.reflection)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
            }
            .padding(.horizontal)
            
            // Action Prompt
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .foregroundStyle(.orange)
                    Text("Today's Action")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
                
                Text(verse.actionPrompt)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.orange)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.05))
            )
            .padding(.horizontal)
            
            // Prayer Prompt
            if !verse.prayerPrompt.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "hands.sparkles.fill")
                            .foregroundStyle(.green)
                        Text("Prayer Prompt")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                    
                    Text(verse.prayerPrompt)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .italic()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.05))
                )
                .padding(.horizontal)
            }
            
            // Related Verses
            if !verse.relatedVerses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Verses")
                        .font(.custom("OpenSans-Bold", size: 14))
                    
                    FlowLayout(spacing: 8) {
                        ForEach(verse.relatedVerses, id: \.self) { ref in
                            RelatedVerseChip(reference: ref)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Collapse Button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded = false
                }
            } label: {
                HStack {
                    Text("Show Less")
                    Spacer()
                    Image(systemName: "chevron.up")
                }
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.secondary)
                .padding()
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.blue)
            
            Text("Generating your personalized verse...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 50))
                .foregroundStyle(.blue.opacity(0.3))
            
            Text("No verse loaded")
                .font(.custom("OpenSans-Bold", size: 16))
            
            Button("Load Today's Verse") {
                Task {
                    await loadDailyVerse()
                }
            }
            .font(.custom("OpenSans-SemiBold", size: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Actions
    
    private func loadDailyVerse() async {
        do {
            _ = try await verseService.generatePersonalizedDailyVerse()
        } catch {
            print("❌ Error loading daily verse: \(error)")
        }
    }
    
    private func refreshVerse() {
        Task {
            do {
                _ = try await verseService.generatePersonalizedDailyVerse(forceRefresh: true)
            } catch {
                print("❌ Error refreshing verse: \(error)")
            }
        }
    }
    
    private func loadThemedVerse(theme: VerseTheme) {
        Task {
            do {
                let verse = try await verseService.generateThemedVerse(theme: theme)
                await MainActor.run {
                    verseService.todayVerse = verse
                }
            } catch {
                print("❌ Error loading themed verse: \(error)")
            }
        }
    }
    
    private func shareVerse() {
        guard let verse = verseService.todayVerse else { return }
        
        let shareText = """
        \(verse.text)
        — \(verse.reference)
        
        \(verse.reflection)
        
        Shared from AMEN App
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Theme Picker Sheet

struct ThemePickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let onThemeSelected: (VerseTheme) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(VerseTheme.allCases, id: \.self) { theme in
                        Button {
                            onThemeSelected(theme)
                            dismiss()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: theme.icon)
                                    .font(.system(size: 30))
                                    .foregroundStyle(.blue)
                                
                                Text(theme.rawValue)
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.primary)
                                
                                Text(theme.description)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose a Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Related Verse Chip

struct RelatedVerseChip: View {
    let reference: String
    
    var body: some View {
        Text(reference)
            .font(.custom("OpenSans-SemiBold", size: 12))
            .foregroundStyle(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AIDailyVerseCard()
            .padding(.top)
    }
}
