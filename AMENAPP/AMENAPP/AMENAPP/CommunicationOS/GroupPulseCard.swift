// GroupPulseCard.swift
// AMENAPP
//
// Shows the current pulse of a group conversation: active topic, open questions,
// pending decisions, and a suggested next action. Gated by groupDiscussionPulseEnabled.

import SwiftUI
import FirebaseFunctions

enum GroupPulseLoadState: Equatable {
    case idle, loading, loaded(GroupPulseData), failed
    static func == (lhs: GroupPulseLoadState, rhs: GroupPulseLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.failed, .failed): return true
        case (.loaded, .loaded): return true
        default: return false
        }
    }
}

@MainActor
final class GroupPulseViewModel: ObservableObject {
    @Published var state: GroupPulseLoadState = .idle
    private var loadTask: Task<Void, Never>?

    func load(conversationId: String, isGroup: Bool) {
        guard AMENFeatureFlags.shared.groupDiscussionPulseEnabled, isGroup else { return }
        loadTask?.cancel()
        state = .loading
        AmenMessagingAnalytics.track(.groupPulseOpened)
        loadTask = Task {
            do {
                let functions = Functions.functions()
                let result = try await functions.httpsCallable("generateGroupPulse").call([
                    "conversationId": conversationId
                ])
                guard !Task.isCancelled else { return }
                if let data = result.data as? [String: Any] {
                    state = .loaded(GroupPulseData(from: data))
                    AmenMessagingAnalytics.track(.groupPulseGenerated)
                } else {
                    state = .failed
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }

    func refresh(conversationId: String, isGroup: Bool) {
        state = .idle
        load(conversationId: conversationId, isGroup: isGroup)
    }
}

struct GroupPulseCard: View {
    @StateObject private var viewModel = GroupPulseViewModel()
    let conversationId: String
    let isGroup: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let pulse):
                pulseView(pulse)
            case .failed:
                failedView
            }
        }
        .onAppear { viewModel.load(conversationId: conversationId, isGroup: isGroup) }
    }

    private var idleView: some View {
        Button {
            viewModel.load(conversationId: conversationId, isGroup: isGroup)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                Text("View Group Pulse")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.85)
            Text("Reading group pulse…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pulseView(_ pulse: GroupPulseData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            pulseHeader(pulse)
            if !pulse.openQuestions.isEmpty {
                pulseSection(title: "Open Questions", icon: "questionmark.bubble", color: .orange, items: pulse.openQuestions)
            }
            if !pulse.pendingDecisions.isEmpty {
                pulseSection(title: "Pending Decisions", icon: "checkmark.seal", color: .green, items: pulse.pendingDecisions)
            }
            if let next = pulse.suggestedNextAction {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(next)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            refreshButton
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group Pulse: \(pulse.openQuestions.count) open questions, \(pulse.pendingDecisions.count) pending decisions")
    }

    private func pulseHeader(_ pulse: GroupPulseData) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text("Group Pulse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let topic = pulse.activeTopic {
                Text(topic)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func pulseSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(items.prefix(3), id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(.secondary).font(.caption)
                    Text(item).font(.caption).foregroundStyle(.primary)
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            viewModel.refresh(conversationId: conversationId, isGroup: isGroup)
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh group pulse")
    }

    private var failedView: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text("Couldn't load group pulse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") {
                viewModel.refresh(conversationId: conversationId, isGroup: isGroup)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.blue)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var cardBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.secondarySystemBackground)) }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}
