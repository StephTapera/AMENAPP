// BereanAgentModeView.swift
// AMEN — Berean Agent Surface (BAS)
// Wave 2 · Lane D: Task-entry and task-running view for BASComposerMode.agent

import SwiftUI

// MARK: - Supporting Types

struct BASPastTask: Identifiable {
    let id = UUID()
    let summary: String
    let timestamp: String
}

// MARK: - BereanAgentModeView

struct BereanAgentModeView: View {

    // MARK: - Inputs

    let isRunning: Bool
    let activePlugins: [BASPlugin]
    let currentTask: String
    /// Past tasks to display in Recent Tasks. Pass [] to show the "Ready to help" empty state.
    let pastTasks: [BASPastTask]
    let onTaskSuggestionTapped: (String) -> Void
    /// Called when the user taps "Ask Berean" from the empty state — host should focus the composer.
    let onFocusComposer: () -> Void
    let onCancel: () -> Void

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Private constants

    private let suggestions: [String] = [
        "Plan my Bible study",
        "Prepare sermon notes from Romans 6",
        "Build a prayer routine",
        "Summarize this meeting",
        "Audit my answer before I post"
    ]

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.basWarmPaper
                .ignoresSafeArea()

            if isRunning {
                runningState
                    .transition(.opacity)
            } else {
                idleState
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.16)
                : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: isRunning
        )
    }

    // MARK: - Idle State

    private var idleState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                Text("What should Berean do?")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundColor(.basInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isHeader)

                suggestionPillsRow
                pastTasksSection
            }
            .padding(.bottom, 32)
        }
    }

    private var suggestionPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { text in
                    BASuggestionPill(text: text) {
                        onTaskSuggestionTapped(text)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var pastTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Tasks")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundColor(.basInk.opacity(0.6))
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)

            if pastTasks.isEmpty {
                noTasksEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(pastTasks) { task in
                        BASPastTaskRow(task: task)
                        if task.id != pastTasks.last?.id {
                            Divider()
                                .padding(.leading, 16)
                                .opacity(0.35)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.basTan.opacity(0.7))
                        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - No Tasks Empty State

    private var noTasksEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(Color.basWineRed.opacity(0.45))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Ready to help.")
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundColor(.basInk)

                Text("Ask a question, plan a study, or let Berean prepare something for you.")
                    .font(.subheadline)
                    .foregroundColor(.basInk.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Button(action: onFocusComposer) {
                Text("Ask Berean")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.basWineRed)
                            .shadow(color: Color.basWineRed.opacity(0.30), radius: 8, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Berean — open the composer to start a conversation")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Running State

    private var runningState: some View {
        VStack(alignment: .leading, spacing: 24) {
            currentTaskBar

            // TRANSPARENCY RULE: MUST be visible whenever isRunning=true. Cannot be collapsed or hidden.
            activePluginsSection

            progressIndicatorSection

            Spacer()

            cancelButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .padding(.top, 28)
    }

    private var currentTaskBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .accessibilityHidden(true)

            Text(currentTask.isEmpty ? "Working…" : currentTask)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.basWineRed)
                .shadow(color: Color.basWineRed.opacity(0.35), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal, 20)
        .accessibilityLabel("Current task: \(currentTask.isEmpty ? "Working" : currentTask)")
        .accessibilityAddTraits(.isHeader)
    }

    /// "Berean is using:" strip — ALWAYS visible when isRunning=true per transparency rule.
    private var activePluginsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Berean is using:")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundColor(.basInk)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if activePlugins.isEmpty {
                        Text("No plugins active")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.basInk.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(activePlugins) { plugin in
                            BASActivePluginChip(plugin: plugin)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private var progressIndicatorSection: some View {
        HStack {
            Spacer()
            BASThreeDotsProgress(reduceMotion: reduceMotion)
            Spacer()
        }
        .padding(.horizontal, 20)
        .accessibilityLabel("Berean is working")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.medium))
                    .accessibilityHidden(true)
                Text("Cancel")
                    .font(.body.weight(.medium))
            }
            .foregroundColor(.basInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.basInk.opacity(0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel task")
        .accessibilityHint("Stops the current Berean task")
    }
}

// MARK: - BASuggestionPill

private struct BASuggestionPill: View {
    let text: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(.subheadline, design: .default, weight: .medium))
                .foregroundColor(.basInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.basTan)
                        .shadow(color: Color.basInk.opacity(0.10), radius: 6, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggest: \(text)")
        .accessibilityHint("Double-tap to use this as your task")
    }
}

// MARK: - BASPastTaskRow

private struct BASPastTaskRow: View {
    let task: BASPastTask

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.summary)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundColor(.basInk)
                    .lineLimit(1)
                Text(task.timestamp)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(.basInk.opacity(0.5))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.medium))
                .foregroundColor(.basInk.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityLabel("\(task.summary), \(task.timestamp)")
        .accessibilityHint("Double-tap to rerun this task")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - BASActivePluginChip

private struct BASActivePluginChip: View {
    let plugin: BASPlugin

    private var isPrivateMode: Bool {
        plugin.currentScope == .privateMode
    }

    private var statusLabel: String {
        switch plugin.currentScope {
        case .readOnly, .importantActionsOnly:
            return "Granted"
        case .askEveryTime:
            return "Ask"
        case .never_:
            return "Denied"
        case .privateMode:
            return "Grant needed"
        }
    }

    private var statusColor: Color {
        switch plugin.currentScope {
        case .never_:
            return Color(.systemRed)
        case .privateMode:
            return Color(.systemOrange)
        default:
            return Color(.systemGreen)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if isPrivateMode {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(statusColor)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: plugin.id.iconToken)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.basInk)
                    .accessibilityHidden(true)
            }

            Text(plugin.id.displayName)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundColor(.basInk)

            Text(statusLabel)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.basTan.opacity(0.85))
                .shadow(color: Color.basInk.opacity(0.08), radius: 4, x: 0, y: 1)
        )
        .accessibilityLabel("\(plugin.id.displayName), \(statusLabel)")
    }
}

