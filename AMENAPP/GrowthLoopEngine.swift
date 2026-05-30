//
//  GrowthLoopEngine.swift
//  AMENAPP
//
//  Standalone Growth Loop System — turns content into behavior change over time.
//  Moves users from passive consumption → active discipleship through structured
//  follow-up at key intervals.
//
//  Loop structure (per item):
//    Day 0:  Item created (note, sermon, verse, Berean response)
//    +24h:   Reflection prompt — "What stood out to you?"
//    +3 days: Application check — "Did you apply anything from this?"
//    +7 days: Assessment — "What changed in your thinking or behavior?"
//    +30 days: Integration — "How has this shaped your faith journey?"
//
//  Growth Metrics (non-social):
//    • Consistency score    — loop completion rate
//    • Reflection depth     — response length + quality signal
//    • Obedience actions    — completed BereanActions linked to loops
//    • Engagement velocity  — time to first reflection
//
//  Architecture:
//    GrowthLoopEngine (@MainActor singleton)
//    ├── GrowthLoop         (model — one tracked content item)
//    ├── LoopCheckIn        (model — one follow-up response)
//    ├── createLoop(for:)   (Firestore write + notification schedule)
//    ├── submitCheckIn(_:)  (records user reflection)
//    ├── computeMetrics()   (aggregated growth stats)
//    └── GrowthDashboardView (SwiftUI)
//

import Foundation
import SwiftUI
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct GrowthLoop: Identifiable, Codable {
    var id: String = UUID().uuidString
    let title: String
    let sourceType: LoopSourceType
    let sourceId: String            // noteId, sermonId, verseRef, bereanResponseId
    let createdAt: Date
    var checkIns: [LoopCheckIn]
    var currentPhase: LoopPhase
    var isComplete: Bool
    var qualityScore: Double        // 0.0 – 1.0, computed from reflection depth

    enum LoopSourceType: String, Codable {
        case churchNote   = "church_note"
        case sermon       = "sermon"
        case verse        = "verse"
        case bereanAnswer = "berean_answer"
        case action       = "action"
    }

    enum LoopPhase: String, Codable, CaseIterable {
        case created     = "created"       // Day 0
        case reflect     = "reflect"       // +24h
        case apply       = "apply"         // +3 days
        case assess      = "assess"        // +7 days
        case integrate   = "integrate"     // +30 days
        case complete    = "complete"

        var displayName: String {
            switch self {
            case .created:   return "Just Started"
            case .reflect:   return "Reflection"
            case .apply:     return "Application"
            case .assess:    return "Assessment"
            case .integrate: return "Integration"
            case .complete:  return "Complete"
            }
        }

        var promptQuestion: String {
            switch self {
            case .created:
                return "What resonated with you most from this?"
            case .reflect:
                return "After sitting with this for a day — what stood out? What are you still thinking about?"
            case .apply:
                return "Have you applied anything from this in the last few days? What happened?"
            case .assess:
                return "Looking back this week — how has this shaped your thinking, attitude, or behavior?"
            case .integrate:
                return "One month later — how has this become part of your faith walk? What's different?"
            case .complete:
                return "This growth loop is complete. How has God used this in your life?"
            }
        }

        var dayOffset: Int {
            switch self {
            case .created:   return 0
            case .reflect:   return 1
            case .apply:     return 3
            case .assess:    return 7
            case .integrate: return 30
            case .complete:  return 31
            }
        }
    }
}

struct LoopCheckIn: Identifiable, Codable {
    let id: String
    let phase: GrowthLoop.LoopPhase
    let prompt: String
    var response: String
    let submittedAt: Date
    var wordCount: Int { response.split(separator: " ").count }
}

// MARK: - Growth Metrics

struct GrowthMetrics: Codable {
    var totalLoops: Int = 0
    var completedLoops: Int = 0
    var averageQualityScore: Double = 0
    var totalCheckIns: Int = 0
    var consistencyScore: Double = 0    // (completed / total)
    var reflectionDepthScore: Double = 0 // avg word count normalized
    var obedienceActionCount: Int = 0
    var longestStreak: Int = 0          // consecutive days with a loop activity

    var completionRate: Double {
        guard totalLoops > 0 else { return 0 }
        return Double(completedLoops) / Double(totalLoops)
    }
}

// MARK: - Service

@MainActor
final class GrowthLoopEngine: ObservableObject {
    static let shared = GrowthLoopEngine()

    @Published var activeLoops: [GrowthLoop] = []
    @Published var completedLoops: [GrowthLoop] = []
    @Published var metrics: GrowthMetrics = GrowthMetrics()
    @Published var pendingCheckIn: GrowthLoop?  // loop awaiting user response
    @Published var isLoading: Bool = false

    private lazy var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?

    private init() {
        Task { await loadLoops() }
    }

    deinit {
        listenerRegistration?.remove()
    }

    // MARK: - Reset (call on sign-out to prevent cross-user data leakage)

