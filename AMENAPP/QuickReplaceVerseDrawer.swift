//
//  QuickReplaceVerseDrawer.swift
//  AMENAPP
//
//  Lightweight drawer for quickly replacing attached scripture
//  without reopening the full search sheet.
//  Shows related verses, recent, and a search field.
//

import SwiftUI

struct QuickReplaceVerseDrawer: View {
    let currentAttachment: ScriptureAttachment
    let replaceResults: [BibleVerse]
    let onReplace: (BibleVerse) -> Void
    let onOpenFullSearch: () -> Void
    let onDismiss: () -> Void
    
    @State private var quickSearchText = ""
    @State private var quickSearchResults: [SmartVerseResult] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool
    
    @StateObject private var searchEngine = VerseSmartSearchEngine()
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            GlassDragHandle()
            
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace Scripture")
                        .font(.systemScaled(17, weight: .bold))
                        .foregroundStyle(Color.primary)
                    
                    Text("Currently: \(currentAttachment.displayReference)")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            // Quick search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color.secondary)
                
                TextField("Search for a verse...", text: $quickSearchText)
                    .font(.systemScaled(14))
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { performQuickSearch() }
                    .onChange(of: quickSearchText) { _, _ in
                        performQuickSearch()
                    }
                
                if !quickSearchText.isEmpty {
                    Button {
                        quickSearchText = ""
                        quickSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Results
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if !quickSearchResults.isEmpty {
                        // Search results
                        ForEach(quickSearchResults.prefix(8)) { result in
                            quickReplaceRow(verse: result.verse)
                        }
                    } else if !quickSearchText.isEmpty && !isSearching {
                        // No results
                        VStack(spacing: 8) {
                            Text("No results")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            Text("Try a reference like \"John 3:16\" or a topic like \"peace\"")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Suggested replacements
                        if !replaceResults.isEmpty {
                            sectionHeader("Suggested")
                            ForEach(replaceResults.prefix(6), id: \.reference) { verse in
                                quickReplaceRow(verse: verse)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            
            // Full search fallback
            Button(action: onOpenFullSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(13, weight: .medium))
                    Text("Open Full Search")
                        .font(.systemScaled(14, weight: .semibold))
                }
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: VerseGlassTokens.radiusXL, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: VerseGlassTokens.radiusXL, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: VerseGlassTokens.radiusXL, style: .continuous)
                        .strokeBorder(VerseGlassTokens.glassStroke, lineWidth: 0.5)
                }
        )
        .shadow(color: Color.black.opacity(0.15), radius: 30, y: -5)
    }
    
    // MARK: - Row
    
    private func quickReplaceRow(verse: BibleVerse) -> some View {
        Button {
            onReplace(verse)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verse.reference)
                            .font(.systemScaled(13, weight: .bold))
                            .foregroundStyle(Color.primary)
                        
                        Text(verse.translation)
                            .font(.systemScaled(9, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    
                    if !verse.text.isEmpty {
                        Text(verse.text)
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.primary.opacity(0.65))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: VerseGlassTokens.radiusSmall, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replace with \(verse.reference)")
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.systemScaled(11, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
    
    // MARK: - Search
    
    private func performQuickSearch() {
        let query = quickSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            quickSearchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            
            let baseVM = AttachVerseViewModel()
            await searchEngine.search(query: query, translation: .NIV, baseViewModel: baseVM)
            
            quickSearchResults = searchEngine.results
            isSearching = false
        }
    }
}
