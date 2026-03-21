//
//  StudioWriteView.swift
//  AMENAPP
//
//  Clean minimal document editor with AI-assisted writing for AMEN Studio.
//  Replaces the old StudioAICreationView UI when mode == .write.
//  Preserves all existing save, share, post, and export logic.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseDatabase
import FirebaseFunctions

// MARK: - Writing Type

enum StudioWritingType: String, CaseIterable, Identifiable {
    case testimony, prayer, devotional, sermon, letter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testimony:  return "Testimony"
        case .prayer:     return "Prayer"
        case .devotional: return "Devotional"
        case .sermon:     return "Sermon"
        case .letter:     return "Letter"
        }
    }

    var placeholder: String {
        switch self {
        case .testimony:  return "Share what God has done in your life\u{2026}"
        case .prayer:     return "Pour out your heart before the Lord\u{2026}"
        case .devotional: return "Begin with a scripture or theme for reflection\u{2026}"
        case .sermon:     return "Start with your main text and message\u{2026}"
        case .letter:     return "Write your letter to a friend, mentor, or the Lord\u{2026}"
        }
    }

    /// Maps to StudioTool for Berean AI backend calls
    var studioTool: StudioTool {
        switch self {
        case .testimony:  return .testimony
        case .prayer:     return .prayer
        case .devotional: return .devotional
        case .sermon:     return .sermonPrep
        case .letter:     return .testimony // closest match
        }
    }
}

// MARK: - AI Mode

enum StudioAIMode: String, CaseIterable, Identifiable {
    case auto, quickPolish, addScripture, deepExpand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:         return "Auto"
        case .quickPolish:  return "Quick polish"
        case .addScripture: return "Add Scripture"
        case .deepExpand:   return "Deep expand"
        }
    }

    var description: String {
        switch self {
        case .auto:         return "Smartly adapts to your request"
        case .quickPolish:  return "Fast grammar and clarity fix"
        case .addScripture: return "Finds matching Bible verses for your writing"
        case .deepExpand:   return "Expand and enrich your content"
        }
    }

    var icon: String {
        switch self {
        case .auto:         return "sparkle"
        case .quickPolish:  return "bolt.fill"
        case .addScripture: return "cross.fill"
        case .deepExpand:   return "scope"
        }
    }

    /// System prompt suffix for Berean AI calls
    var systemPromptSuffix: String {
        switch self {
        case .auto:
            return "Intelligently improve the text \u{2014} fix grammar, enhance clarity, and strengthen the message."
        case .quickPolish:
            return "Only fix grammar, spelling, and clarity. Keep the original voice and length."
        case .addScripture:
            return "Find 1-2 Bible verses that deeply connect with the themes in this writing. Include the full verse text and reference."
        case .deepExpand:
            return "Expand and enrich this content \u{2014} add depth, vivid details, and stronger spiritual insight while preserving the author's voice."
        }
    }
}

// MARK: - Text Formatting

enum StudioTextAlignment: String {
    case left, center, right

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left:   return .left
        case .center: return .center
        case .right:  return .right
        }
    }
}

// MARK: - Color Cycle

private let textColorCycle: [UIColor] = [
    .label, .systemRed, UIColor(red: 0.48, green: 0.37, blue: 0.65, alpha: 1), .systemBlue, UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)
]

// MARK: - StudioWriteView

