//
//  AIDailyVerseView.swift
//  AMENAPP
//
//  Created by AI Assistant on 1/23/26.
//
//  AI-powered daily verse display with personalized reflections
//

import SwiftUI
import Combine

// MARK: - AI Daily Verse Card

struct AIDailyVerseCard: View {
    @ObservedObject private var verseService = DailyVerseGenkitService.shared

    var body: some View {
        DailyVerseBannerView(
            verse: verseService.todayVerse,
            isLoading: verseService.isGenerating,
            onLoad: { Task { await loadDailyVerse() } }
        )
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
                        dlog("📖 Loaded cached verse from UserDefaults")
                    }
                } else {
                    // No cache, load fresh verse
                    await loadDailyVerse()
                }
            }
        }
    }

    // MARK: - Actions

    private func loadDailyVerse() async {
        _ = await verseService.generatePersonalizedDailyVerse()
    }
}

// MARK: - Daily Verse Banner (Liquid Glass)

struct DailyVerseBannerView: View {
    let verse: PersonalizedDailyVerse?
    let isLoading: Bool
    let onLoad: () -> Void

    @State private var isExpanded = false
    @State private var showSelahView = false
    @State private var didSaveToday = false

    private var dayString: String {
        String(Calendar.current.component(.day, from: Date()))
    }

    private var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                dayMonthStack

                VStack(alignment: .leading, spacing: 8) {
                    headerRow

                    if let verse {
                        VerseContentView(
                            verse: verse,
                            isExpanded: isExpanded,
                            onToggle: toggleExpanded
                        )
                    } else if isLoading {
                        loadingView
                    } else {
                        emptyStateView
                    }
                }
            }

            ExpandableSection(
                isExpanded: isExpanded,
                didSaveToday: didSaveToday,
                onSelah: { showSelahView = true },
                onSave: saveToday
            )
        }
        .padding(12)
        .background(liquidGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
        .sheet(isPresented: $showSelahView) {
            if let verse {
                SelahView(
                    message: bereanMessage(from: verse),
                    originalQuery: "Daily Verse"
                )
            }
        }
    }

    private var dayMonthStack: some View {
        VStack(spacing: 2) {
            Text(dayString)
                .font(.systemScaled(24, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
            Text(monthString)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.45))
                .tracking(1.1)
        }
        .frame(width: 44)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("DAILY VERSE")
                .font(.systemScaled(9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.black.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.5))
                )

            Spacer()

            Button(action: toggleExpanded) {
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse daily verse" : "Expand daily verse")
        }
    }

    private var liquidGlassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.85)
                .tint(Color.black.opacity(0.5))
            Text("Loading verse...")
                .font(.systemScaled(12, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.5))
        }
    }

    private var emptyStateView: some View {
        Button(action: onLoad) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.systemScaled(12, weight: .semibold))
                Text("Load Verse")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private func toggleExpanded() {
        guard verse != nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isExpanded.toggle()
        }
    }

    private func saveToday() {
        guard let verse else { return }
        didSaveToday = saveDailyVerse(verse)
    }

    private func saveDailyVerse(_ verse: PersonalizedDailyVerse) -> Bool {
        let key = "savedDailyVerses"
        let saved = loadSavedVerses(key: key)
        let today = Calendar.current.startOfDay(for: Date())

        let alreadySaved = saved.contains {
            $0.reference == verse.reference &&
            $0.text == verse.text &&
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        if alreadySaved {
            return true
        }

        let newItem = SavedDailyVerse(
            date: today,
            reference: verse.reference,
            text: verse.text
        )
        var updated = saved
        updated.insert(newItem, at: 0)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(updated) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return true
    }

    private func loadSavedVerses(key: String) -> [SavedDailyVerse] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedDailyVerse].self, from: data) else {
            return []
        }
        return decoded
    }

    private func bereanMessage(from verse: PersonalizedDailyVerse) -> BereanMessage {
        BereanMessage(
            id: UUID(),
            content: "\(verse.text)\n\n— \(verse.reference)",
            role: .assistant,
            timestamp: Date(),
            verseReferences: [verse.reference],
            feedback: nil,
            isBookmarked: false
        )
    }
}

struct VerseContentView: View {
    let verse: PersonalizedDailyVerse
    let isExpanded: Bool
    let onToggle: () -> Void

    private var collapsedLineLimit: Int {
        let count = verse.text.count
        if count < 80 { return 2 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verse.text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .truncationMode(.tail)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            Text(verse.reference)
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(Color.black.opacity(0.6))

            Text("Tap to reflect")
                .font(.custom("OpenSans-SemiBold", size: 10))
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}

struct ExpandableSection: View {
    let isExpanded: Bool
    let didSaveToday: Bool
    let onSelah: () -> Void
    let onSave: () -> Void

    var body: some View {
        if isExpanded {
            VStack(spacing: 8) {
                Button(action: onSelah) {
                    HStack {
                        Text("Selah View")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
                }
                .buttonStyle(.plain)

                Button(action: onSave) {
                    HStack {
                        Text(didSaveToday ? "Saved Today" : "Save Today")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.7))
                        Spacer()
                        Image(systemName: didSaveToday ? "checkmark" : "bookmark")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.45))
                    )
                }
                .buttonStyle(.plain)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct SavedDailyVerse: Codable, Identifiable {
    let id: UUID
    let date: Date
    let reference: String
    let text: String

    init(id: UUID = UUID(), date: Date, reference: String, text: String) {
        self.id = id
        self.date = date
        self.reference = reference
        self.text = text
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
                                    .font(.systemScaled(30))
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
