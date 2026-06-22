// ConnectSmartBereanBar.swift
// AMEN Connect — Wave 4 (ff: connectSmartBereanEnabled)
//
// Context-aware Berean pill with real backend path (bereanQuestion callable,
// App Check + Auth enforced by the existing function contract).
// Pill collapses to sparkle orb on scroll-down; re-expands on scroll-up.
// Intent routing: keyword-matched intents render a glass action chip before
// calling the backend, so navigation is instant for common commands.
//
// W4 Total Control Wiring Certificate:
// Surface                        Flag                     Status
// ConnectSmartBereanBar          connectSmartBereanEnabled Wired in AmenConnectV2RootView bottomChrome
// ConnectBadgeStore.shared       connectSmartBereanEnabled Accessed by V2RootView
// Intent routing                 connectSmartBereanEnabled Wired via handleBereanIntent(_:)
// bereanQuestion callable        connectSmartBereanEnabled Real Firebase function, App Check + Auth
// Reduce Motion                  (invariant)              Verified
// Glass: pill uses .amenGlassEffect, no glass-on-glass    Verified

import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import Observation

// MARK: - Intent enum

enum ConnectBereanIntent {
    case catchUp
    case goTo(ConnectSection)
    case openComposer
    case none
}

// MARK: - Badge store

@Observable
@MainActor
final class ConnectBadgeStore {

    static let shared = ConnectBadgeStore()

    private var counts: [ConnectSection: Int] = [:]

    func count(for section: ConnectSection) -> Int? {
        counts[section]
    }

    func setBadge(_ count: Int, for section: ConnectSection) {
        counts[section] = count > 0 ? count : nil
    }

    func clearBadge(for section: ConnectSection) {
        counts.removeValue(forKey: section)
    }
}

// MARK: - Smart Berean Bar

struct ConnectSmartBereanBar: View {

    var section: ConnectSection
    var expanded: Bool
    var onIntent: (ConnectBereanIntent) -> Void

    @State private var query = ""
    @State private var isQuerying = false
    @State private var response: String?
    @State private var pendingIntent: ConnectBereanIntent?
    @State private var showResponseSheet = false

    @Environment(\.accessibilityReduceMotion) private var rm
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let functions = Functions.functions()

    var body: some View {
        Group {
            if expanded {
                expandedPill
            } else {
                collapsedOrb
            }
        }
        .animation(rm ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.84), value: expanded)
        .sheet(isPresented: $showResponseSheet) {
            bereanResponseSheet
        }
    }

    // MARK: Expanded pill

    private var expandedPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            TextField(section.bereanPlaceholder, text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.sentences)
                .onSubmit { Task { await submitQuery() } }
                .accessibilityLabel(section.bereanPlaceholder)
                .frame(minHeight: 44)

            if isQuerying {
                ProgressView()
                    .scaleEffect(0.75)
                    .accessibilityLabel("Berean is thinking")
            } else if !query.isEmpty {
                Button {
                    Task { await submitQuery() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Ask Berean")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(pillBackground)
        .cornerRadius(26)
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }

    // MARK: Collapsed sparkle orb

    private var collapsedOrb: some View {
        Button { Task { await submitQuery() } } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(pillBackground)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Berean: \(section.bereanPlaceholder)")
    }

    @ViewBuilder
    private var pillBackground: some View {
        if #available(iOS 26, *), !reduceTransparency {
            Color.clear.amenGlassEffect()
        } else {
            Color(.secondarySystemBackground)
        }
    }

    // MARK: Response sheet with intent chip

    private var bereanResponseSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let r = response {
                        Text(r)
                            .font(.body)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // Intent action chip — instant navigation
                    if let intent = pendingIntent, intent != .none {
                        Button {
                            showResponseSheet = false
                            onIntent(intent)
                        } label: {
                            intentChipLabel(for: intent)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    // W2: canonical disclosure
                    Text(ConnectStrings.aiSummaryDisclosure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showResponseSheet = false }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func intentChipLabel(for intent: ConnectBereanIntent) -> some View {
        switch intent {
        case .catchUp:
            Label("Open Catch Up →", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        case .goTo(let s):
            Label("Go to \(s.rawValue) →", systemImage: s.iconName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        case .openComposer:
            Label("Open composer →", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        case .none:
            EmptyView()
        }
    }

    // MARK: Submit — keyword intent check first, then callable

    @MainActor
    private func submitQuery() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Keyword intent matching (instant, no network)
        let matched = detectIntent(trimmed)
        if matched != .none {
            pendingIntent = matched
            onIntent(matched)     // route immediately
            query = ""
            return
        }

        // Real Berean callable — bereanQuestion (App Check + Auth enforced by function)
        isQuerying = true
        defer { isQuerying = false }

        do {
            let payload: [String: Any] = [
                "query": trimmed,
                "surface": "connect",
                "section": section.rawValue.lowercased()
            ]
            let result = try await functions.httpsCallable("bereanQuestion").call(payload)
            let data = result.data as? [String: Any]
            response = data?["text"] as? String ?? "I couldn't find a specific answer. Try rephrasing."
            pendingIntent = detectIntent(response ?? "")
            query = ""
            showResponseSheet = true
        } catch {
            response = "Unable to reach Berean right now. Check your connection and try again."
            pendingIntent = ConnectBereanIntent.none
            showResponseSheet = true
        }
    }

    // MARK: Intent keyword detector

    private func detectIntent(_ text: String) -> ConnectBereanIntent {
        let lower = text.lowercased()
        if lower.contains("catch up") || lower.contains("what did i miss") || lower.contains("missed") {
            return .catchUp
        }
        if lower.contains("find a group") || lower.contains("discover") || lower.contains("join") {
            return .goTo(.discover)
        }
        if lower.contains("my space") || lower.contains("spaces") {
            return .goTo(.spaces)
        }
        if lower.contains("announcement") || lower.contains("compose") || lower.contains("draft") {
            return .openComposer
        }
        if lower.contains("what's coming") || lower.contains("calendar") || lower.contains("upcoming") {
            return .goTo(.activity)
        }
        return .none
    }
}

// Equatable conformance for intent comparison
extension ConnectBereanIntent: Equatable {
    static func == (lhs: ConnectBereanIntent, rhs: ConnectBereanIntent) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.catchUp, .catchUp), (.openComposer, .openComposer): return true
        case (.goTo(let a), .goTo(let b)): return a == b
        default: return false
        }
    }
}
