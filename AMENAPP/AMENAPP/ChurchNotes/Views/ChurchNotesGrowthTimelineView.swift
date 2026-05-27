import SwiftUI

// Spiritual Growth Timeline — private view of recurring themes, answered prayers,
// scripture journey, and sermon continuity across Church Notes history.
// Private by default; never exposed in group or public contexts.
struct ChurchNotesGrowthTimelineView: View {

    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let userId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.growthTimelineState {
                case .loading:
                    CNLoadingView(label: "Loading your growth timeline\u{2026}")
                case .error(let message):
                    CNErrorView(message: message) {
                        viewModel.loadGrowthTimeline(userId: userId)
                    }
                case .empty, .idle:
                    emptyState
                case .loaded:
                    timelineList
                }
            }
            .navigationTitle("Spiritual Journey")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    privateIndicator
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss growth timeline")
                }
            }
        }
        .task {
            viewModel.loadGrowthTimeline(userId: userId)
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.growthEntries) { entry in
                    GrowthEntryRow(entry: entry)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        CNEmptyStateView(
            icon: "leaf.fill",
            title: "Your journey starts here",
            message: "As you save Church Notes, your spiritual growth patterns will appear here \u{2014} privately, just for you."
        )
    }

    // MARK: - Private Indicator

    private var privateIndicator: some View {
        Label("Private", systemImage: "lock.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("This timeline is private \u{2014} only visible to you")
    }
}

// MARK: - Growth Entry Row

private struct GrowthEntryRow: View {
    let entry: CNGrowthEntry
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Timeline connector
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(entryColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 8) {
                    entryCard
                }
                .padding(.bottom, 16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.type.displayLabel): \(entry.title). \(entry.summary)")
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(entry.type.displayLabel, systemImage: entry.type.sfSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entryColor)
                Spacer()
                if let date = entry.date {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(entry.title)
                .font(.subheadline.weight(.medium))

            if isExpanded {
                Text(entry.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))

                if !entry.relatedNoteIds.isEmpty {
                    Text("\(entry.relatedNoteIds.count) related \(entry.relatedNoteIds.count == 1 ? "note" : "notes")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                CNProvenanceRow(label: entry.provenance)
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(isExpanded ? "Collapse entry details" : "Expand entry details")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var entryColor: Color {
        switch entry.type {
        case .recurringTheme:       return .purple
        case .answeredPrayer:       return .green
        case .repeatedVerse:        return .blue
        case .sermonContinuity:     return .indigo
        case .reflectionCompleted:  return .pink
        case .actionFollowedThrough: return .teal
        }
    }
}

// MARK: - Growth Timeline Button

struct ChurchNotesGrowthTimelineButton: View {
    @ObservedObject var viewModel: ChurchNotesContextViewModel
    let userId: String
    private let flags = AMENFeatureFlags.shared

    var body: some View {
        if flags.churchNotesGrowthTimelineEnabled {
            Button {
                viewModel.isGrowthTimelinePresented = true
            } label: {
                Label("Your Journey", systemImage: "leaf.fill")
            }
            .sheet(isPresented: $viewModel.isGrowthTimelinePresented) {
                ChurchNotesGrowthTimelineView(viewModel: viewModel, userId: userId)
                    .presentationDetents([.large])
            }
        }
    }
}
