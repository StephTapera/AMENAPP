// AmenAssistantBarCoordinator.swift
// Spiritual OS — Agent G: Berean Assistant Bar
//
// Owns all state for the global assistant bar overlay.
// Injected at ContentView level; tab bar remains fully accessible beneath it.
//
// Feature gate: AppStorage key "spiritualOS_assistant_bar_enabled" (default OFF).
// All @Published mutations happen on @MainActor.

import SwiftUI
import Firebase
import FirebaseFunctions
import Foundation

// MARK: - AssistantResponse

/// Structured response returned by the `getAssistantResponse` callable.
struct AssistantResponse: Equatable {
    /// The main answer text to display to the user.
    let answer: String
    /// Scripture or community sources supporting the answer.
    let sources: [AssistantSource]
    /// Suggested follow-up prompts shown beneath the response card.
    let suggestedFollowUps: [String]
    /// Short AI disclosure label, e.g. "Berean AI · powered by Anthropic".
    let aiDisclosureLabel: String
}

// MARK: - AssistantSource

/// A single sourced reference within an AssistantResponse.
struct AssistantSource: Equatable {
    /// Category of source: "scripture", "commentary", "community", etc.
    let type: String
    /// Machine-readable reference, e.g. "Romans 8:28".
    let ref: String
    /// Human-readable title.
    let title: String
    /// Optional short excerpt surfaced as a chip tooltip.
    let snippet: String?
}

// MARK: - AmenAssistantBarCoordinator

@MainActor
final class AmenAssistantBarCoordinator: ObservableObject {

    // MARK: Published state

    @Published var isExpanded: Bool = false
    @Published var currentSurface: SOSurface = .assistantBar
    /// Set when a deep link arrives carrying a pre-populated query string.
    @Published var pendingQuery: String? = nil
    /// True when the Context Engine reports the user is in drive/hands-free mode.
    @Published var isVoiceMode: Bool = false
    @Published var showingCamera: Bool = false
    @Published var showingVoice: Bool = false
    @Published var lastResponse: AssistantResponse? = nil
    /// Surfaced to the UI so a spinner or error badge can be shown.
    @Published var isLoading: Bool = false
    @Published var lastError: String? = nil

    // MARK: Identity

    let userId: String

    // MARK: Private

    private let functions = Functions.functions()

    // MARK: Init

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Actions

    /// Submits a free-text or quick-prompt query to the `getAssistantResponse` callable.
    func submit(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        lastError = nil

        let payload: [String: Any] = [
            "userId": userId,
            "query": trimmed,
            "queryType": "text",
            "surfaceContext": currentSurface.rawValue
        ]

        do {
            let callable = functions.httpsCallable("getAssistantResponse")
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any] else {
                lastError = "Unexpected response format."
                isLoading = false
                return
            }

            let answer = data["answer"] as? String ?? ""
            let disclosureLabel = data["aiDisclosureLabel"] as? String ?? "Berean AI"
            let followUps = data["suggestedFollowUps"] as? [String] ?? []

            var sources: [AssistantSource] = []
            if let rawSources = data["sources"] as? [[String: Any]] {
                sources = rawSources.compactMap { raw in
                    guard
                        let type = raw["type"] as? String,
                        let ref  = raw["ref"]  as? String,
                        let title = raw["title"] as? String
                    else { return nil }
                    return AssistantSource(
                        type: type,
                        ref: ref,
                        title: title,
                        snippet: raw["snippet"] as? String
                    )
                }
            }

            lastResponse = AssistantResponse(
                answer: answer,
                sources: sources,
                suggestedFollowUps: followUps,
                aiDisclosureLabel: disclosureLabel
            )
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    /// Opens the camera OCR sheet for verse / scripture detection.
    func openCamera() {
        showingCamera = true
    }

    /// Opens the voice input sheet (drive mode / hands-free).
    func openVoice() {
        showingVoice = true
    }

    /// Updates the active surface so quick prompts and context stay in sync.
    func setSurface(_ surface: SOSurface) {
        currentSurface = surface
    }

    /// Dismisses the last response card.
    func dismissResponse() {
        lastResponse = nil
    }

    // MARK: - Quick Prompts

    /// Returns 3 surface-appropriate quick prompt strings shown above the bar.
    func quickPromptsForSurface(_ surface: SOSurface) -> [String] {
        switch surface {
        case .dailyDigest:
            return [
                "What does today's verse mean?",
                "Show me a prayer for today",
                "What's on my schedule?"
            ]
        case .unifiedHub:
            return [
                "Summarize my messages",
                "Who needs prayer today?",
                "Help me respond"
            ]
        case .lifePlanner:
            return [
                "What should I prioritize today?",
                "Suggest a scripture for tonight",
                "Help me plan tomorrow"
            ]
        case .spaceDashboard:
            return [
                "What's happening in this space?",
                "Suggest a devotional for our group",
                "Help us pray together"
            ]
        case .commandCenter:
            return [
                "How am I growing in faith?",
                "Suggest my next step",
                "What should I focus on this week?"
            ]
        default:
            return [
                "Ask about scripture",
                "Help me pray",
                "Find a community"
            ]
        }
    }
}

// MARK: - AmenAssistantBarOverlay

/// Drop-in overlay injected at ContentView level.
/// Renders above all content; the tab bar beneath remains tappable.
struct AmenAssistantBarOverlay: View {

