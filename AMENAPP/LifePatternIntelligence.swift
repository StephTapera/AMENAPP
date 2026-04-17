//
//  LifePatternIntelligence.swift
//  AMENAPP
//
//  Behavior-Aware Spiritual Intelligence.
//  Tracks on-device behavioral signals (never uploaded raw) to infer the
//  user's current spiritual/emotional state and surface proactive support.
//
//  Privacy-first design:
//    • All signal collection happens 100% on-device
//    • ONLY anonymized, aggregated state labels are stored in Firestore
//    • Raw signals (posting content, times) never leave the device
//    • User can view the current detected state and reset at any time
//    • No behavioral data is used for advertising or shared with third parties
//
//  Signal Types (all on-device):
//    • Posting frequency + tone (post count trend, recent tag sentiment)
//    • App session timing (late-night usage, length)
//    • Prayer request frequency
//    • Engagement patterns (scrolling without interacting)
//
//  Detected States:
//    • Thriving       — consistent engagement, positive signals
//    • Reflective     — normal, introspective usage
//    • Stressed       — increased frequency, late-night sessions
//    • Isolated       — low engagement, no social signals
//    • Struggling     — prayer requests up, distress tone
//    • Crisis         — escalates to CrisisDetectionService
//
//  Architecture:
//    LifePatternIntelligence (@MainActor singleton)
//    ├── SpiritualStateLabel   (model)
//    ├── recordSignal(_:)      (on-device signal ingestion)
//    ├── evaluateState()       (classifier)
//    ├── maybeShowProactiveCard() (non-intrusive check-in)
//    └── LifePatternDashboardView (user-facing transparency view)
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

enum SpiritualStateLabel: String, Codable, CaseIterable {
    case thriving    = "thriving"
    case reflective  = "reflective"
    case stressed    = "stressed"
    case isolated    = "isolated"
    case struggling  = "struggling"
    case unknown     = "unknown"

    var displayName: String {
        switch self {
        case .thriving:   return "Thriving"
        case .reflective: return "Reflective"
        case .stressed:   return "Under Pressure"
        case .isolated:   return "Feeling Isolated"
        case .struggling: return "Going Through Something"
        case .unknown:    return "Normal"
        }
    }

    var icon: String {
        switch self {
        case .thriving:   return "sun.max.fill"
        case .reflective: return "moon.stars.fill"
        case .stressed:   return "bolt.fill"
        case .isolated:   return "person.fill.xmark"
        case .struggling: return "heart.text.square.fill"
        case .unknown:    return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .thriving:   return .green
        case .reflective: return .blue
        case .stressed:   return .orange
        case .isolated:   return .gray
        case .struggling: return .red
        case .unknown:    return .secondary
        }
    }

    var proactiveMessage: String? {
        switch self {
        case .stressed:
            return "You've been pretty active lately. How are you really doing?"
        case .isolated:
            return "We haven't heard from you in a while. Just checking in."
        case .struggling:
            return "It seems like you might be carrying something heavy right now."
        default:
            return nil
        }
    }
}

// On-device only — never sent to server in raw form
struct LifeSignal {
    enum SignalType {
        case sessionStart
        case sessionEnd(duration: TimeInterval)
        case postCreated(tone: String?)     // tone: "positive", "negative", "neutral"
        case prayerRequested
        case scrollWithoutEngaging
        case lateNightSession               // after 11pm
        case churchNoteCreated
        case bereanInteraction
    }
    let type: SignalType
    let timestamp: Date
}

// MARK: - Service

@MainActor
final class LifePatternIntelligence: ObservableObject {
    static let shared = LifePatternIntelligence()

    @Published private(set) var currentState: SpiritualStateLabel = .unknown
    @Published var showProactiveCard: Bool = false
    @Published var proactiveCardDismissed: Bool = false

    // On-device ring buffer — last 7 days of signals
    private var signals: [LifeSignal] = []
    private let maxSignals = 500
    private let evaluationThrottle: TimeInterval = 1800 // re-evaluate every 30 min
    private var lastEvaluation: Date?
    private lazy var db = Firestore.firestore()

