// ONEEmotionalSafetyModeView.swift
// ONE P5-A — Emotional safety controls: slow-reply friction, tone preview, delay-send, pause thread.
//
// Design rules:
//   • All friction is strictly opt-in. Exit is instant, no confirmation needed.
//   • Tone check NEVER blocks send — it is advisory only.
//   • "Pause thread" requires confirmation; unpause is instant.
//   • Settings persist to Firestore one_users/{uid}/safetySettings.
//   • delaySend is per-session only (not persisted) to avoid message confusion on relaunch.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Duration types

enum ONESlowReplyDuration: String, CaseIterable, Sendable {
    case off, fiveMinutes = "5m", tenMinutes = "10m", thirtyMinutes = "30m"

    var label: String {
        switch self {
        case .off:           return "Off"
        case .fiveMinutes:   return "5m"
        case .tenMinutes:    return "10m"
        case .thirtyMinutes: return "30m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .off:           return 0
        case .fiveMinutes:   return 300
        case .tenMinutes:    return 600
        case .thirtyMinutes: return 1800
        }
    }
}

enum ONEDelaySendDuration: String, CaseIterable, Sendable {
    case off, fiveMinutes = "5m", tenMinutes = "10m"

    var label: String {
        switch self {
        case .off:         return "Off"
        case .fiveMinutes: return "5m"
        case .tenMinutes:  return "10m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .off:         return 0
        case .fiveMinutes: return 300
        case .tenMinutes:  return 600
        }
    }
}

// MARK: - Store

@MainActor
final class ONEEmotionalSafetyStore: ObservableObject {
    static let shared = ONEEmotionalSafetyStore()

    @Published var enabled:      Bool                  = false
    @Published var slowReply:    ONESlowReplyDuration  = .off
    @Published var tonePreview:  Bool                  = false
    @Published var delaySend:    ONEDelaySendDuration  = .off   // session-only
    @Published var threadPaused: Bool                  = false  // per-thread; reset on relaunch

    @Published var isLoading = false

    private let db = Firestore.firestore()
    private init() {}

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        let snap = try? await db.collection("one_users").document(uid)
            .collection("safetySettings").document("emotional").getDocument()
        guard let data = snap?.data() else { return }
        enabled     = data["enabled"]     as? Bool   ?? false
        tonePreview = data["tonePreview"] as? Bool   ?? false
        if let sr = data["slowReply"]    as? String { slowReply = ONESlowReplyDuration(rawValue: sr) ?? .off }
    }

    func save() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "enabled":     enabled,
            "slowReply":   slowReply.rawValue,
            "tonePreview": tonePreview,
            "updatedAt":   FieldValue.serverTimestamp()
        ]
        try? await db.collection("one_users").document(uid)
            .collection("safetySettings").document("emotional")
            .setData(payload, merge: true)
    }
}

// MARK: - ONEEmotionalSafetyModeView

struct ONEEmotionalSafetyModeView: View {
    @ObservedObject var store: ONEEmotionalSafetyStore
    let threadDisplayName: String
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showPauseConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                masterSection
                if store.enabled {
                    slowReplySection
                    tonePreviewSection
                    delaySendSection
                    pauseThreadSection
                    frictionSummarySection
                }
                exitNoticeSection
            }
            .navigationTitle("Safety Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await store.save() }
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await store.load() }
        .confirmationDialog(
            "Pause thread with \(threadDisplayName)?",
            isPresented: $showPauseConfirm,
            titleVisibility: .visible
        ) {
            Button("Pause") {
                withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                    store.threadPaused = true
                }
            }
            Button("Keep active", role: .cancel) {}
        } message: {
            Text("You won't receive messages until you unpause. \(threadDisplayName) won't be notified.")
        }
    }

    // MARK: - Sections

    private var masterSection: some View {
        Section {
            Toggle(isOn: $store.enabled.animation(ONE.Motion.adaptive(reduceMotion: reduceMotion))) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safety Mode")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Opt-in friction. Turn off instantly at any time.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(ONE.Colors.repairGreen)
                }
            }
            .tint(ONE.Colors.repairGreen)
            .accessibilityLabel("Safety mode")
            .accessibilityHint(store.enabled ? "On. Tap to turn off." : "Off. Tap to enable friction controls.")
        }
    }

    private var slowReplySection: some View {
        Section {
            LabeledContent("Wait before sending") {
                Picker("Slow reply", selection: $store.slowReply) {
                    ForEach(ONESlowReplyDuration.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .accessibilityLabel("Slow reply duration: \(store.slowReply.label)")
        } header: {
            Text("Slow Reply")
        } footer: {
            Text("Adds a confirmation delay before your message is dispatched. Time to reflect.")
                .font(.caption)
        }
    }

    private var tonePreviewSection: some View {
        Section {
            Toggle(isOn: $store.tonePreview) {
                Label("Tone preview", systemImage: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.primary)
            }
            .tint(Color.accentColor)
            .accessibilityLabel("Tone preview")
            .accessibilityHint("AI suggests softer phrasing before you send. Sending is always your choice.")
        } footer: {
            Text("Advisory only. You always choose whether to edit or send anyway.")
                .font(.caption)
        }
    }

    private var delaySendSection: some View {
        Section {
            LabeledContent("Hold before delivery") {
                Picker("Delay send", selection: $store.delaySend) {
                    ForEach(ONEDelaySendDuration.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            .accessibilityLabel("Delay send: \(store.delaySend.label)")
        } header: {
            Text("Delay Send")
        } footer: {
            Text("Messages are held locally and can be cancelled before delivery. Resets on relaunch.")
                .font(.caption)
        }
    }

    private var pauseThreadSection: some View {
        Section {
            if store.threadPaused {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thread paused")
                                .font(.system(size: 14, weight: .medium))
                            Text("Incoming muted until you resume.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(ONE.Colors.decayAmber)
                    }
                    Spacer()
                    Button("Resume") {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                            store.threadPaused = false
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ONE.Colors.repairGreen)
                    .accessibilityLabel("Resume thread")
                }
            } else {
                Button {
                    showPauseConfirm = true
                } label: {
                    Label("Pause thread", systemImage: "pause.circle.fill")
                        .foregroundStyle(ONE.Colors.decayAmber)
                }
                .accessibilityLabel("Pause thread with \(threadDisplayName)")
                .accessibilityHint("Mutes incoming messages until you resume. You can unpause instantly.")
            }
        } header: {
            Text("Pause Thread")
        } footer: {
            Text("The other person is not notified. You can unpause instantly at any time.")
                .font(.caption)
        }
    }

    private var frictionSummarySection: some View {
        let lines = activeSummaryLines
        return Group {
            if !lines.isEmpty {
                Section {
                    ForEach(lines, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    Text("Active friction")
                }
            }
        }
    }

    private var activeSummaryLines: [String] {
        var lines: [String] = []
        if store.slowReply != .off    { lines.append("Slow reply: \(store.slowReply.label) wait before send") }
        if store.tonePreview          { lines.append("Tone preview: advisory AI suggestion") }
        if store.delaySend != .off    { lines.append("Delay send: \(store.delaySend.label) hold before delivery") }
        if store.threadPaused         { lines.append("Thread paused: incoming muted") }
        return lines
    }

    private var exitNoticeSection: some View {
        Section {
            HStack(alignment: .top, spacing: ONE.Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text("Safety mode turns off instantly. Block or sever is always available from the profile, independent of this setting.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
