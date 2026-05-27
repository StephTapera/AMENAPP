//
//  SelahReflectionListView.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  Gated list of the current user's reflection entries.
//  The list is hidden behind App Lock (Face ID / passcode). Relational signals
//  (group prayer count) are displayed in place of vanity like counts.
//

import SwiftUI

// MARK: - List ViewModel

@MainActor
final class SelahReflectionListViewModel: ObservableObject {

    @Published var reflections: [SelahReflectionDocument] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let service = SelahFirestoreReflectionService.shared

    func load() async {
        isLoading = true
        error = nil
        do {
            reflections = try await service.fetchMyReflections()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ reflection: SelahReflectionDocument) async {
        do {
            try await service.deleteReflection(id: reflection.id)
            reflections.removeAll { $0.id == reflection.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - List View

struct SelahReflectionListView: View {

    @StateObject private var viewModel = SelahReflectionListViewModel()
    @State private var isUnlocked: Bool = false
    @State private var showComposer: Bool = false
    @State private var composerViewModel = SelahReflectionViewModel()

    var body: some View {
        Group {
            if isUnlocked {
                unlockedContent
            } else {
                SelahAppLockGateView(onUnlocked: { isUnlocked = true })
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isUnlocked)
    }

    // MARK: Unlocked Content

    private var unlockedContent: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading reflections…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    errorView(message: error)
                } else if viewModel.reflections.isEmpty {
                    emptyStateView
                } else {
                    reflectionList
                }
            }
            .navigationTitle("My Reflections")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composerViewModel.reset()
                        showComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Reflection")
                    .accessibilityIdentifier("reflectionList.newButton")
                }
            }
            .sheet(isPresented: $showComposer, onDismiss: {
                Task { await viewModel.load() }
            }) {
                SelahReflectionComposerView(
                    viewModel: composerViewModel,
                    verseReference: composerViewModel.verseId ?? "Scripture"
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task {
                await viewModel.load()
            }
        }
    }

    // MARK: Reflection List

    private var reflectionList: some View {
        List {
            ForEach(viewModel.reflections) { reflection in
                ReflectionRowView(reflection: reflection)
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let reflection = viewModel.reflections[index]
                    Task { await viewModel.delete(reflection) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No reflections yet")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Tap the pencil icon to write your first reflection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Could not load reflections")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reflection Row

private struct ReflectionRowView: View {

    let reflection: SelahReflectionDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // MARK: Header row
            HStack(alignment: .center, spacing: 8) {
                if let verseId = reflection.verseId {
                    Text(verseId)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(reflection.shareScope.badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Share scope: \(reflection.shareScope.accessibilityLabel)")

                Text(reflection.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // MARK: Body preview
            let preview = reflection.body.count > 80
                ? String(reflection.body.prefix(80)) + "…"
                : reflection.body

            Text(preview)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // MARK: Relational signals
            if reflection.relationalSignals.prayedByGroupCount > 0 {
                Label(
                    "Prayed by \(reflection.relationalSignals.prayedByGroupCount) in your group",
                    systemImage: "hands.sparkles"
                )
                .font(.caption)
                .foregroundStyle(.teal)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // The delete action is driven by List's onDelete handler above;
            // this label provides the swipe affordance with an explicit identifier.
            Button(role: .destructive) {
                // Handled by onDelete in parent list.
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("reflectionList.deleteButton")
        }
    }
}

// MARK: - Share scope badge helpers

private extension SelahReflectionShareScope {
    var badge: String {
        switch self {
        case .justMe:                return "Lock  Just Me"
        case .accountabilityPartner: return "Group  Partner"
        case .namedGroup:            return "House  Group"
        }
    }
    var accessibilityLabel: String {
        switch self {
        case .justMe:                return "Private"
        case .accountabilityPartner: return "Shared with accountability partner"
        case .namedGroup:            return "Shared with group"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SelahReflectionListView()
}
#endif
