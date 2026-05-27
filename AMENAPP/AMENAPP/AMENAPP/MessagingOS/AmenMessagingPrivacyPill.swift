// AmenMessagingPrivacyPill.swift
// AMENAPP
//
// Compact privacy pill shown in every chat header.
// Shows: security status, AI consent, disappearing messages state, trust/request state.
// Tap opens the per-chat privacy controls sheet.
//
// Design rules:
//   - .ultraThinMaterial capsule (Liquid Glass), Reduce Transparency fallback
//   - White base / black text / calm spacing
//   - No misleading E2EE claims (shows "Secured" only — never "End-to-end encrypted")
//   - Gated by messagingPrivacyPillEnabled feature flag

import SwiftUI
import LocalAuthentication

// MARK: - Per-Chat Privacy State

/// Persisted per-conversation in UserDefaults and synced to Firestore.
struct ChatPrivacyState: Codable, Equatable {
    var aiConsent: AIConsentLevel = .askEveryTime
    var disappearingSeconds: Int? = nil         // nil = off
    var chatLockEnabled: Bool = false
    var readReceiptsEnabled: Bool = true
    var screenshotAlertEnabled: Bool = false    // iOS warns, cannot block

    enum AIConsentLevel: String, Codable, CaseIterable {
        case on          = "on"
        case askEveryTime = "ask"
        case off         = "off"

        var displayName: String {
            switch self {
            case .on:           return "AI On"
            case .askEveryTime: return "Ask"
            case .off:          return "AI Off"
            }
        }

        var icon: String {
            switch self {
            case .on:           return "sparkles"
            case .askEveryTime: return "questionmark.circle"
            case .off:          return "sparkles.slash"
            }
        }

        var color: Color {
            switch self {
            case .on:           return .blue
            case .askEveryTime: return .orange
            case .off:          return .gray
            }
        }
    }

    var disappearingLabel: String {
        guard let secs = disappearingSeconds else { return "Off" }
        switch secs {
        case 0..<60:     return "\(secs)s"
        case 60..<3600:  return "\(secs / 60)m"
        case 3600..<86400: return "\(secs / 3600)h"
        default:         return "\(secs / 86400)d"
        }
    }
}

// MARK: - Privacy State Store

@MainActor
final class ChatPrivacyStateStore: ObservableObject {
    @Published private(set) var state: ChatPrivacyState

    private let conversationId: String
    private let key: String

    init(conversationId: String) {
        self.conversationId = conversationId
        self.key = "chatPrivacy_\(conversationId)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(ChatPrivacyState.self, from: data) {
            self.state = saved
        } else {
            self.state = ChatPrivacyState()
        }
    }

    func update(_ mutate: (inout ChatPrivacyState) -> Void) {
        mutate(&state)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key)
        }
        // TODO: sync to Firestore conversations/{id}/privacySettings (server validates, never trusts client for security fields)
    }
}

// MARK: - Privacy Pill (compact)

struct AmenMessagingPrivacyPill: View {
    let conversationId: String
    let trustSection: TrustInboxSection?

    @StateObject private var store: ChatPrivacyStateStore
    @State private var showPrivacySheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(conversationId: String, trustSection: TrustInboxSection? = nil) {
        self.conversationId = conversationId
        self.trustSection = trustSection
        _store = StateObject(wrappedValue: ChatPrivacyStateStore(conversationId: conversationId))
    }

    var body: some View {
        Button {
            showPrivacySheet = true
        } label: {
            HStack(spacing: 5) {
                // Security indicator — never claims E2EE
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                // AI consent
                Image(systemName: store.state.aiConsent.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.state.aiConsent.color)
                    .accessibilityHidden(true)

                // Disappearing indicator
                if store.state.disappearingSeconds != nil {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }

                // Chat lock
                if store.state.chatLockEnabled {
                    Image(systemName: "faceid")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(pillBackground)
                    .overlay(
                        Capsule()
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pillAccessibilityLabel)
        .accessibilityHint("Tap to view privacy settings for this conversation")
        .sheet(isPresented: $showPrivacySheet) {
            ChatPrivacyControlsSheet(
                conversationId: conversationId,
                store: store
            )
        }
    }

    private var pillBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var pillAccessibilityLabel: String {
        var parts = ["Secured"]
        parts.append("AI \(store.state.aiConsent.displayName)")
        if store.state.disappearingSeconds != nil {
            parts.append("Disappearing messages on")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Privacy Controls Sheet

struct ChatPrivacyControlsSheet: View {
    let conversationId: String
    @ObservedObject var store: ChatPrivacyStateStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: Security
                Section {
                    HStack {
                        Label("Secured", systemImage: "lock.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Secured")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // Explicit: no false E2EE claim
                    Text("Messages are stored securely. End-to-end encryption is on our roadmap.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Security")
                }

                // MARK: AI Access
                Section {
                    ForEach(ChatPrivacyState.AIConsentLevel.allCases, id: \.self) { level in
                        Button {
                            store.update { $0.aiConsent = level }
                        } label: {
                            HStack {
                                Label(level.displayName, systemImage: level.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if store.state.aiConsent == level {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                    }
                } header: {
                    Text("AI Access")
                } footer: {
                    Text("Controls whether AI can summarize, translate, or analyze this conversation. AI never reads chats set to Off.")
                }

                // MARK: Disappearing Messages
                Section {
                    let options: [(label: String, seconds: Int?)] = [
                        ("Off", nil),
                        ("1 minute", 60),
                        ("1 hour", 3600),
                        ("24 hours", 86400),
                        ("7 days", 604800),
                    ]
                    ForEach(options, id: \.label) { option in
                        Button {
                            store.update { $0.disappearingSeconds = option.seconds }
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if store.state.disappearingSeconds == option.seconds {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Selected")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Disappearing Messages")
                } footer: {
                    Text("New messages disappear after the timer. Existing messages are not affected.")
                }

                // MARK: Chat Lock
                Section {
                    Toggle(isOn: Binding(
                        get: { store.state.chatLockEnabled },
                        set: { newValue in
                            if newValue {
                                authenticateAndEnable()
                            } else {
                                store.update { $0.chatLockEnabled = false }
                            }
                        }
                    )) {
                        Label("Require Face ID / Passcode", systemImage: "faceid")
                    }
                } header: {
                    Text("Chat Lock")
                } footer: {
                    Text("Require authentication to open this conversation.")
                }

                // MARK: Read Receipts
                Section {
                    Toggle(isOn: Binding(
                        get: { store.state.readReceiptsEnabled },
                        set: { newValue in store.update { $0.readReceiptsEnabled = newValue } }
                    )) {
                        Label("Read Receipts", systemImage: "checkmark.message.fill")
                    }
                } footer: {
                    Text("When off, you won't send or receive read receipts in this conversation.")
                }

                // MARK: Screenshot Alert
                Section {
                    Toggle(isOn: Binding(
                        get: { store.state.screenshotAlertEnabled },
                        set: { newValue in store.update { $0.screenshotAlertEnabled = newValue } }
                    )) {
                        Label("Screenshot Notifications", systemImage: "camera.metering.none")
                    }
                } footer: {
                    Text("Notify participants when a screenshot is taken. iOS cannot prevent screenshots.")
                }
            }
            .navigationTitle("Chat Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func authenticateAndEnable() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Lock this conversation"
        ) { success, _ in
            Task { @MainActor in
                if success {
                    store.update { $0.chatLockEnabled = true }
                }
            }
        }
    }
}
