// BereanMemoryView.swift
// AMEN App — Trust Architecture Layer 3: Berean Memory Transparency UI
//
// Gives users full visibility into, and control over, every piece of
// context that Berean has learned about them.
//
// Feature flag: `berean_memory_enabled` (Firebase Remote Config).
// When the flag is absent or false this screen shows a disabled state
// rather than crashing or silently hiding itself.
//
// Accessibility:
//   • Every interactive element carries an accessibilityLabel + accessibilityHint.
//   • Reduce-motion: spring animations replaced with instant transitions when
//     UIAccessibility.isReduceMotionEnabled returns true.
//   • VoiceOver: rows use .accessibilityElement(children: .combine) so the
//     full row context (content + provenance + lock state) is read as one unit.

import SwiftUI
import FirebaseRemoteConfig

// MARK: - BereanMemoryView

struct BereanMemoryView: View {

    // MARK: Dependencies

    /// Authenticated user ID supplied by the caller.
    let userId: String

    // MARK: State

    @StateObject private var manager = BereanMemoryManager()

    /// Feature flag read directly from Remote Config. Defaults to false so
    /// the view fails safely if Remote Config has not been fetched yet.
    @State private var memoryFeatureEnabled: Bool = false

    @State private var entryPendingDelete: BereanMemoryEntry? = nil
    @State private var showDeleteConfirmation = false
    @State private var showDeleteAllSheet = false
    @State private var showInfoSheet = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if !memoryFeatureEnabled {
                    memoryDisabledState
                } else {
                    mainContent
                }
            }
            .navigationTitle("Berean Memory")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
            .sheet(isPresented: $showInfoSheet) { infoSheet }
            .confirmationDialog(
                "Delete this memory?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryPendingDelete {
                        Task { await manager.deleteEntry(entry.id, userId: userId) }
                    }
                    entryPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    entryPendingDelete = nil
                }
            } message: {
                Text("This entry will be permanently removed from Berean's memory.")
            }
            .confirmationDialog(
                "Delete All Memory?",
                isPresented: $showDeleteAllSheet,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    Task { await manager.deleteAll(userId: userId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes everything Berean has learned about you. This cannot be undone.")
            }
        }
        .task {
            fetchFeatureFlag()
            if memoryFeatureEnabled {
                await manager.fetchEntries(userId: userId)
            }
        }
    }

    // MARK: - Feature flag disabled state

    private var memoryDisabledState: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Memory not enabled")
                .font(.title3.bold())

            Text("Berean Memory is not available on your account right now. Check back later or contact support.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Berean Memory is not enabled. It is not available on your account right now.")
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if manager.isLoading && manager.entries.isEmpty {
            loadingSkeletonView
        } else if let err = manager.error {
            errorView(error: err)
        } else if manager.entries.isEmpty {
            emptyStateView
        } else {
            entriesListView
        }
    }

    // MARK: - Entries list

    private var entriesListView: some View {
        List {
            ForEach(manager.presentCategories, id: \.rawValue) { category in
                Section {
                    ForEach(manager.entries(for: category)) { entry in
                        memoryRow(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !entry.isLocked {
                                    Button(role: .destructive) {
                                        entryPendingDelete = entry
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete memory entry: \(entry.content.prefix(40))")
                                }
                            }
                    }
                } header: {
                    categorySectionHeader(category)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { deleteAllFooter }
        .refreshable {
            await manager.fetchEntries(userId: userId)
        }
    }

    // MARK: - Category section header

    private func categorySectionHeader(_ category: BereanMemoryEntry.MemoryCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(categoryColor(category))
                .accessibilityHidden(true)
            Text(category.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName) section, \(manager.entries(for: category).count) entries")
    }

    // MARK: - Memory row

    private func memoryRow(_ entry: BereanMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Category icon
            Image(systemName: entry.category.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(categoryColor(entry.category))
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Provenance line: "Created from: [action]"
                Text("Created from: \(entry.provenance.action)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 10) {
                lockToggleButton(entry)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // Full-row accessibility element so VoiceOver reads everything together
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(entry))
        .accessibilityHint(entry.isLocked
            ? "Locked. Swipe to reveal options. Double tap to unlock."
            : "Unlocked. Swipe left to delete. Double tap to lock."
        )
        .accessibilityAddTraits(.isButton)
    }

    private func rowAccessibilityLabel(_ entry: BereanMemoryEntry) -> String {
        let lock = entry.isLocked ? "Locked." : "Unlocked."
        return "\(entry.category.displayName) memory: \(entry.content). \(lock) Created from: \(entry.provenance.action)."
    }

    // MARK: - Lock toggle button

    private func lockToggleButton(_ entry: BereanMemoryEntry) -> some View {
        Button {
            let entryId = entry.id
            if reduceMotion {
                Task { await manager.toggleLock(entryId, userId: userId) }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    Task { await manager.toggleLock(entryId, userId: userId) }
                }
            }
        } label: {
            Image(systemName: entry.isLocked ? "lock.fill" : "lock.open")
                .font(.body)
                .foregroundStyle(entry.isLocked ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isLocked ? "Unlock this memory entry" : "Lock this memory entry")
        .accessibilityHint(entry.isLocked
            ? "Unlocking allows this entry to be edited or deleted."
            : "Locking prevents accidental edits or deletion."
        )
    }

    // MARK: - Delete all footer

    private var deleteAllFooter: some View {
        Button(role: .destructive) {
            showDeleteAllSheet = true
        } label: {
            Label("Delete All Memories", systemImage: "trash.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Material.regularMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                }
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .disabled(manager.entries.isEmpty || manager.isLoading)
        .accessibilityLabel("Delete all Berean memories")
        .accessibilityHint("Permanently removes everything Berean has learned about you. Requires confirmation.")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About Berean Memory")
            .accessibilityHint("Explains what memory is stored and how to manage it.")
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeletonView: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                skeletonRow
            }
        }
        .listStyle(.insetGrouped)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading Berean memory entries")
    }

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 120, height: 10)
            }
        }
        .padding(.vertical, 6)
        .redacted(reason: .placeholder)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 56))
                .foregroundStyle(.teal.opacity(0.6))
                // Pulse only when motion is allowed; keep static otherwise.
                .symbolEffect(
                    .pulse,
                    options: reduceMotion ? .nonRepeating : .repeating
                )
                .accessibilityHidden(true)

            Text("No memories yet")
                .font(.title3.bold())

            Text("Berean will learn your preferences as you use it. Everything it learns will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No Berean memory saved yet. Berean will learn your preferences as you use it and everything it learns will appear here.")
    }

    // MARK: - Error state

    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Something went wrong")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Retry") {
                Task { await manager.fetchEntries(userId: userId) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry loading Berean memory")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Info sheet

    private var infoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundStyle(.teal)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                        .accessibilityHidden(true)

                    Text("What is Berean Memory?")
                        .font(.title2.bold())

                    Text("Berean saves context from your conversations to personalize responses — for example, your denomination, preferred Bible translation, or topics you study often.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("You own this data.")
                        .font(.body.bold())

                    Text("You can view, lock, or delete any entry at any time. Locking an entry protects it from accidental edits or deletion while still allowing Berean to use it.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("About Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showInfoSheet = false }
                        .accessibilityLabel("Close about memory sheet")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    /// Returns a SwiftUI Color matching the category's semantic accent color name.
    private func categoryColor(_ category: BereanMemoryEntry.MemoryCategory) -> Color {
        switch category.accentColor {
        case "indigo":  return .indigo
        case "purple":  return .purple
        case "green":   return .green
        case "blue":    return .blue
        case "orange":  return .orange
        case "cyan":    return .cyan
        default:        return .teal
        }
    }

    /// Reads `berean_memory_enabled` from Remote Config. Falls back to false.
    private func fetchFeatureFlag() {
        let rc = RemoteConfig.remoteConfig()
        memoryFeatureEnabled = rc["berean_memory_enabled"].boolValue
    }
}

// MARK: - BereanMemorySettingsRow

/// Convenience row for a Settings list that navigates into BereanMemoryView.
struct BereanMemorySettingsRow: View {
    let userId: String
    let entryCount: Int

    var body: some View {
        NavigationLink {
            BereanMemoryView(userId: userId)
        } label: {
            HStack {
                Label {
                    Text("Manage Berean Memory")
                        .font(.body)
                } icon: {
                    Image(systemName: "brain")
                        .foregroundStyle(.teal)
                }

                Spacer()

                if entryCount > 0 {
                    Text("\(entryCount)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.teal.opacity(0.18)))
                        .foregroundStyle(.teal)
                        .accessibilityLabel("\(entryCount) memory \(entryCount == 1 ? "entry" : "entries")")
                }
            }
        }
        .accessibilityLabel("Manage Berean Memory. \(entryCount > 0 ? "\(entryCount) \(entryCount == 1 ? "entry" : "entries") saved." : "No entries yet.")")
        .accessibilityHint("Opens the memory management screen where you can view, lock, and delete entries.")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Memory list") {
    BereanMemoryView(userId: "preview-user")
}

#Preview("Settings row") {
    NavigationStack {
        List {
            BereanMemorySettingsRow(userId: "preview-user", entryCount: 4)
        }
        .navigationTitle("Settings")
    }
}
#endif
