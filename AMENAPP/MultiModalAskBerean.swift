//
//  MultiModalAskBerean.swift
//  AMENAPP
//
//  Universal "Ask Berean" Entry Point — ambient, not a separate screen.
//
//  Modes of input:
//    • Text       → direct question or topic
//    • Voice      → WhisperVoiceService transcription → Claude
//    • Image      → ScriptureVisionService (camera capture)
//    • Highlight  → selected text passed in from any view
//    • Verse      → specific scripture reference for deep study
//    • Sermon     → routes to SermonIntelligenceEngine
//
//  Intent routing (automatic):
//    • Verse detected   → ContextExpansionEngine + optional MultiPerspective
//    • Crisis signals   → CrisisDetectionService
//    • Decision query   → BereanDecisionEngine
//    • Teaching prep    → IntentAwareStudyMode (teaching intent)
//    • General          → BereanChatView
//
//  UI:
//    • AskBereanButton  — floating action button, embeds anywhere
//    • AskBereanSheet   — the main input sheet
//    • AskBereanBanner  — compact inline trigger (e.g. inside PostCard)
//
//  Long-press any text in the app → "Ask Berean" via contextual menu.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Input Mode

enum AskBereanInputMode: String, CaseIterable {
    case text      = "Text"
    case voice     = "Voice"
    case camera    = "Camera"
    case highlight = "Highlight"
    case verse     = "Verse"
    case sermon    = "Sermon"

    var icon: String {
        switch self {
        case .text:      return "text.bubble.fill"
        case .voice:     return "waveform.and.mic"
        case .camera:    return "camera.viewfinder"
        case .highlight: return "text.badge.magnifyingglass"
        case .verse:     return "book.fill"
        case .sermon:    return "music.note.list"
        }
    }
}

// Destination after routing
enum BereanRoute: Equatable {
    case chat(prefill: String)
    case contextExpansion(verse: String)
    case multiPerspective(verse: String)
    case decision(query: String)
    case studyMode(query: String)
    case visionScanner
    case sermonIntelligence
    case crisis
}

// MARK: - Router

@MainActor
final class AskBereanRouter: ObservableObject {
    static let shared = AskBereanRouter()

    @Published var pendingRoute: BereanRoute?
    @Published var isSheetPresented: Bool = false
    @Published var prefillText: String = ""
    @Published var selectedMode: AskBereanInputMode = .text

    private init() {}

    /// Opens the Ask Berean sheet with optional pre-filled text.
    func open(with text: String = "", mode: AskBereanInputMode = .text) {
        prefillText = text
        selectedMode = mode
        isSheetPresented = true
    }

    /// Highlight integration — pass selected text from any view.
    func openWithHighlight(_ text: String) {
        open(with: text, mode: .highlight)
    }

    /// Verse reference — routes directly to context expansion.
    func openWithVerse(_ ref: String) {
        pendingRoute = .contextExpansion(verse: ref)
        isSheetPresented = true
    }

    /// Routes a query to the appropriate engine based on intent.
    func route(query: String) -> BereanRoute {
        let q = query.lowercased()

        // Crisis check
        let crisisWords = ["suicide", "kill myself", "end it", "self harm", "can't go on", "no point"]
        if crisisWords.contains(where: { q.contains($0) }) { return .crisis }

        // Verse pattern detection
        let versePattern = #"([1-3]?\s?[A-Za-z]+)\s+\d+:\d+"#
        if let _ = try? NSRegularExpression(pattern: versePattern).firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) {
            return .contextExpansion(verse: query)
        }

        // Decision
        let decisionWords = ["should i", "is it ok", "is it a sin", "can i", "biblical view on"]
        if decisionWords.contains(where: { q.contains($0) }) { return .decision(query: query) }

        // Teaching
        if q.contains("preach") || q.contains("sermon") || q.contains("teach") {
            return .studyMode(query: query)
        }

        return .chat(prefill: query)
    }
}

// MARK: - Main Sheet View

struct AskBereanSheet: View {
    @StateObject private var router = AskBereanRouter.shared
    @StateObject private var voiceVM = WhisperVoiceViewModel()
    @State private var query: String = ""
    @State private var response: String = ""
    @State private var isLoading: Bool = false
    @State private var activeRoute: BereanRoute?
    @State private var showingVision = false
    @State private var showingSermon = false
    @Environment(\.dismiss) private var dismiss

    var prefill: String
    var mode: AskBereanInputMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode selector
                modeSelectorBar

                Divider()

                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Input area
                        inputArea

                        // Tone selector (compact)
                        ToneSelectorView(compact: true)
                            .padding(.horizontal)

                        // Route navigation
                        if let route = activeRoute {
                            routeView(for: route)
                        }

