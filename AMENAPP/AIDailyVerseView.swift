//
//  AIDailyVerseView.swift
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - simple black and white
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.2))
                        )

                    Text("Daily Verse")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.white)
                }

                Spacer()

                Menu {
                    Button {
                        refreshVerse()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        shareVerse()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.15))
                        )
                }
            }
            .padding(12)
            
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
            ZStack {
                // Black and white liquid glass base
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.6),
                                        Color.black.opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                // Subtle white glass overlay
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )

                // Glass border
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .task {
            // ✅ FIXED: Load cached verse first to prevent crash
            // Try to load from cache
            if verseService.todayVerse == nil {
                // First attempt to load from UserDefaults cache
                if let data = UserDefaults.standard.data(forKey: "cachedDailyVerse"),
                   let date = UserDefaults.standard.object(forKey: "cachedVerseDate") as? Date,
                   Calendar.current.isDate(date, inSameDayAs: Date()),
                   let verse = try? JSONDecoder().decode(PersonalizedDailyVerse.self, from: data) {
                    await MainActor.run {
                        verseService.todayVerse = verse
                        print("📖 Loaded cached verse from UserDefaults")
                    }
                } else {
                    // No cache, load fresh verse
                    await loadDailyVerse()
                }
            }
        }
    }
    
    // MARK: - Verse Content

    @ViewBuilder
    private func verseContent(_ verse: PersonalizedDailyVerse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Verse Text - simple and clean
            Text(verse.text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Reference
            Text("— \(verse.reference)")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    
    // MARK: - Loading View

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.white)

            Text("Loading verse...")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.4))

            Text("No verse loaded")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.white)

            Button("Load Verse") {
                Task {
                    await loadDailyVerse()
                }
            }
            .font(.custom("OpenSans-SemiBold", size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Actions
    
    private func loadDailyVerse() async {
        _ = await verseService.generatePersonalizedDailyVerse()
    }
    
    private func refreshVerse() {
        Task {
            _ = await verseService.generatePersonalizedDailyVerse(forceRefresh: true)
        }
    }
    
    private func loadThemedVerse(theme: VerseTheme) {
        Task {
            let verse = await verseService.generateThemedVerse(theme: theme)
            await MainActor.run {
                verseService.todayVerse = verse
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
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
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