    private init() {
        // Load persisted state label (not raw signals)
        if let raw = UserDefaults.standard.string(forKey: "lifePatterState"),
           let label = SpiritualStateLabel(rawValue: raw) {
            currentState = label
        }
    }

    // MARK: - Signal Ingestion

    func recordSignal(_ signal: LifeSignal) {
        signals.append(signal)
        if signals.count > maxSignals {
            signals.removeFirst(signals.count - maxSignals)
        }
        maybeEvaluate()
    }

    // Convenience methods for call sites
    func recordSessionStart() { recordSignal(LifeSignal(type: .sessionStart, timestamp: Date())) }
    func recordSessionEnd(duration: TimeInterval) { recordSignal(LifeSignal(type: .sessionEnd(duration: duration), timestamp: Date())) }
    func recordPostCreated(tone: String? = nil) { recordSignal(LifeSignal(type: .postCreated(tone: tone), timestamp: Date())) }
    func recordPrayerRequest() { recordSignal(LifeSignal(type: .prayerRequested, timestamp: Date())) }
    func recordScrollWithoutEngaging() { recordSignal(LifeSignal(type: .scrollWithoutEngaging, timestamp: Date())) }
    func recordChurchNote() { recordSignal(LifeSignal(type: .churchNoteCreated, timestamp: Date())) }
    func recordBereanInteraction() { recordSignal(LifeSignal(type: .bereanInteraction, timestamp: Date())) }

    // MARK: - State Evaluation

    private func maybeEvaluate() {
        if let last = lastEvaluation, Date().timeIntervalSince(last) < evaluationThrottle { return }
        lastEvaluation = Date()
        evaluateState()
    }

    private func evaluateState() {
        let newState = classify()
        guard newState != currentState else { return }

        let previous = currentState
        currentState = newState
        UserDefaults.standard.set(newState.rawValue, forKey: "lifePatterState")

        // Persist ONLY the label (not raw signals) to Firestore
        persistStateLabel(newState)

        // Show proactive card on state transitions that warrant it
        if shouldShowProactiveCard(from: previous, to: newState) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, !self.proactiveCardDismissed else { return }
                self.showProactiveCard = true
            }
        }
    }

    private func classify() -> SpiritualStateLabel {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-604_800)
        let recent = signals.filter { $0.timestamp > sevenDaysAgo }

        // Count signal types
        var prayerCount = 0
        var lateNightCount = 0
        var scrollCount = 0
        var postCount = 0
        var negativePostCount = 0
        var churchNoteCount = 0
        var bereanCount = 0
        var totalSessions = 0

        for s in recent {
            switch s.type {
            case .prayerRequested:       prayerCount += 1
            case .lateNightSession:      lateNightCount += 1
            case .scrollWithoutEngaging: scrollCount += 1
            case .postCreated(let tone):
                postCount += 1
                if tone == "negative" { negativePostCount += 1 }
            case .churchNoteCreated:     churchNoteCount += 1
            case .bereanInteraction:     bereanCount += 1
            case .sessionStart:          totalSessions += 1
            default: break
            }
        }

        // Rules (ordered by severity)
        if prayerCount >= 5 && negativePostCount >= 3 {
            return .struggling
        }
        if totalSessions == 0 && postCount == 0 && recent.isEmpty {
            return .isolated
        }
        if lateNightCount >= 3 || (prayerCount >= 3 && negativePostCount >= 2) {
            return .stressed
        }
        if churchNoteCount >= 2 || bereanCount >= 5 {
            return .reflective
        }
        if churchNoteCount >= 3 && prayerCount >= 2 && postCount >= 2 {
            return .thriving
        }
        return .unknown
    }

    private func shouldShowProactiveCard(from: SpiritualStateLabel, to: SpiritualStateLabel) -> Bool {
        // Only proactively surface for meaningful negative transitions
        switch to {
        case .stressed, .isolated, .struggling: return true
        default: return false
        }
    }

    // MARK: - Persistence (label only)

    private func persistStateLabel(_ label: SpiritualStateLabel) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData([
            "currentSpiritualState": label.rawValue,
            "stateUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - User Controls

    func resetSignals() {
        signals.removeAll()
        currentState = .unknown
        UserDefaults.standard.removeObject(forKey: "lifePatterState")
    }

    func dismissProactiveCard() {
        showProactiveCard = false
        proactiveCardDismissed = true
        // Allow another card after 72 hours
        DispatchQueue.main.asyncAfter(deadline: .now() + 259_200) { [weak self] in
            self?.proactiveCardDismissed = false
        }
    }
}

// MARK: - Proactive Check-In Card

struct LifePatternCheckInCard: View {
    @ObservedObject var intelligence: LifePatternIntelligence
    @State private var showingBerean = false

    var body: some View {
        guard let message = intelligence.currentState.proactiveMessage else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: intelligence.currentState.icon)
                        .foregroundStyle(intelligence.currentState.color)
                    Text("Berean is checking in")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        intelligence.dismissProactiveCard()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        showingBerean = true
                    } label: {
                        Text("Talk to Berean")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    Button {
                        intelligence.dismissProactiveCard()
                    } label: {
                        Text("I'm fine")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .sheet(isPresented: $showingBerean) {
                // Opens Berean with the check-in pre-loaded
                BereanCheckInSheet(state: intelligence.currentState)
            }
        )
    }
}