struct StudioWriteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - Document state
    @State private var documentTitle: String = "Untitled"
    @State private var documentText: String = ""
    @State private var writingType: StudioWritingType = .testimony
    @State private var selectedAIMode: StudioAIMode = .auto

    // MARK: - Formatting state
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var textAlignment: StudioTextAlignment = .left
    @State private var textColorIndex = 0

    // MARK: - AI state
    @State private var showAIModePicker = false
    @State private var aiSuggestionText: String = ""
    @State private var showAISuggestion = false
    @State private var isAIGenerating = false
    @State private var aiSuggestionScale: CGFloat = 0.92

    // MARK: - Auto-suggest debounce
    @State private var autoSuggestTask: Task<Void, Never>?
    @State private var lastAutoSuggestLength = 0

    // MARK: - Auto-save
    @State private var autoSaveTimer: Timer?
    @State private var showSavedFlash = false
    private let sessionID = UUID().uuidString

    // MARK: - Share
    @State private var showShareSheet = false

    // MARK: - Undo/Redo
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var isUndoRedoAction = false

    private let functions = Functions.functions(region: "us-central1")
    private let bereanPurple = Color(red: 0.48, green: 0.37, blue: 0.65) // #7B5EA7

    // MARK: - Computed

    private var wordCount: Int {
        documentText.split(separator: " ", omittingEmptySubsequences: true).count
    }

    private var readingTime: Int {
        max(1, wordCount / 200)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Page background
                Color(red: 0.96, green: 0.96, blue: 0.97) // #F5F5F7
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    editorCard
                    bottomBar
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) {
                if showAIModePicker {
                    aiModePickerOverlay
                }
            }
            .onAppear { startAutoSaveTimer() }
            .onDisappear {
                autoSaveTimer?.invalidate()
                autoSuggestTask?.cancel()
                saveDraft()
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [documentText])
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.impact(style: .light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TextField("Document Title", text: $documentTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)

            Spacer()

            // Saved flash
            if showSavedFlash {
                Text("Saved")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Button {
                HapticManager.impact(style: .light)
                saveDraft()
                withAnimation(.easeInOut(duration: 0.2)) { showSavedFlash = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { showSavedFlash = false }
                }
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.impact(style: .light)
                showShareSheet = true
            } label: {
                Text("Share")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }

    // MARK: - Editor Card

    private var editorCard: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Floating formatting toolbar
                formattingToolbar
                    .padding(.horizontal, 12)
                    .padding(.top, 14)

                // Writing type chips
                writingTypeChips
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // Text editor
                editorContent
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // AI Suggestion card
                if showAISuggestion {
                    aiSuggestionCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .scaleEffect(aiSuggestionScale)
                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: aiSuggestionScale)
                }

                Color.clear.frame(height: 80) // bottom padding for keyboard
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 0) {
            // Ask AI button
            Button {
                HapticManager.impact(style: .light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    showAIModePicker.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Ask AI")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(bereanPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            toolbarDivider

            // Bold
            formatButton(label: "B", isActive: isBold, weight: .bold) {
                isBold.toggle()
            }
            // Italic
            formatButton(label: "I", isActive: isItalic, weight: .regular, italic: true) {
                isItalic.toggle()
            }
            // Underline
            formatButton(label: "U", isActive: isUnderline, weight: .regular, underline: true) {
                isUnderline.toggle()
            }
            // Bullet
            Button {
                HapticManager.impact(style: .light)
                insertBullet()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.clear))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            // Link placeholder
            Button {
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            // Color dot
            Button {
                HapticManager.impact(style: .light)
                textColorIndex = (textColorIndex + 1) % textColorCycle.count
            } label: {
                Circle()
                    .fill(Color(textColorCycle[textColorIndex]))
                    .frame(width: 14, height: 14)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            toolbarDivider

            // Alignment
            alignButton(icon: "text.alignleft", alignment: .left)
            alignButton(icon: "text.aligncenter", alignment: .center)
            alignButton(icon: "text.alignright", alignment: .right)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.1))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func formatButton(label: String, isActive: Bool, weight: Font.Weight = .regular, italic: Bool = false, underline: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: weight))
                .italic(italic)
                .underline(underline)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.black.opacity(0.08) : Color.clear)
                )
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func alignButton(icon: String, alignment: StudioTextAlignment) -> some View {
        Button {
            HapticManager.impact(style: .light)
            textAlignment = alignment
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(textAlignment == alignment ? Color.black.opacity(0.08) : Color.clear)
                )
                .foregroundStyle(textAlignment == alignment ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Writing Type Chips

    private var writingTypeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudioWritingType.allCases) { type in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            writingType = type
                        }
                        HapticManager.impact(style: .light)
                    } label: {
                        Text(type.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(writingType == type ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(writingType == type ? Color.black : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        writingType == type ? Color.clear : Color.black.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            if documentText.isEmpty {
                Text(writingType.placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.placeholderText))
                    .lineSpacing(1.75 * 15)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $documentText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(1.75)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .multilineTextAlignment(
                    textAlignment == .center ? .center :
                    textAlignment == .right ? .trailing : .leading
                )
                .onChange(of: documentText) { oldValue, newValue in
                    guard !isUndoRedoAction else {
                        isUndoRedoAction = false
                        return
                    }
                    // Undo stack
                    undoStack.append(oldValue)
                    redoStack.removeAll()

                    // Auto-suggest after ~120 characters
                    checkAutoSuggest(newValue)
                }
        }
    }

    // MARK: - AI Mode Picker Overlay

    private var aiModePickerOverlay: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 120) // position below toolbar

            VStack(alignment: .leading, spacing: 0) {
                ForEach(StudioAIMode.allCases) { mode in
                    Button {
                        selectedAIMode = mode
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showAIModePicker = false
                        }
                        HapticManager.impact(style: .medium)
                        triggerAISuggestion(mode: mode)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(bereanPurple)
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedAIMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(bereanPurple)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if mode != StudioAIMode.allCases.last {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            )
            .padding(.horizontal, 24)
            .scaleEffect(showAIModePicker ? 1.0 : 0.92, anchor: .top)
            .opacity(showAIModePicker ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: showAIModePicker)

            Spacer()
        }
        .background(Color.black.opacity(0.001))
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showAIModePicker = false
            }
        }
    }

    // MARK: - AI Suggestion Card

    private var aiSuggestionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(bereanPurple)
                Text("BEREAN AI SUGGESTION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(bereanPurple)
                    .tracking(0.5)

                Spacer()

                if isAIGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(bereanPurple)
                }
            }

            if isAIGenerating {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(bereanPurple.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.vertical, 8)
            } else {
                Text(aiSuggestionText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action buttons
            if !isAIGenerating {
                aiSuggestionButtons
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bereanPurple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(bereanPurple.opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private var aiSuggestionButtons: some View {
        HStack(spacing: 10) {
            // Insert
            Button {
                HapticManager.impact(style: .medium)
                insertAISuggestion()
            } label: {
                Text("Insert")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)

            // Try again
            Button {
                HapticManager.impact(style: .light)
                triggerAISuggestion(mode: selectedAIMode)
            } label: {
                Text("Try again")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Dismiss
            Button {
                HapticManager.impact(style: .light)
                dismissAISuggestion()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Word count + reading time
            Text("\(wordCount) words \u{00B7} ~\(readingTime) min read")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            // Quick AI action chips
            bottomBarChip(icon: "sparkle", label: "Polish") {
                selectedAIMode = .quickPolish
                triggerAISuggestion(mode: .quickPolish)
            }

            bottomBarChip(icon: "cross.fill", label: "Add verse") {
                selectedAIMode = .addScripture
                triggerAISuggestion(mode: .addScripture)
            }

            Button {
                HapticManager.impact(style: .light)
                triggerClosingPrayer()
            } label: {
                HStack(spacing: 4) {
                    Text("\u{1F64F}")
                        .font(.system(size: 10))
                    Text("Close with prayer")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(bereanPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(bereanPurple.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }

    private func bottomBarChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.impact(style: .light)
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(bereanPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(bereanPurple.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Integration (Berean)

    private func triggerAISuggestion(mode: StudioAIMode) {
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAIGenerating = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            showAISuggestion = true
            aiSuggestionScale = 0.92
        }
        // Animate in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72).delay(0.05)) {
            aiSuggestionScale = 1.0
        }

        let tool = writingType.studioTool
        let systemInstruction = """
        You are Berean, a faith-grounded AI writing assistant for AMEN.
        Writing type: \(writingType.displayName).
        AI mode: \(mode.title).
        \(mode.systemPromptSuffix)
        Keep your response concise (2-4 sentences max). Be warm but not preachy.
        """

        Task {
            do {
                let payload: [String: Any] = [
                    "tool": tool.rawValue,
                    "user_input": trimmed,
                    "scripture_ref": "",
                    "tone": "reflective",
                    "system_override": systemInstruction
                ]
                let result = try await functions
                    .httpsCallable("studioGenerateContent")
                    .safeCall(payload)
                if let data = result.data as? [String: Any],
                   let text = data["generated_text"] as? String {
                    await MainActor.run {
                        aiSuggestionText = text
                        isAIGenerating = false
                    }
                } else {
                    await MainActor.run {
                        aiSuggestionText = "Couldn't generate a suggestion. Please try again."
                        isAIGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    aiSuggestionText = "AI is unavailable right now. Please try again later."
                    isAIGenerating = false
                }
                dlog("\u{26A0}\u{FE0F} [StudioWrite] AI suggestion error: \(error)")
            }
        }
    }

    private func triggerClosingPrayer() {
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAIGenerating = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            showAISuggestion = true
            aiSuggestionScale = 1.0
        }

        let systemInstruction = """
        You are Berean, a faith-grounded AI writing assistant.
        Generate a closing prayer that matches the tone and themes of the following writing.
        Writing type: \(writingType.displayName).
        The prayer should be 2-4 sentences, heartfelt, and appropriate for the content's tone.
        """

        Task {
            do {
                let payload: [String: Any] = [
                    "tool": writingType.studioTool.rawValue,
                    "user_input": trimmed,
                    "scripture_ref": "",
                    "tone": "gentle",
                    "system_override": systemInstruction
                ]
                let result = try await functions
                    .httpsCallable("studioGenerateContent")
                    .safeCall(payload)
                if let data = result.data as? [String: Any],
                   let text = data["generated_text"] as? String {
                    await MainActor.run {
                        aiSuggestionText = text
                        isAIGenerating = false
                    }
                } else {
                    await MainActor.run {
                        aiSuggestionText = "Couldn't generate a prayer. Please try again."
                        isAIGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    aiSuggestionText = "AI is unavailable right now."
                    isAIGenerating = false
                }
            }
        }
    }

    private func insertAISuggestion() {
        guard !aiSuggestionText.isEmpty else { return }
        if documentText.isEmpty || documentText.hasSuffix("\n") {
            documentText += aiSuggestionText
        } else {
            documentText += "\n\n" + aiSuggestionText
        }
        dismissAISuggestion()
    }

    private func dismissAISuggestion() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            aiSuggestionScale = 0.92
        }
        withAnimation(.easeOut(duration: 0.15).delay(0.1)) {
            showAISuggestion = false
            aiSuggestionText = ""
        }
    }

    // MARK: - Auto-Suggest (passive, ~120 chars)

    private func checkAutoSuggest(_ text: String) {
        let currentLength = text.count
        // Only trigger when we've crossed a 120-char boundary
        guard currentLength >= lastAutoSuggestLength + 120 else { return }
        lastAutoSuggestLength = currentLength

        autoSuggestTask?.cancel()
        autoSuggestTask = Task { @MainActor in
            // Debounce 2 seconds
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard !showAISuggestion else { return } // don't interrupt active suggestion
            triggerAISuggestion(mode: .auto)
        }
    }

    // MARK: - Helpers

    private func insertBullet() {
        if documentText.isEmpty || documentText.hasSuffix("\n") {
            documentText += "\u{2022} "
        } else {
            documentText += "\n\u{2022} "
        }
    }

    // MARK: - Auto-Save & Draft Persistence

    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                saveDraft()
                withAnimation(.easeInOut(duration: 0.2)) { showSavedFlash = true }
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled {
                    withAnimation { showSavedFlash = false }
                }
            }
        }
    }

    private func saveDraft() {
        guard !documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Sync to RTDB
        syncToRTDB()

        // Save to SwiftData
        let draft = StudioDraft(
            tool: writingType.studioTool.rawValue,
            userInput: documentText,
            scriptureRef: "",
            tone: "reflective",
            generatedText: ""
        )
        modelContext.insert(draft)

        // Prune to last 5 drafts
        let toolValue = writingType.studioTool.rawValue
        let descriptor = FetchDescriptor<StudioDraft>(
            predicate: #Predicate { $0.tool == toolValue },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        if let allDrafts = try? modelContext.fetch(descriptor), allDrafts.count > 5 {
            allDrafts.dropFirst(5).forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
    }

    private func syncToRTDB() {
        guard let uid = Auth.auth().currentUser?.uid,
              !documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let ref = Database.database().reference()
            .child("studioSessions").child(uid).child(sessionID)
        ref.setValue([
            "tool": writingType.studioTool.rawValue,
            "userInput": documentText,
            "title": documentTitle,
            "scriptureRef": "",
            "tone": "reflective",
            "generatedText": "",
            "updatedAt": ServerValue.timestamp(),
        ])
    }
}
