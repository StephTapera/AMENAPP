import SwiftUI

// MARK: - Chat Memory Sheet View
/// Full memory management sheet with tabbed navigation.
/// Displays active items, decisions, follow-ups, and date/plan items.

struct ChatMemorySheetView: View {
    @ObservedObject var memoryService: ChatMemoryService
    @ObservedObject var extractionEngine: ChatMemoryExtractionEngine
    @ObservedObject var calendarBridge: ChatCalendarBridge
    @State private var selectedTab: ChatMemoryTab = .active
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                tabPicker

                // Content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Pending suggestions (transient, from extraction engine)
                        if selectedTab == .active && !extractionEngine.pendingSuggestions.isEmpty {
                            suggestionsSection
                        }

                        // Persisted items
                        let items = memoryService.items(for: selectedTab)
                        if items.isEmpty && extractionEngine.pendingSuggestions.isEmpty {
                            emptyState
                        } else {
                            ForEach(items) { item in
                                ChatMemoryItemCard(
                                    item: item,
                                    onResolve: { Task { await memoryService.resolve(item) } },
                                    onCalendar: { calendarBridge.promptCalendarAdd(for: item) },
                                    onDismiss: { Task { await memoryService.dismiss(item) } }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Chat Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(15))
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatMemoryTab.allCases) { tab in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.systemScaled(11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(selectedTab == tab
                            ? Color.primary.opacity(0.90)
                            : Color.primary.opacity(0.50))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab
                                    ? .regularMaterial
                                    : .ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedTab == tab
                                                ? Color.white.opacity(0.45)
                                                : Color.white.opacity(0.15),
                                            lineWidth: 0.5
                                        )
                                )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(Color(hex: "6B48FF"))
                Text("Suggestions")
                    .font(AMENFont.bold(13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            ForEach(extractionEngine.pendingSuggestions) { suggestion in
                ChatMemorySuggestionCard(
                    suggestion: suggestion,
                    onAccept: {
                        Task {
                            let chatId = memoryService.memoryItems.first?.chatId ?? ""
                            if !chatId.isEmpty {
                                await memoryService.saveSuggestion(suggestion, chatId: chatId)
                            }
                            extractionEngine.removeSuggestion(id: suggestion.id)
                        }
                    },
                    onDismiss: {
                        extractionEngine.dismissSuggestion(suggestion)
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedTab.icon)
                .font(.systemScaled(36, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.20))
            Text(emptyMessage)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyMessage: String {
        switch selectedTab {
        case .active:       return "No active items.\nConversation memories will appear here."
        case .decisions:    return "No decisions recorded yet."
        case .followUps:    return "No follow-ups to track."
        case .datesAndPlans: return "No dates or plans detected."
        }
    }
}

// MARK: - Memory Item Card

private struct ChatMemoryItemCard: View {
    let item: ChatMemoryItem
    let onResolve: () -> Void
    let onCalendar: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Category badge
                Image(systemName: item.type.icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(hex: item.type.tintColor))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color(hex: item.type.tintColor).opacity(0.12))
                    )

                Text(item.type.label)
                    .font(AMENFont.bold(12))
                    .foregroundStyle(Color(hex: item.type.tintColor))

                Spacer()

                // Timestamp
                Text(item.createdAt, style: .relative)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.tertiary)
            }

            // Summary
            Text(item.summary)
                .font(AMENFont.regular(14))
                .foregroundStyle(Color.primary.opacity(0.80))
                .lineLimit(3)

            // Due date if present
            if let dueDate = item.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.systemScaled(10, weight: .medium))
                    Text(dueDate, style: .date)
                        .font(AMENFont.semiBold(11))
                }
                .foregroundStyle(Color(hex: "FF3B30").opacity(0.80))
            }

            // Action buttons
            HStack(spacing: 10) {
                actionButton("Resolve", icon: "checkmark", action: onResolve)

                if item.dueDate != nil && item.calendarState != .added {
                    actionButton("Calendar", icon: "calendar.badge.plus", action: onCalendar)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(10, weight: .semibold))
                Text(title)
                    .font(AMENFont.semiBold(11))
            }
            .foregroundStyle(Color.primary.opacity(0.60))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Suggestion Card

private struct ChatMemorySuggestionCard: View {
    let suggestion: ChatMemorySuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.type.icon)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color(hex: suggestion.type.tintColor))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(hex: suggestion.type.tintColor).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.type.label)
                    .font(AMENFont.bold(12))
                    .foregroundStyle(Color(hex: suggestion.type.tintColor))
                Text(suggestion.summary)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer()

            VStack(spacing: 6) {
                Button(action: onAccept) {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(Color(hex: "6B48FF"))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "6B48FF").opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: "6B48FF").opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