    /// Stops the Firestore listener and clears all per-user published state.
    /// Leaves the singleton in the same state it would be in after first init.
    func reset() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        activeLoops.removeAll()
        completedLoops.removeAll()
        metrics = GrowthMetrics()
        pendingCheckIn = nil
        isLoading = false
        dlog("🧹 GrowthLoopEngine: user state cleared on sign-out")
    }

    // MARK: - Create Loop

    /// Call this whenever significant content is created (note, sermon, Berean answer).
    func createLoop(title: String, sourceType: GrowthLoop.LoopSourceType, sourceId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let loop = GrowthLoop(
            title: title,
            sourceType: sourceType,
            sourceId: sourceId,
            createdAt: Date(),
            checkIns: [],
            currentPhase: .created,
            isComplete: false,
            qualityScore: 0
        )

        let data = encodeLoop(loop)
        try? await db.collection("users").document(uid)
            .collection("growthLoops")
            .document(loop.id)
            .setData(data)

        scheduleNotifications(for: loop)
        activeLoops.insert(loop, at: 0)
        await computeMetrics()
    }

    // MARK: - Submit Check-In

    func submitCheckIn(loopId: String, phase: GrowthLoop.LoopPhase, response: String) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let idx = activeLoops.firstIndex(where: { $0.id == loopId }) else { return }

        let checkIn = LoopCheckIn(
            id: UUID().uuidString,
            phase: phase,
            prompt: phase.promptQuestion,
            response: response,
            submittedAt: Date()
        )

        activeLoops[idx].checkIns.append(checkIn)
        activeLoops[idx].currentPhase = nextPhase(after: phase)

        if activeLoops[idx].currentPhase == .complete {
            activeLoops[idx].isComplete = true
        }

        activeLoops[idx].qualityScore = computeQualityScore(for: activeLoops[idx])

        // Persist
        let updated = activeLoops[idx]
        let data = encodeLoop(updated)
        try? await db.collection("users").document(uid)
            .collection("growthLoops")
            .document(loopId)
            .setData(data)

        pendingCheckIn = nil
        await computeMetrics()
    }

    // MARK: - Load

    func loadLoops() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        let snap = try? await db.collection("users").document(uid)
            .collection("growthLoops")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        var active: [GrowthLoop] = []
        var completed: [GrowthLoop] = []

        for doc in snap?.documents ?? [] {
            if let loop = decodeLoop(doc.data()) {
                if loop.isComplete { completed.append(loop) }
                else               { active.append(loop) }
            }
        }

        activeLoops = active
        completedLoops = completed
        isLoading = false
        await computeMetrics()
    }

    // MARK: - Metrics

    func computeMetrics() async {
        let all = activeLoops + completedLoops
        guard !all.isEmpty else { metrics = GrowthMetrics(); return }

        let completed = all.filter { $0.isComplete }.count
        let allCheckIns = all.flatMap { $0.checkIns }
        let avgWords = allCheckIns.isEmpty ? 0.0 : Double(allCheckIns.reduce(0) { $0 + $1.wordCount }) / Double(allCheckIns.count)
        let avgQuality = all.map { $0.qualityScore }.reduce(0, +) / Double(all.count)

        metrics = GrowthMetrics(
            totalLoops: all.count,
            completedLoops: completed,
            averageQualityScore: avgQuality,
            totalCheckIns: allCheckIns.count,
            consistencyScore: Double(completed) / Double(all.count),
            reflectionDepthScore: min(avgWords / 100.0, 1.0),
            obedienceActionCount: 0 // linked via BereanActionEngine
        )

        // Persist metrics summary
        if let uid = Auth.auth().currentUser?.uid {
            let metricsData: [String: Any] = [
                "totalLoops": metrics.totalLoops,
                "completedLoops": metrics.completedLoops,
                "consistencyScore": metrics.consistencyScore,
                "reflectionDepthScore": metrics.reflectionDepthScore,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try? await db.collection("users").document(uid).setData(["growthMetrics": metricsData], merge: true)
        }
    }

    // MARK: - Notifications

    private func scheduleNotifications(for loop: GrowthLoop) {
        let center = UNUserNotificationCenter.current()
        let phases: [GrowthLoop.LoopPhase] = [.reflect, .apply, .assess, .integrate]

        for phase in phases {
            let content = UNMutableNotificationContent()
            content.title = "Growth Check-In: \(loop.title)"
            content.body = phase.promptQuestion
            content.sound = .default
            content.userInfo = ["loopId": loop.id, "phase": phase.rawValue]

            let delay = TimeInterval(phase.dayOffset * 86_400)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let req = UNNotificationRequest(
                identifier: "growth_\(loop.id)_\(phase.rawValue)",
                content: content,
                trigger: trigger
            )
            center.add(req)
        }
    }

    // MARK: - Helpers

    private func nextPhase(after phase: GrowthLoop.LoopPhase) -> GrowthLoop.LoopPhase {
        let all = GrowthLoop.LoopPhase.allCases
        guard let idx = all.firstIndex(of: phase), idx + 1 < all.count else { return .complete }
        return all[idx + 1]
    }

    private func computeQualityScore(for loop: GrowthLoop) -> Double {
        guard !loop.checkIns.isEmpty else { return 0 }
        let avgWords = Double(loop.checkIns.reduce(0) { $0 + $1.wordCount }) / Double(loop.checkIns.count)
        let completionRatio = Double(loop.checkIns.count) / Double(GrowthLoop.LoopPhase.allCases.count - 2) // exclude created + complete
        let wordScore = min(avgWords / 80.0, 1.0)
        return (completionRatio * 0.5) + (wordScore * 0.5)
    }

    private func encodeLoop(_ loop: GrowthLoop) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(loop),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    private func decodeLoop(_ dict: [String: Any]) -> GrowthLoop? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(GrowthLoop.self, from: data)
    }
}

