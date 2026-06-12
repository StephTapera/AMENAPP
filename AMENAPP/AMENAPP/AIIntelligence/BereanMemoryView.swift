import SwiftUI
import FirebaseFunctions

// MARK: - BereanMemoryEntry
//
// Codable model for a single persisted memory entry. The backend stores these
// under users/{uid}/bereanMemory/{id} and surfaces them via the
// "bereanGetMemory" callable.

struct BereanMemoryEntry: Codable, Identifiable {
    let id: String
    let category: String   // preference | study | prayer | church | action | context
    let content: String
    let isLocked: Bool
    let provenance: String // "Created during conversation on [date]"
    let updatedAt: Date

    // MARK: Derived display properties

    /// SF Symbol name for the entry category.
    var categoryIcon: String {
        switch category {
        case "preference": return "slider.horizontal.3"
        case "study":      return "books.vertical"
        case "prayer":     return "hands.sparkles"
        case "church":     return "building.2"
        case "action":     return "checkmark.circle"
        default:           return "brain"   // "context" + unknown
        }
    }

    /// Accent color per category — used in icon rendering.
    var categoryColor: Color {
        switch category {
        case "preference": return .blue
        case "study":      return .indigo
        case "prayer":     return .purple
        case "church":     return .green
        case "action":     return .orange
        default:           return .teal    // "context"
        }
    }

    /// Title shown in the section header.
    var categoryTitle: String {
        switch category {
        case "preference": return "Preferences"
        case "study":      return "Study"
        case "prayer":     return "Prayer"
        case "church":     return "Church"
        case "action":     return "Actions"
        default:           return "Context"
        }
    }
}

// MARK: - Codable helpers (Date decoded as timeIntervalSince1970 Double)

extension BereanMemoryEntry {
    enum CodingKeys: String, CodingKey {
        case id, category, content, isLocked, provenance, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self, forKey: .id)
        category   = try c.decode(String.self, forKey: .category)
        content    = try c.decode(String.self, forKey: .content)
        isLocked   = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        provenance = try c.decodeIfPresent(String.self, forKey: .provenance) ?? "Context saved by Berean"
        let ts     = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        updatedAt  = Date(timeIntervalSince1970: ts)
    }
}

// MARK: - BereanMemoryService

@MainActor
final class BereanMemoryService: ObservableObject {
    @Published var entries: [BereanMemoryEntry] = []
    @Published var isLoading = false
    @Published var error: String? = nil

    private let functions = Functions.functions()

    // MARK: Load