// MARK: - BASThreeDotsProgress

private struct BASThreeDotsProgress: View {
    let reduceMotion: Bool

    @State private var activeIndex: Int = 0

    private let dotCount = 3
    private let dotSize: CGFloat = 9
    private let bounceHeight: CGFloat = 6
    private let intervalNanos: UInt64 = 280_000_000 // 0.28s

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.basInk.opacity(0.55))
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: (!reduceMotion && activeIndex == index) ? -bounceHeight : 0)
                    .animation(
                        reduceMotion
                            ? .none
                            : Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.55)),
                        value: activeIndex
                    )
            }
        }
        .onAppear { startBounce() }
    }

    private func startBounce() {
        guard !reduceMotion else { return }
        Task {
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                let next = i % dotCount
                await MainActor.run { activeIndex = next }
                i += 1
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Idle State — no past tasks") {
    BereanAgentModeView(
        isRunning: false,
        activePlugins: [],
        currentTask: "",
        pastTasks: [],
        onTaskSuggestionTapped: { _ in },
        onFocusComposer: {},
        onCancel: {}
    )
}

#Preview("Idle State — with past tasks") {
    BereanAgentModeView(
        isRunning: false,
        activePlugins: [],
        currentTask: "",
        pastTasks: [
            BASPastTask(summary: "Explained John 15:5",      timestamp: "2h ago"),
            BASPastTask(summary: "Outlined Romans 8 sermon", timestamp: "Yesterday"),
            BASPastTask(summary: "Created morning prayer",   timestamp: "2 days ago")
        ],
        onTaskSuggestionTapped: { _ in },
        onFocusComposer: {},
        onCancel: {}
    )
}

#Preview("Running State") {
    BereanAgentModeView(
        isRunning: true,
        activePlugins: [
            BASPlugin(id: .context,  currentScope: .readOnly),
            BASPlugin(id: .memory,   currentScope: .importantActionsOnly),
            BASPlugin(id: .notes,    currentScope: .privateMode),
            BASPlugin(id: .church,   currentScope: .askEveryTime)
        ],
        currentTask: "Outline Romans 8 sermon with application points",
        pastTasks: [],
        onTaskSuggestionTapped: { _ in },
        onFocusComposer: {},
        onCancel: {}
    )
}
#endif