    @ObservedObject var coordinator: AmenAssistantBarCoordinator

    @AppStorage("spiritualOS_assistant_bar_enabled") private var isEnabled = false

    var body: some View {
        if !isEnabled {
            EmptyView()
        } else {
            overlayContent
        }
    }

    // MARK: - Overlay content

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Response card sits above the bar when a response is present.
            if let response = coordinator.lastResponse {
                responseCard(response)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if coordinator.isVoiceMode {
                // Drive / hands-free mode: only show the mic chip.
                voiceModeButton
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                // Normal mode: full assistant bar.
                VStack(spacing: 0) {
                    AssistantBar(
                        placeholder: "Ask Berean\u{2026}",
                        contextSurface: coordinator.currentSurface,
                        onSubmit: { query in
                            Task { await coordinator.submit(query: query) }
                        },
                        onCamera: { coordinator.openCamera() },
                        onVoice:  { coordinator.openVoice()  },
                        quickPrompts: coordinator.quickPromptsForSurface(coordinator.currentSurface)
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: coordinator.lastResponse != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: coordinator.isVoiceMode)
        .sheet(isPresented: $coordinator.showingCamera) {
            CameraPlaceholderView()
        }
        .sheet(isPresented: $coordinator.showingVoice) {
            VoicePlaceholderView()
        }
    }

    // MARK: - Voice-mode mic button

    private var voiceModeButton: some View {
        HStack {
            Spacer()
            GlassChip(
                label: "Mic",
                icon: "mic.fill",
                tint: .amenPurple,
                size: .regular,
                isActive: true,
                action: { coordinator.openVoice() }
            )
            .accessibilityLabel("Voice input — tap to speak")
            Spacer()
        }
    }

    // MARK: - Response card

    @ViewBuilder
    private func responseCard(_ response: AssistantResponse) -> some View {
        GlassCard(tint: .amenPurple.opacity(0.08), elevated: true) {
            VStack(alignment: .leading, spacing: 10) {

                // Answer body on matte amenCream background
                Text(response.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.amenBlack)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Source chips (max 3)
                if !response.sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(response.sources.prefix(3).enumerated()), id: \.offset) { _, source in
                                GlassChip(
                                    label: source.title,
                                    icon: source.type == "scripture" ? "book.closed" : "person.2",
                                    tint: .amenGold,
                                    size: .compact,
                                    isActive: true
                                )
                                .accessibilityLabel(source.ref)
                            }
                        }
                    }
                }

                // Follow-up prompts
                if !response.suggestedFollowUps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(response.suggestedFollowUps.prefix(3), id: \.self) { followUp in
                            Button {
                                Task { await coordinator.submit(query: followUp) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.amenPurple)
                                    Text(followUp)
                                        .font(.caption.italic())
                                        .foregroundStyle(Color.amenSlate)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.amenSlate.opacity(0.45))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.amenPurple.opacity(0.06))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.amenPurple.opacity(0.14), lineWidth: 0.5)
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Follow up: \(followUp)")
                        }
                    }
                }

                // Divider + disclosure + dismiss row
                Divider()
                    .overlay(Color.amenPurple.opacity(0.12))

                HStack(alignment: .center, spacing: 0) {
                    Text(response.aiDisclosureLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.amenSlate)

                    Spacer()

                    GlassChip(
                        label: "Dismiss",
                        icon: "xmark",
                        tint: .amenSlate,
                        size: .compact,
                        action: { coordinator.dismissResponse() }
                    )
                    .accessibilityLabel("Dismiss Berean response")
                }
            }
            .padding(14)
            .background(Color.amenCream)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Placeholder Views

/// Stub shown while the real AMEN Vision OCR camera feature is not yet wired.
struct CameraPlaceholderView: View {
    var body: some View {
        Text("Camera OCR coming soon")
            .padding()
    }
}

/// Stub shown while the real voice-input feature is not yet wired.
struct VoicePlaceholderView: View {
    var body: some View {
        Text("Voice input coming soon")
            .padding()
    }
}