    func loadMemory(userId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("bereanGetMemory")
            let result = try await callable.call(["userId": userId])
            guard let raw = result.data as? [[String: Any]] else {
                entries = []
                return
            }
            let data = try JSONSerialization.data(withJSONObject: raw)
            entries = try JSONDecoder().decode([BereanMemoryEntry].self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Delete single entry

    func deleteEntry(_ entry: BereanMemoryEntry, userId: String) async {
        guard !entry.isLocked else { return }
        do {
            let callable = functions.httpsCallable("bereanDeleteMemory")
            _ = try await callable.call(["userId": userId, "entryId": entry.id])
            entries.removeAll { $0.id == entry.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Toggle lock

    func toggleLock(_ entry: BereanMemoryEntry, userId: String) async {
        do {
            let callable = functions.httpsCallable("bereanToggleMemoryLock")
            let result = try await callable.call(["userId": userId, "entryId": entry.id])
            // Backend returns updated entry; re-fetch on success
            if let _ = result.data as? [String: Any] {
                await loadMemory(userId: userId)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Edit entry content

    func editEntry(_ entry: BereanMemoryEntry, newContent: String, userId: String) async {
        guard !entry.isLocked else { return }
        guard !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let callable = functions.httpsCallable("bereanUpdateMemory")
            _ = try await callable.call([
                "userId": userId,
                "entryId": entry.id,
                "content": newContent.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            await loadMemory(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Delete all memory

    func deleteAllMemory(userId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let callable = functions.httpsCallable("bereanDeleteAllMemory")
            _ = try await callable.call(["userId": userId])
            entries = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Derived

    /// Ordered list of category keys present in entries, for section grouping.
    var presentCategories: [String] {
        let order = ["preference", "study", "prayer", "church", "action", "context"]
        let found = Set(entries.map(\.category))
        return order.filter { found.contains($0) }
    }

    func entries(for category: String) -> [BereanMemoryEntry] {
        entries.filter { $0.category == category }
    }
}

// MARK: - BereanMemoryView

struct BereanMemoryView: View {
    @StateObject private var service = BereanMemoryService()

    /// Caller must supply the authenticated user ID.
    let userId: String

    @State private var editingEntry: BereanMemoryEntry? = nil
    @State private var editText: String = ""
    @State private var showDeleteAllConfirm = false
    @State private var showInfoSheet = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Berean Memory")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showInfoSheet) { infoSheet }
                .sheet(item: $editingEntry) { entry in editSheet(for: entry) }
                .alert("Delete All Memory?", isPresented: $showDeleteAllConfirm) {
                    deleteAllAlert
                } message: {
                    Text("This permanently removes everything Berean has learned about you. This cannot be undone.")
                }
                .task { await service.loadMemory(userId: userId) }
        }
    }

    // MARK: Main content

    @ViewBuilder
    private var content: some View {
        if service.isLoading {
            loadingView
        } else if let err = service.error {
            errorView(message: err)
        } else if service.entries.isEmpty {
            emptyStateView
        } else {
            entriesList
        }
    }

    // MARK: Entries list

    private var entriesList: some View {
        List {
            ForEach(service.presentCategories, id: \.self) { category in
                Section(header: categorySectionHeader(category)) {
                    ForEach(service.entries(for: category)) { entry in
                        memoryRow(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: !entry.isLocked) {
                                if !entry.isLocked {
                                    Button(role: .destructive) {
                                        Task { await service.deleteEntry(entry, userId: userId) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete memory entry")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { deleteAllButton }
    }

    // MARK: Section header

    private func categorySectionHeader(_ category: String) -> some View {
        let sample = service.entries(for: category).first
        return HStack(spacing: 6) {
            Image(systemName: sample?.categoryIcon ?? "brain")
                .foregroundStyle(sample?.categoryColor ?? .teal)
                .font(.caption.weight(.semibold))
            Text(sample?.categoryTitle ?? category.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sample?.categoryTitle ?? category) section")
    }

    // MARK: Memory row

    private func memoryRow(_ entry: BereanMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Category icon
            Image(systemName: entry.categoryIcon)
                .foregroundStyle(entry.categoryColor)
                .font(.body.weight(.medium))
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(entry.provenance)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 12) {
                lockButton(entry)
                if !entry.isLocked {
                    deleteButton(entry)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !entry.isLocked else { return }
            editText = entry.content
            editingEntry = entry
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(entry))
        .accessibilityHint(entry.isLocked ? "Locked. Unlock to edit or delete." : "Double tap to edit.")
        .padding(.vertical, 2)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Material.regularMaterial)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
    }

    private func rowAccessibilityLabel(_ entry: BereanMemoryEntry) -> String {
        let lockStatus = entry.isLocked ? "Locked." : "Unlocked."
        return "\(entry.categoryTitle) memory: \(entry.content). \(lockStatus) \(entry.provenance)."
    }

    // MARK: Lock button

    private func lockButton(_ entry: BereanMemoryEntry) -> some View {
        Button {
            Task { await service.toggleLock(entry, userId: userId) }
        } label: {
            Image(systemName: entry.isLocked ? "lock.fill" : "lock.open")
                .font(.body)
                .foregroundStyle(entry.isLocked ? .orange : .secondary)
                .symbolEffect(.bounce, value: entry.isLocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isLocked ? "Unlock memory entry" : "Lock memory entry")
        .accessibilityHint(entry.isLocked ? "Unlocking allows editing and deletion." : "Locking prevents editing and deletion.")
    }

    // MARK: Delete button

    private func deleteButton(_ entry: BereanMemoryEntry) -> some View {
        Button(role: .destructive) {
            Task { await service.deleteEntry(entry, userId: userId) }
        } label: {
            Image(systemName: "trash")
                .font(.body)
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete memory entry")
        .accessibilityHint("Permanently removes this entry.")
    }

    // MARK: Delete all button (bottom toolbar)

    private var deleteAllButton: some View {
        Button(role: .destructive) {
            showDeleteAllConfirm = true
        } label: {
            Label("Delete All Memory", systemImage: "trash.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Material.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                )
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityLabel("Delete all Berean memory")
        .accessibilityHint("Permanently removes everything Berean has learned. Requires confirmation.")
        .disabled(service.entries.isEmpty || service.isLoading)
    }

    // MARK: Delete all alert buttons

    @ViewBuilder
    private var deleteAllAlert: some View {
        Button("Delete All", role: .destructive) {
            Task { await service.deleteAllMemory(userId: userId) }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About Berean Memory")
            .accessibilityHint("Explains what memory is and how it is used.")
        }
    }

    // MARK: Info sheet

    private var infoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "brain")
                    .font(.system(size: 48))
                    .foregroundStyle(.teal)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)

                Text("What is Berean Memory?")
                    .font(.title2.bold())

                Text("Berean saves context from your conversations to personalize responses. For example, it may remember your denomination, preferred Bible translation, or topics you study frequently.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("You own this data.")
                    .font(.body.bold())

                Text("You can view, edit, lock, or delete any entry at any time. Locking an entry prevents accidental edits or deletion while still allowing Berean to use it.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 24)
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

    // MARK: Edit sheet

    private func editSheet(for entry: BereanMemoryEntry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit Memory")
                    .font(.title3.bold())
                    .padding(.top, 8)

                Text(entry.provenance)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                TextEditor(text: $editText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Material.regularMaterial)
                    )
                    .accessibilityLabel("Edit memory content")

                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        editingEntry = nil
                    }
                    .accessibilityLabel("Cancel edit")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let current = editingEntry
                        editingEntry = nil
                        Task {
                            if let e = current {
                                await service.editEntry(e, newContent: editText, userId: userId)
                            }
                        }
                    }
                    .font(.body.bold())
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Save memory edit")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading memory…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading Berean memory")
    }

    // MARK: Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await service.loadMemory(userId: userId) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry loading memory")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Empty state

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 56))
                .foregroundStyle(.teal.opacity(0.6))
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)

            Text("No memory saved yet")
                .font(.title3.bold())

            Text("Berean will learn your preferences as you use it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No Berean memory saved yet. Berean will learn your preferences as you use it.")
    }
}

// MARK: - BereanMemorySettingsRow

/// Drop-in row for use inside a Settings screen.
/// Shows "Manage Berean Memory" with a count badge and navigates to BereanMemoryView.
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
                        .background(
                            Capsule()
                                .fill(Color.teal.opacity(0.18))
                        )
                        .foregroundStyle(.teal)
                        .accessibilityLabel("\(entryCount) memory entries")
                }
            }
        }
        .accessibilityLabel("Manage Berean Memory. \(entryCount > 0 ? "\(entryCount) entries saved." : "No entries yet.")")
        .accessibilityHint("Opens memory management screen where you can view, edit, lock, and delete entries.")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Memory List") {
    BereanMemoryView(userId: "preview-user")
}

#Preview("Settings Row") {
    NavigationStack {
        List {
            BereanMemorySettingsRow(userId: "preview-user", entryCount: 7)
        }
        .navigationTitle("Settings")
    }
}
#endif
