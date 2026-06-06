// AmenMessageIntentChipRow.swift
// AMEN Spaces — Agent 4: Spaces Intelligence
//
// Horizontal chip row showing detected message intents.
// Glass pills for each intent. Care-sensitive intents route via
// AmenConnectSpacesCallableProxy.shared.routeCareSignal(spaceId:messageId:intents:)
// Agent 5 seam: `onCareRoutingComplete` closure is surfaced for downstream care-routing UI.

import SwiftUI

// MARK: - Design Tokens (file-local, mirroring ConnectSpacesPhase0Contracts)

// MARK: - Intent Metadata

private struct IntentStyle {
    let emoji: String
    let label: String
    let tint: Color
}

private func style(for intent: AmenConnectSpacesMessageIntent) -> IntentStyle {
    switch intent {
    case .prayerRequest: return IntentStyle(emoji: "🙏", label: "Prayer",        tint: .accentColor)
    case .struggling:    return IntentStyle(emoji: "💛", label: "Struggling",    tint: .accentColor)
    case .leadSunday:    return IntentStyle(emoji: "📋", label: "Lead Sunday",   tint: .amenBlue)
    case .volunteerNeed: return IntentStyle(emoji: "🤝", label: "Volunteer",     tint: .amenPurple)
    case .testimony:     return IntentStyle(emoji: "✨", label: "Testimony",     tint: .accentColor)
    case .confession:    return IntentStyle(emoji: "💙", label: "Confession",    tint: .amenBlue)
    case .grief:         return IntentStyle(emoji: "💙", label: "Grief",         tint: .amenBlue)
    case .decision:      return IntentStyle(emoji: "⚡", label: "Decision",      tint: .amenBlue)
    case .task:          return IntentStyle(emoji: "⚡", label: "Task",          tint: .amenBlue)
    case .risk:          return IntentStyle(emoji: "⚠️", label: "Risk",          tint: .accentColor)
    case .question:      return IntentStyle(emoji: "❓", label: "Question",      tint: .amenPurple)
    case .careFollowUp:  return IntentStyle(emoji: "💚", label: "Care",          tint: .accentColor)
    }
}

private let careSensitiveIntents: Set<AmenConnectSpacesMessageIntent> = [
    .prayerRequest, .struggling, .grief, .confession
]

// MARK: - Single Intent Chip

private struct SpaceIntentChip: View {
    let intent: AmenConnectSpacesMessageIntent
    let onTap: () -> Void

    private var meta: IntentStyle { style(for: intent) }
    private var isCare: Bool { careSensitiveIntents.contains(intent) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(meta.emoji)
                    .font(.system(size: 11))
                Text(meta.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground)
            .foregroundStyle(meta.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(meta.label) intent\(isCare ? ", care sensitive" : "")")
        .accessibilityHint(isCare ? "Double-tap to route care signal" : "")
    }

    @ViewBuilder
    private var chipBackground: some View {
        // Glass pill — chrome surface per design rules
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(meta.tint.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: meta.tint.opacity(0.10), radius: 4, y: 0)
    }
}

// MARK: - AmenMessageIntentChipRow

struct AmenMessageIntentChipRow: View {
    let intents: [AmenConnectSpacesMessageIntent]
    let spaceId: String
    let messageId: String

    /// Agent 5 seam: called after care routing completes (success or error).
    var onCareRoutingComplete: ((Result<[String: Any], Error>) -> Void)?

    @State private var routingIntents: Set<AmenConnectSpacesMessageIntent> = []
    @State private var routedIntents:  Set<AmenConnectSpacesMessageIntent> = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if intents.count > 3 {
                scrollingRow
            } else {
                staticRow
            }
        }
        .alert("Care routing unavailable", isPresented: .constant(errorMessage != nil), actions: {
            Button("Dismiss") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    @ViewBuilder
    private var staticRow: some View {
        HStack(spacing: 6) {
            chips
        }
    }

    @ViewBuilder
    private var scrollingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chips
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(intents, id: \.self) { intent in
            SpaceIntentChip(intent: intent) {
                handleTap(intent)
            }
            .overlay(alignment: .topTrailing) {
                if routingIntents.contains(intent) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if routedIntents.contains(intent) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .padding(2)
                }
            }
        }
    }

    private func handleTap(_ intent: AmenConnectSpacesMessageIntent) {
        guard careSensitiveIntents.contains(intent) else { return }
        guard !routingIntents.contains(intent) else { return }

        routingIntents.insert(intent)

        Task {
            do {
                let result = try await AmenConnectSpacesCallableProxy.shared.routeCareSignal(
                    spaceId: spaceId,
                    messageId: messageId,
                    intents: [intent]
                )
                await MainActor.run {
                    routingIntents.remove(intent)
                    routedIntents.insert(intent)
                    onCareRoutingComplete?(.success(result))
                }
            } catch {
                await MainActor.run {
                    routingIntents.remove(intent)
                    errorMessage = error.localizedDescription
                    onCareRoutingComplete?(.failure(error))
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        AmenMessageIntentChipRow(
            intents: [.prayerRequest, .struggling],
            spaceId: "space-1",
            messageId: "msg-1"
        )

        AmenMessageIntentChipRow(
            intents: [.decision, .task, .risk, .question, .careFollowUp],
            spaceId: "space-1",
            messageId: "msg-2"
        )

        AmenMessageIntentChipRow(
            intents: [.testimony, .leadSunday, .volunteerNeed],
            spaceId: "space-1",
            messageId: "msg-3"
        )
    }
    .padding()
    .background(Color(hex: "#070607"))
}
#endif