                        // Streaming response
                        if !response.isEmpty {
                            responseCard
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.vertical)
                }

                // Submit bar
                submitBar
            }
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingVision) {
                ScriptureVisionSheet()
            }
            .sheet(isPresented: $showingSermon) {
                SermonIntelligenceSheet()
            }
        }
        .onAppear {
            query = prefill
        }
    }

    // MARK: - Mode Selector

    private var modeSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AskBereanInputMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            router.selectedMode = m
                        }
                        handleModeSwitch(m)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: m.icon)
                                .font(.caption)
                            Text(m.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(router.selectedMode == m ? Color.indigo : Color(.systemGray5),
                                    in: Capsule())
                        .foregroundStyle(router.selectedMode == m ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Input Area

    @ViewBuilder
    private var inputArea: some View {
        switch router.selectedMode {
        case .text, .highlight, .verse:
            VStack(alignment: .leading, spacing: 6) {
                if router.selectedMode == .highlight {
                    Label("Selected Text", systemImage: "text.badge.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else if router.selectedMode == .verse {
                    Label("Bible Verse or Reference", systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                TextField(placeholderFor(router.selectedMode), text: $query, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

        case .voice:
            voiceInputView

        case .camera:
            Button {
                showingVision = true
            } label: {
                Label("Open Camera Scanner", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

        case .sermon:
            Button {
                showingSermon = true
            } label: {
                Label("Open Sermon Intelligence", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Voice Input

    private var voiceInputView: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(voiceVM.isRecording ? Color.red.opacity(0.15) : Color.indigo.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: voiceVM.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.systemScaled(32))
                        .foregroundStyle(voiceVM.isRecording ? .red : .indigo)
                }
                .onTapGesture {
                    Task {
                        if voiceVM.isRecording {
                            await voiceVM.stopAndTranscribe()
                            if !voiceVM.transcript.isEmpty {
                                query = voiceVM.transcript
                            }
                        } else {
                            await voiceVM.startRecording()
                        }
                    }
                }
                .scaleEffect(voiceVM.isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceVM.isRecording)

            Text(voiceVM.isRecording ? "Tap to stop" : "Tap to speak")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !query.isEmpty {
                Text(query)
                    .font(.subheadline)
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Submit Bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    Task { await submitQuery() }
                } label: {
                    Label(isLoading ? "Thinking…" : "Ask", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

                if !query.isEmpty {
                    Button {
                        let route = router.route(query: query)
                        activeRoute = route
                    } label: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .buttonStyle(.bordered)
                    .help("Route to specialist")
                }
            }
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Route View

    @ViewBuilder
    private func routeView(for route: BereanRoute) -> some View {
        switch route {
        case .contextExpansion(let verse):
            VStack(alignment: .leading, spacing: 8) {
                Label("Context Expansion", systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ContextExpansionView(verse: verse)
                    .padding(.horizontal)
            }

        case .multiPerspective(let verse):
            MultiPerspectivePill(verse: verse)
                .padding(.horizontal)

        case .studyMode:
            IntentBadgeView(intent: StudyToneManager.shared.detectedIntent)
                .padding(.horizontal)

        case .crisis:
            BereanCrisisCard()
                .padding(.horizontal)

        default:
            EmptyView()
        }
    }

    // MARK: - Response Card

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Berean", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Image(systemName: StudyToneManager.shared.selectedTone.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(StudyToneManager.shared.selectedTone.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Text(response)
                .font(.body)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            // Verse follow-up pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ContextExpansionPill(verse: extractFirstVerse(from: response) ?? "")
                        .opacity(extractFirstVerse(from: response) != nil ? 1 : 0)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Helpers

    private func handleModeSwitch(_ mode: AskBereanInputMode) {
        if mode == .camera  { showingVision = true }
        if mode == .sermon  { showingSermon = true }
    }

    private func placeholderFor(_ mode: AskBereanInputMode) -> String {
        switch mode {
        case .text:      return "Ask anything — verse, topic, decision, question…"
        case .highlight: return "Paste or type the highlighted text…"
        case .verse:     return "e.g. John 3:16 or Romans 8"
        default:         return "Ask Berean…"
        }
    }

    private func submitQuery() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        activeRoute = nil
        isLoading = true
        response = ""

        // Check route first
        let route = router.route(query: query)
        switch route {
        case .crisis:
            activeRoute = .crisis
            isLoading = false
            return
        case .contextExpansion(let v):
            activeRoute = .contextExpansion(verse: v)
        case .decision:
            // Still stream a response but with decision framing
            break
        default:
            break
        }

        let userContext = await BereanUserContextProvider.shared.getContextBlock()
        let modeAddition = StudyToneManager.shared.systemPromptAddition(for: query)
        _ = "You are Berean, a faith-aligned AI companion. \(modeAddition)"

        response = (try? await ClaudeService.shared.sendMessageSync("\(userContext)\n\nUser: \(query)", mode: .shepherd)) ?? ""
        isLoading = false
    }

    private func extractFirstVerse(from text: String) -> String? {
        let pattern = #"([1-3]?\s?[A-Za-z]+)\s+\d+:\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Berean Crisis Card (inline, contextual)

struct BereanCrisisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("You're not alone", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("If you're in crisis, please reach out to someone who can help right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                CrisisLink(label: "988 Suicide & Crisis Lifeline", detail: "Call or text 988", icon: "phone.fill")
                CrisisLink(label: "Crisis Text Line", detail: "Text HOME to 741741", icon: "message.fill")
                CrisisLink(label: "Find a Christian Counselor", detail: "aacc.net/find-a-counselor", icon: "person.fill.checkmark")
            }

            Text("Berean cares about you, but cannot replace professional help.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding()
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct CrisisLink: View {
    let label: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Floating Ask Berean Button

struct AskBereanFloatingButton: View {
    var prefill: String = ""
    var mode: AskBereanInputMode = .text
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Ask Berean")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.indigo.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .sheet(isPresented: $showingSheet) {
            AskBereanSheet(prefill: prefill, mode: mode)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Inline Banner (for PostCard, etc.)

struct AskBereanBanner: View {
    let context: String         // The post text or topic to pre-fill
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                Text("Ask Berean about this")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.indigo)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
        .sheet(isPresented: $showingSheet) {
            AskBereanSheet(prefill: context, mode: .highlight)
                .presentationDetents([.medium, .large])
        }
    }
}