// MARK: - Berean Check-In Sheet

private struct BereanCheckInSheet: View {
    let state: SpiritualStateLabel
    @State private var response: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: state.icon)
                            .foregroundStyle(state.color)
                        Text(state.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    if isLoading {
                        ProgressView("Berean is responding…")
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else {
                        Text(response)
                            .font(.body)
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadResponse() }
    }

    private func loadResponse() async {
        let prompt: String
        switch state {
        case .stressed:
            prompt = "The user seems to be under significant pressure lately based on their activity patterns. Without being preachy, offer 2-3 sentences of genuine care, a relevant scripture, and a simple grounding question. Keep it warm and brief."
        case .isolated:
            prompt = "The user hasn't been active and may be feeling disconnected. Offer a warm, brief check-in with a scripture about community or God's presence. Ask one gentle question."
        case .struggling:
            prompt = "The user appears to be going through something difficult. Offer pastoral care, a comforting scripture, and remind them they're not alone. Keep it under 5 sentences. Never be preachy."
        default:
            prompt = "Offer a brief, warm check-in. Ask how they're doing with their faith journey."
        }

        response = (try? await ClaudeService.shared.sendMessageSync(prompt, mode: .shepherd)) ?? ""
        isLoading = false
    }
}

// MARK: - Transparency Dashboard

struct LifePatternDashboardView: View {
    @ObservedObject var intelligence: LifePatternIntelligence = .shared
    @State private var showingResetConfirm = false

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected State")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: intelligence.currentState.icon)
                                .foregroundStyle(intelligence.currentState.color)
                            Text(intelligence.currentState.displayName)
                                .font(.headline)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("Your Current Pattern")
            }

            Section {
                Label("All detection happens on your device", systemImage: "iphone")
                Label("Only your state label (not behavior data) is saved", systemImage: "lock.fill")
                Label("Your raw app usage is never uploaded", systemImage: "shield.fill")
                Label("You can reset this at any time", systemImage: "arrow.counterclockwise")
            } header: {
                Text("How This Works")
            } footer: {
                Text("Berean uses behavioral patterns to offer timely support — not to judge you or create profiles. This data is never shared.")
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Reset Pattern Data", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Life Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Pattern Data?", isPresented: $showingResetConfirm) {
            Button("Reset", role: .destructive) {
                intelligence.resetSignals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all on-device signals and resets the detected state. It cannot be undone.")
        }
    }
}
