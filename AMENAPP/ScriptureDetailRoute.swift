//
//  ScriptureDetailRoute.swift
//  AMENAPP
//
//  Scripture detail view powered by Selah infrastructure.
//  Opens when tapping a scripture pill from composer or post card.
//  Displays verse text, surrounding context, chapter, and actions.
//

import SwiftUI

struct ScriptureDetailRoute: View {
    let context: SelahLaunchContext
    let onDismiss: () -> Void
    
    @State private var verseText: String = ""
    @State private var nearbyVerses: [(reference: String, text: String)] = []
    @State private var chapterVerses: [BibleVerse] = []
    @State private var showFullChapter = false
    @State private var selectedTranslation: BibleTranslation
    @State private var isLoading = true
    @State private var error: String?
    @State private var appear = false
    
    init(context: SelahLaunchContext, onDismiss: @escaping () -> Void) {
        self.context = context
        self.onDismiss = onDismiss
        self._selectedTranslation = State(initialValue: BibleTranslation(rawValue: context.translationPreference) ?? .NIV)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Verse header
                    verseHeaderSection
                    
                    // Main verse text
                    mainVerseSection
                    
                    // Context verses
                    if !nearbyVerses.isEmpty {
                        contextSection
                    }
                    
                    // Translation picker
                    translationSection
                    
                    // Actions
                    actionsSection
                    
                    // Full chapter toggle
                    fullChapterSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
                }
                
                ToolbarItem(placement: .principal) {
                    Text(context.attachment.displayReference)
                        .font(.systemScaled(15, weight: .semibold))
                }
            }
            .opacity(appear ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { appear = true }
                loadContent()
            }
        }
    }
    
    // MARK: - Sections
    
    private var verseHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reference
            Text(context.attachment.displayReference)
                .font(.systemScaled(28, weight: .bold))
                .foregroundStyle(Color.primary)
            
            // Translation badge
            HStack(spacing: 8) {
                Text(selectedTranslation.rawValue)
                    .font(.systemScaled(12, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                
                if context.attachment.isRange {
                    Text("Verses \(context.attachment.verseStart)–\(context.attachment.verseEnd ?? context.attachment.verseStart)")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(.top, 8)
    }
    
    private var mainVerseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                // Skeleton
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 18)
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 200, height: 18)
                }
                .padding(.vertical, 8)
            } else if let error = error {
                // Error state
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.systemScaled(24))
                        .foregroundStyle(Color.secondary)
                    Text(error)
                        .font(.systemScaled(14))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { loadContent() }
                        .font(.systemScaled(14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Verse text
                Text(verseText.isEmpty ? context.attachment.previewText : verseText)
                    .font(.system(size: 20, design: .serif))
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
            }
        }
    }
    
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Surrounding Context")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(nearbyVerses, id: \.reference) { verse in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verse.reference)
                            .font(.systemScaled(12, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.6))
                        
                        Text(verse.text)
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineSpacing(4)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }
    
    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Translation")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BibleTranslation.allCases, id: \.self) { translation in
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                                selectedTranslation = translation
                            }
                            loadContent()
                        } label: {
                            Text(translation.rawValue)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(selectedTranslation == translation ? Color.white : Color.primary.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background {
                                    if selectedTranslation == translation {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.85))
                                    } else {
                                        Capsule()
                                            .fill(Color.primary.opacity(0.05))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 10) {
            // Copy
            actionRow(icon: "doc.on.doc", title: "Copy Verse") {
                let text = "\(context.attachment.displayReference) (\(selectedTranslation.rawValue))\n\(verseText.isEmpty ? context.attachment.previewText : verseText)"
                UIPasteboard.general.string = text
            }
            
            // Share
            actionRow(icon: "square.and.arrow.up", title: "Share") {
                let text = "\"\(verseText.isEmpty ? context.attachment.previewText : verseText)\"\n— \(context.attachment.displayReference) (\(selectedTranslation.rawValue))"
                let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(av, animated: true)
                }
            }
        }
    }
    
    private var fullChapterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                    showFullChapter.toggle()
                }
                if showFullChapter && chapterVerses.isEmpty {
                    loadChapter()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: showFullChapter ? "chevron.down" : "chevron.right")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                    
                    Text("\(context.attachment.book) \(context.attachment.chapter)")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    Text("Full Chapter")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View full chapter, \(context.attachment.book) \(context.attachment.chapter)")
            
            if showFullChapter {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(chapterVerses, id: \.reference) { verse in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verse.reference.displayString)
                                .font(.systemScaled(11, weight: .bold))
                                .foregroundStyle(Color.primary.opacity(0.5))

                            Text(verse.text)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(
                                    verse.reference.displayString == context.attachment.canonicalReference
                                    ? Color.primary
                                    : Color.primary.opacity(0.65)
                                )
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(
                            verse.reference.displayString == context.attachment.canonicalReference
                            ? RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.04))
                                .padding(.horizontal, -8)
                            : nil
                        )
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 20)
                
                Text(title)
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.8))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Data Loading
    
    private func loadContent() {
        isLoading = true
        error = nil
        
        // Use prefetched data if available
        if let payload = context.prefetchedPayload, !payload.isStale {
            verseText = payload.attachment.previewText
            nearbyVerses = payload.nearbyVerses.map { ($0.reference.displayString, $0.text) }
            isLoading = false
            return
        }
        
        // Fetch fresh data
        Task {
            do {
                let version = selectedTranslation.apiVersion
                let passage = try await YouVersionBibleService.shared.fetchVerse(
                    reference: context.attachment.canonicalReference,
                    version: version
                )
                
                verseText = passage.text
                
                // Fetch nearby context
                let attachment = context.attachment
                let before = max(1, attachment.verseStart - 2)
                let after = attachment.verseStart + 2
                
                var nearby: [(String, String)] = []
                
                if before < attachment.verseStart {
                    for v in before..<attachment.verseStart {
                        let ref = "\(attachment.book) \(attachment.chapter):\(v)"
                        if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: ref, version: version) {
                            nearby.append((passage.reference, passage.text))
                        }
                    }
                }
                
                let endVerse = attachment.verseEnd ?? attachment.verseStart
                for v in (endVerse + 1)...after {
                    let ref = "\(attachment.book) \(attachment.chapter):\(v)"
                    if let passage = try? await YouVersionBibleService.shared.fetchVerse(reference: ref, version: version) {
                        nearby.append((passage.reference, passage.text))
                    }
                }
                
                nearbyVerses = nearby
                isLoading = false
                
            } catch {
                // Use cached preview text if available
                if !context.attachment.previewText.isEmpty {
                    verseText = context.attachment.previewText
                    isLoading = false
                } else {
                    self.error = "Unable to load verse. Check your connection."
                    isLoading = false
                }
            }
        }
    }
    
    private func loadChapter() {
        Task {
            let version = selectedTranslation.apiVersion
            var verses: [BibleVerse] = []
            
            // Try to load verses 1-30 (reasonable chapter length)
            for v in 1...30 {
                let ref = "\(context.attachment.book) \(context.attachment.chapter):\(v)"
                do {
                    let passage = try await YouVersionBibleService.shared.fetchVerse(reference: ref, version: version)
                    verses.append(BibleVerse(reference: passage.reference, text: passage.text, translation: selectedTranslation.rawValue))
                } catch {
                    // We've likely passed the end of the chapter
                    break
                }
            }
            
            chapterVerses = verses
        }
    }
}
