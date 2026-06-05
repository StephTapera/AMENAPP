// AmenAIHostAssistantPanel.swift
// AMEN Connect + Spaces — Host-Only AI Signal Panel (Live)
// Built: 2026-06-03

import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - Local types

private struct HostSignal: Identifiable {
    let id: String
    var authorName: String
    var text: String
    var ageMinutes: Int
}

private struct HostAssistantPayload {
    var questions: [HostSignal]
    var prayerRequests: [HostSignal]
    var raisedHands: [HostSignal]
    var aiSuggestion: String?
}

// MARK: - Main panel

struct AmenAIHostAssistantPanel: View {
    let streamId: String
    let isHost: Bool

    @State private var isExpanded: Bool = false
    @State private var payload: HostAssistantPayload = HostAssistantPayload(
        questions: [],
        prayerRequests: [],
        raisedHands: [],
        aiSuggestion: nil
    )
    @State private var isLoading: Bool = false
    @State private var timerCancellable: AnyCancellable? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let functions = Functions.functions()

    var body: some View {
        // Render nothing for non-hosts — callers should pass isHost accurately
        if !isHost {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                if isExpanded {
                    expandedPanel
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }

                collapsedPill
            }
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
        }
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        Button {
            let anim: Animation? = reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.8)
            withAnimation(anim) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)

                if isLoading && payload.questions.isEmpty {
                    ProgressView()
                        .tint(Color(hex: "D9A441"))
                        .scaleEffect(0.75)
                } else {
                    signalSummaryText
                }

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color(hex: "D9A441").opacity(0.5), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsedAccessibilityLabel)
        .accessibilityHint(isExpanded ? "Double-tap to collapse" : "Double-tap to expand host signals")
    }

    private var signalSummaryText: some View {
        HStack(spacing: 6) {
            let qCount = payload.questions.count
            let pCount = payload.prayerRequests.count
            let hCount = payload.raisedHands.count

            if qCount == 0 && pCount == 0 && hCount == 0 {
                Text("No signals yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            } else {
                signalChip(count: qCount, label: "question", plural: "questions")
                if pCount > 0 {
                    Text("•").foregroundStyle(Color.white.opacity(0.3)).font(.system(size: 10))
                    signalChip(count: pCount, label: "prayer request", plural: "prayer requests")
                }
                if hCount > 0 {
                    Text("•").foregroundStyle(Color.white.opacity(0.3)).font(.system(size: 10))
                    signalChip(count: hCount, label: "raised hand", plural: "raised hands")
                }
            }
        }
    }

    @ViewBuilder
    private func signalChip(count: Int, label: String, plural: String) -> some View {
        if count > 0 {
            Text("\(count) \(count == 1 ? label : plural)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var collapsedAccessibilityLabel: String {
        let q = payload.questions.count
        let p = payload.prayerRequests.count
        let h = payload.raisedHands.count
        if q == 0 && p == 0 && h == 0 {
            return "AI Host Assistant — no signals yet"
        }
        var parts: [String] = []
        if q > 0 { parts.append("\(q) \(q == 1 ? "question" : "questions")") }
        if p > 0 { parts.append("\(p) \(p == 1 ? "prayer request" : "prayer requests")") }
        if h > 0 { parts.append("\(h) raised \(h == 1 ? "hand" : "hands")") }
        return "AI Host Assistant — " + parts.joined(separator: ", ")
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // AI Suggestion banner
            if let suggestion = payload.aiSuggestion, !suggestion.isEmpty {
                aiSuggestionBanner(suggestion)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    signalSection(
                        title: "Unanswered Questions",
                        icon: "questionmark.bubble.fill",
                        accentColor: Color(hex: "245B8F"),
                        signals: payload.questions,
                        actionLabel: "Reply",
                        onAction: { _ in
                            // TODO: wire reply-to-question action (e.g. surface in chat input or callout)
                        }
                    )

                    signalSection(
                        title: "Prayer Requests",
                        icon: "hands.sparkles.fill",
                        accentColor: Color(hex: "6E4BB5"),
                        signals: payload.prayerRequests,
                        actionLabel: "Acknowledge",
                        onAction: { _ in
                            // TODO: wire acknowledgment action
                        }
                    )

                    raisedHandsSection
                }
                .padding(16)
            }
            .frame(maxHeight: 340)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "0D0D0D"))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: -4)
    }

    // MARK: - AI Suggestion Banner

    @ViewBuilder
    private func aiSuggestionBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "070607"))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "070607"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "D9A441"))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .accessibilityLabel("AI suggestion: \(text)")
    }

    // MARK: - Signal Section

    @ViewBuilder
    private func signalSection(
        title: String,
        icon: String,
        accentColor: Color,
        signals: [HostSignal],
        actionLabel: String,
        onAction: @escaping (HostSignal) -> Void
    ) -> some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    countBadge(signals.count, color: accentColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(title), \(signals.count) item\(signals.count == 1 ? "" : "s")")

                VStack(spacing: 8) {
                    ForEach(signals) { signal in
                        SignalRow(
                            signal: signal,
                            actionLabel: actionLabel,
                            accentColor: accentColor,
                            onAction: { onAction(signal) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Raised Hands Section

    @ViewBuilder
    private var raisedHandsSection: some View {
        if !payload.raisedHands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .accessibilityHidden(true)
                    Text("Raised Hands")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    countBadge(payload.raisedHands.count, color: Color(hex: "D9A441"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Raised Hands, \(payload.raisedHands.count) \(payload.raisedHands.count == 1 ? "person" : "people")")

                VStack(spacing: 8) {
                    ForEach(payload.raisedHands) { signal in
                        HStack(spacing: 10) {
                            initialsCircle(signal.authorName, color: Color(hex: "D9A441"))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.authorName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("\(signal.ageMinutes)m ago")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // "Call On" copies the name to pasteboard for the host
                            Button {
                                UIPasteboard.general.string = signal.authorName
                            } label: {
                                Text("Call On")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: "D9A441"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        Capsule()
                                            .fill(Color(hex: "D9A441").opacity(0.13))
                                            .overlay {
                                                Capsule()
                                                    .strokeBorder(Color(hex: "D9A441").opacity(0.4), lineWidth: 1)
                                            }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Call on \(signal.authorName)")
                        }
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(signal.authorName) raised hand \(signal.ageMinutes) minutes ago")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(color.opacity(0.18))
            }
    }

    @ViewBuilder
    private func initialsCircle(_ name: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 34, height: 34)
            Text(initials(for: name))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")) + String((parts[1].first ?? "?"))
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Polling

    private func startPolling() {
        guard isHost else { return }
        fetchSignals()
        timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { _ in fetchSignals() }
    }

    private func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func fetchSignals() {
        guard isHost else { return }
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let callable = functions.httpsCallable("getHostAssistantSignals")
                let result = try await callable.call(["streamId": streamId])
                guard let data = result.data as? [String: Any] else { return }

                payload = HostAssistantPayload(
                    questions: parseSignals(data["questions"]),
                    prayerRequests: parseSignals(data["prayerRequests"]),
                    raisedHands: parseSignals(data["raisedHands"]),
                    aiSuggestion: data["aiSuggestion"] as? String
                )
            } catch {
                // Non-fatal — keep existing payload; will retry on next tick
            }
        }
    }

    private func parseSignals(_ raw: Any?) -> [HostSignal] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard
                let id = dict["id"] as? String,
                let authorName = dict["authorName"] as? String,
                let text = dict["text"] as? String
            else { return nil }
            let ageMinutes = dict["ageMinutes"] as? Int ?? 0
            return HostSignal(id: id, authorName: authorName, text: text, ageMinutes: ageMinutes)
        }
    }
}

// MARK: - Signal Row

private struct SignalRow: View {
    let signal: HostSignal
    let actionLabel: String
    let accentColor: Color
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 34, height: 34)
                Text(initials(for: signal.authorName))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(signal.authorName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("• \(signal.ageMinutes)m ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(signal.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onAction) {
                Text(actionLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(accentColor.opacity(0.13))
                            .overlay {
                                Capsule().strokeBorder(accentColor.opacity(0.38), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(actionLabel) from \(signal.authorName)")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.authorName), \(signal.ageMinutes) minutes ago: \(signal.text)")
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")) + String((parts[1].first ?? "?"))
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Preview

#Preview("Host — with signals") {
    ZStack(alignment: .bottom) {
        Color(hex: "070607").ignoresSafeArea()

        AmenAIHostAssistantPanel(
            streamId: "stream-001",
            isHost: true
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
    .preferredColorScheme(.dark)
}

#Preview("Non-host — renders nothing") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        AmenAIHostAssistantPanel(
            streamId: "stream-001",
            isHost: false
        )
    }
    .preferredColorScheme(.dark)
}
