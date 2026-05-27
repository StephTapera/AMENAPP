// AmenConversationOSSurfaces.swift
// AMEN Conversation OS — Surface Definitions, Rollout Classification & Entry Points
//
// GO / GO WITH CAVEATS / NO-GO rollout gating.
// Ambient non-intrusive entry points — no aggressive overlays.

import SwiftUI

// MARK: - Surface Rollout Classification

enum ConversationOSRolloutStatus {
    case go
    case goWithCaveats(String)
    case noGo(String)
}

enum ConversationOSSurfaceClassification {

    static func status(for surface: ConversationOSSurface) -> ConversationOSRolloutStatus {
        switch surface {
        case .amenSpaces:          return .go
        case .groupMessages:       return .go
        case .churchDiscussion:    return .go
        case .bereanStudy:         return .go
        case .eventChat:           return .go
        case .creatorCommunity:    return .go
        case .orgHub:              return .go
        case .classroomDiscussion: return .goWithCaveats("Youth consent required. No student PII in summary.")
        case .directMessages:      return .goWithCaveats("On-device only. DM content never surfaces to groups.")
        case .mediaComments:       return .goWithCaveats("Public content only. No private comment summaries.")
        case .prayerRoom:          return .noGo("Sensitive pastoral content. Requires explicit room-level opt-in by admin.")
        case .leadershipRoom:      return .noGo("Restricted room. Server-side permissions must be validated before any AI access.")
        case .adminChannel:        return .noGo("Internal admin content. Admin-only opt-in required.")
        }
    }

    static func isSummaryEnabled(_ surface: ConversationOSSurface, flags: AMENFeatureFlags) -> Bool {
        guard flags.conversationOSEnabled, flags.conversationSummariesEnabled else { return false }
        switch status(for: surface) {
        case .go, .goWithCaveats: return true
        case .noGo: return false
        }
    }
}

// MARK: - Ambient Top Banner (non-intrusive unread summary trigger)

struct AmenConversationOSAmbientBanner: View {
    @ObservedObject var viewModel: AmenConversationOSViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        if viewModel.pendingActionCount > 0 || viewModel.pendingDecisionCount > 0 || viewModel.unresolvedCount > 0 {
            HStack(spacing: 6) {
                if viewModel.pendingActionCount > 0 {
                    ConversationOSPill(
                        label: "\(viewModel.pendingActionCount) action\(viewModel.pendingActionCount == 1 ? "" : "s")",
                        systemImage: "checkmark.circle",
                        color: .purple
                    )
                }
                if viewModel.pendingDecisionCount > 0 {
                    ConversationOSPill(
                        label: "\(viewModel.pendingDecisionCount) decision\(viewModel.pendingDecisionCount == 1 ? "" : "s")",
                        systemImage: "arrow.triangle.branch",
                        color: .green
                    )
                }
                if viewModel.unresolvedCount > 0 {
                    ConversationOSPill(
                        label: "\(viewModel.unresolvedCount) open",
                        systemImage: "questionmark.circle",
                        color: .orange
                    )
                }
                Spacer()
                Button {
                    viewModel.showingCatchUp = true
                } label: {
                    Text("Catch up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Open AI catch-up summary for this conversation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0) : .easeIn(duration: 0.25)) {
                    visible = true
                }
            }
        }
    }
}

// MARK: - Contextual Chip

struct ConversationOSPill: View {
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel(label)
    }
}

// MARK: - Catch-Up Sheet

struct AmenConversationOSCatchUpSheet: View {
    @ObservedObject var viewModel: AmenConversationOSViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .loading:
                    AmenConversationOSLoadingView()
                case .loaded:
                    if let summary = viewModel.summary {
                        AmenCatchUpCard(summary: summary, viewModel: viewModel)
                    } else {
                        AmenConversationOSEmptyView(message: "No summary available yet.")
                    }
                case .empty:
                    AmenConversationOSEmptyView(message: "No new activity since your last visit.")
                case .sensitiveSpaceBlocked:
                    AmenConversationOSSensitiveBlockedView()
                case .error(let msg):
                    AmenConversationOSErrorView(message: msg) {
                        Task { await viewModel.loadCatchUpRecap(unreadCount: 0, lastVisitedAt: nil) }
                    }
                default:
                    AmenConversationOSIdleView { viewModel.showingCatchUp = true }
                }
            }
            .navigationTitle("Catch Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close catch-up summary")
                }
            }
        }
    }
}

// MARK: - Empty / Error / Loading / Idle Views

struct AmenConversationOSLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Analyzing conversation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading conversation summary")
    }
}

struct AmenConversationOSEmptyView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AmenConversationOSErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
                .accessibilityLabel("Retry loading summary")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AmenConversationOSSensitiveBlockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("AI summaries are not enabled in this space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("A group admin can enable them in space settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AmenConversationOSIdleView: View {
    let onLoad: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.purple)
            Text("Tap to generate a catch-up summary")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Generate", action: onLoad)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Generate AI catch-up summary")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ViewModifier for attaching Conversation OS to any view

struct ConversationOSContextModifier: ViewModifier {
    @ObservedObject var viewModel: AmenConversationOSViewModel
    let showBanner: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if showBanner && AMENFeatureFlags.shared.ambientConversationIntelligenceEnabled {
                    AmenConversationOSAmbientBanner(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $viewModel.showingCatchUp) {
                AmenConversationOSCatchUpSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingOrgMemory) {
                AmenConversationOSOrgMemorySheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.selectedCluster) { cluster in
                AmenTopicClusterDetailSheet(cluster: cluster)
            }
    }
}

extension View {
    func conversationOS(_ viewModel: AmenConversationOSViewModel, showBanner: Bool = true) -> some View {
        modifier(ConversationOSContextModifier(viewModel: viewModel, showBanner: showBanner))
    }
}

// MARK: - Org Memory Sheet

struct AmenConversationOSOrgMemorySheet: View {
    @ObservedObject var viewModel: AmenConversationOSViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let memory = viewModel.organizationalMemory {
                    AmenOrgMemoryCard(memory: memory)
                } else {
                    AmenConversationOSEmptyView(message: "No organizational memory available yet.")
                }
            }
            .navigationTitle("Org Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Topic Cluster Detail Sheet

struct AmenTopicClusterDetailSheet: View {
    let cluster: ConversationTopicCluster
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(cluster.confidencePrefix + cluster.summary)
                        .font(.body)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                    ForEach(cluster.messages) { msg in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg.senderDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(msg.preview)
                                .font(.footnote)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle(cluster.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