// MARK: - Growth Dashboard View

struct GrowthDashboardView: View {
    @ObservedObject private var engine = GrowthLoopEngine.shared // PERF: singleton → @ObservedObject
    @State private var showingCheckIn: GrowthLoop?

    var body: some View {
        NavigationStack {
            List {
                // Metrics summary
                Section {
                    MetricsSummaryCard(metrics: engine.metrics)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // Active loops
                if !engine.activeLoops.isEmpty {
                    Section("Active Growth Loops") {
                        ForEach(engine.activeLoops) { loop in
                            GrowthLoopRow(loop: loop, onCheckIn: {
                                showingCheckIn = loop
                            })
                        }
                    }
                }

                // Completed
                if !engine.completedLoops.isEmpty {
                    Section("Completed") {
                        ForEach(engine.completedLoops) { loop in
                            GrowthLoopRow(loop: loop, onCheckIn: nil)
                        }
                    }
                }
            }
            .navigationTitle("Growth")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await engine.loadLoops() }
            .sheet(item: $showingCheckIn) { loop in
                GrowthCheckInSheet(loop: loop)
            }
            .overlay {
                if engine.isLoading && engine.activeLoops.isEmpty {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Metrics Summary Card

private struct MetricsSummaryCard: View {
    let metrics: GrowthMetrics

    var body: some View {
        HStack(spacing: 0) {
            StatCell(label: "Loops", value: "\(metrics.totalLoops)", icon: "arrow.clockwise.circle.fill", color: .indigo)
            Divider()
            StatCell(label: "Completed", value: "\(Int(metrics.consistencyScore * 100))%", icon: "checkmark.seal.fill", color: .green)
            Divider()
            StatCell(label: "Depth", value: "\(Int(metrics.reflectionDepthScore * 100))%", icon: "brain.head.profile", color: .blue)
            Divider()
            StatCell(label: "Check-ins", value: "\(metrics.totalCheckIns)", icon: "pencil.and.outline", color: .orange)
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Loop Row

private struct GrowthLoopRow: View {
    let loop: GrowthLoop
    let onCheckIn: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loop.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(loop.currentPhase.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if loop.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if let onCheckIn {
                    Button("Check In", action: onCheckIn)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }

            // Phase progress bar
            PhaseProgressBar(loop: loop)
        }
        .padding(.vertical, 4)
    }
}

private struct PhaseProgressBar: View {
    let loop: GrowthLoop
    private let phases: [GrowthLoop.LoopPhase] = [.created, .reflect, .apply, .assess, .integrate, .complete]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(phases.dropLast(), id: \.rawValue) { phase in
                let done = isPhaseCompleted(phase)
                RoundedRectangle(cornerRadius: 2)
                    .fill(done ? Color.indigo : Color(.systemGray5))
                    .frame(height: 4)
            }
        }
    }

    private func isPhaseCompleted(_ phase: GrowthLoop.LoopPhase) -> Bool {
        loop.checkIns.contains { $0.phase == phase }
    }
}

// MARK: - Check-In Sheet

struct GrowthCheckInSheet: View {
    let loop: GrowthLoop
    @State private var response: String = ""
    @State private var isSubmitting: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Phase context
                VStack(alignment: .leading, spacing: 4) {
                    Text(loop.currentPhase.displayName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Text(loop.title)
                        .font(.title3.weight(.semibold))
                }
                .padding(.horizontal)

                // Prompt
                Text(loop.currentPhase.promptQuestion)
                    .font(.body)
                    .padding()
                    .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                // Response
                TextEditor(text: $response)
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Text("\(response.split(separator: " ").count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        await GrowthLoopEngine.shared.submitCheckIn(
                            loopId: loop.id,
                            phase: loop.currentPhase,
                            response: response
                        )
                        isSubmitting = false
                        dismiss()
                    }
                } label: {
                    Label(isSubmitting ? "Saving…" : "Submit Reflection", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(response.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Growth Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
