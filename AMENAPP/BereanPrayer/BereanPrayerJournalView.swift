// BereanPrayerJournalView.swift
// AMENAPP — Berean Prayer Intelligence OS — Journal + Add Entry

import SwiftUI
import FirebaseFirestore

// MARK: - Journal View

struct BereanPrayerJournalView: View {
    @StateObject private var service = BereanPrayerService.shared
    @State private var selectedStatus: BereanPrayerEntryStatus? = nil   // nil = All
    @State private var searchText = ""
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    emptyStateView
                } else {
                    journalList
                }
            }
            .navigationTitle("Prayer Journal")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemBackground).ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search prayers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add prayer request")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPrayerEntrySheet(service: service)
            }
        }
    }

    // MARK: - Journal list

    private var journalList: some View {
        List {
            // Status filter pills
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill(label: "All", status: nil)
                        ForEach(BereanPrayerEntryStatus.allCases, id: \.rawValue) { status in
                            filterPill(label: status.displayName, status: status)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityLabel("Filter prayer requests")
            }

            // Grouped by category
            ForEach(groupedCategories, id: \.rawValue) { category in
                let categoryEntries = entries(forCategory: category)
                if !categoryEntries.isEmpty {
                    Section(header: categoryHeader(category)) {
                        ForEach(categoryEntries) { entry in
                            journalRow(entry: entry)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: selectedStatus)
    }

    // MARK: - Filter pill

    private func filterPill(label: String, status: BereanPrayerEntryStatus?) -> some View {
        let isSelected = selectedStatus == status
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStatus = status
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color(.secondarySystemFill)
                )
                .clipShape(Capsule())
        }
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Category header

    private func categoryHeader(_ category: BereanPrayerCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.systemImage)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .accessibilityHidden(true)
            Text(category.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    // MARK: - Journal row

    private func journalRow(entry: BereanPrayerEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.subject)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                statusBadge(entry.status)
            }

            if !entry.forWhom.isEmpty {
                Text("For \(entry.forWhom)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.status == .answered, let answeredAt = entry.answeredAt {
                Text("Answered \(answeredRelativeText(answeredAt))")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel(entry))
    }

    private func statusBadge(_ status: BereanPrayerEntryStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private func statusColor(_ status: BereanPrayerEntryStatus) -> Color {
        switch status {
        case .active:   return .green
        case .answered: return Color.accentColor
        case .archived: return .gray
        }
    }

    private func answeredRelativeText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    private func accessibilityRowLabel(_ entry: BereanPrayerEntry) -> String {
        var label = "\(entry.subject), for \(entry.forWhom), \(entry.status.displayName)"
        if entry.status == .answered, let answeredAt = entry.answeredAt {
            label += ", answered \(answeredRelativeText(answeredAt))"
        }
        return label
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hands.clap")
                .font(.systemScaled(44))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .accessibilityHidden(true)

            Text(emptyStateMessage)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if selectedStatus == nil && searchText.isEmpty {
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                        Text("Add Prayer Request")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Add prayer request")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No results for \"\(searchText)\""
        }
        guard let status = selectedStatus else {
            return "No prayer requests yet"
        }
        return "No \(status.displayName.lowercased()) prayer requests"
    }

    // MARK: - Filtered + grouped data

    private var filteredEntries: [BereanPrayerEntry] {
        service.entries
            .filter { entry in
                let matchesStatus = selectedStatus == nil || entry.status == selectedStatus
                let matchesSearch = searchText.isEmpty
                    || entry.subject.localizedCaseInsensitiveContains(searchText)
                    || entry.forWhom.localizedCaseInsensitiveContains(searchText)
                return matchesStatus && matchesSearch
            }
    }

    private var groupedCategories: [BereanPrayerCategory] {
        let usedCategories = Set(filteredEntries.map(\.category))
        return BereanPrayerCategory.allCases.filter { usedCategories.contains($0) }
    }

    private func entries(forCategory category: BereanPrayerCategory) -> [BereanPrayerEntry] {
        filteredEntries.filter { $0.category == category }
    }
}

// MARK: - Add Entry Sheet

struct AddPrayerEntrySheet: View {
    let service: BereanPrayerService
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var forWhom = ""
    @State private var bodyText = ""
    @State private var category: BereanPrayerCategory = .faith
    @State private var sensitivity: PrayerEntrySensitivity = .normal
    @State private var isPrivate = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Validation
    private var isValid: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !forWhom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section {
                    TextField("Prayer subject", text: $subject)
                        .accessibilityLabel("Prayer subject")

                    TextField("For whom", text: $forWhom)
                        .accessibilityLabel("Who to pray for")

                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("Additional notes (optional)")
                                .foregroundStyle(Color(.placeholderText))
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 80)
                            .accessibilityLabel("Prayer notes")
                    }
                } header: {
                    Text("Prayer Details")
                }

                // Category
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(BereanPrayerCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }
                    .accessibilityLabel("Prayer category")
                } header: {
                    Text("Category")
                }

                // Sensitivity
                Section {
                    Picker("Sensitivity", selection: $sensitivity) {
                        Text("Normal").tag(PrayerEntrySensitivity.normal)
                        Text("Tender").tag(PrayerEntrySensitivity.tender)
                        Text("Crisis").tag(PrayerEntrySensitivity.crisis)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Prayer sensitivity level")

                    if sensitivity == .crisis {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text("Crisis prayers receive special care and privacy protections.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Crisis prayers receive special care and privacy protections")
                    }
                } header: {
                    Text("Sensitivity")
                }

                // Privacy
                Section {
                    Toggle("Keep Private", isOn: $isPrivate)
                        .accessibilityLabel("Keep this prayer request private")
                        .accessibilityHint("Private prayers are only visible to you")

                    Text("Prayer requests are private by default and never shared without your permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }

                // Error
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Prayer Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSubmitting {
                        ProgressView()
                            .accessibilityLabel("Saving prayer request")
                    } else {
                        Button("Save") { submitEntry() }
                            .fontWeight(.semibold)
                            .disabled(!isValid)
                            .accessibilityLabel("Save prayer request")
                            .accessibilityHint(isValid ? "" : "Subject and for whom fields are required")
                    }
                }
            }
        }
    }

    // MARK: - Submit

    private func submitEntry() {
        guard isValid else {
            errorMessage = "Please fill in the subject and who this prayer is for."
            return
        }

        isSubmitting = true
        errorMessage = nil

        let entry = BereanPrayerEntry(
            id:          UUID().uuidString,
            subject:     subject.trimmingCharacters(in: .whitespacesAndNewlines),
            forWhom:     forWhom.trimmingCharacters(in: .whitespacesAndNewlines),
            body:        bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            status:      .active,
            category:    category,
            createdAt:   Date(),
            isPrivate:   isPrivate,
            sensitivity: sensitivity
        )

        Task {
            do {
                try await service.addEntry(entry)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BereanPrayerJournalView_Previews: PreviewProvider {
    static var previews: some View {
        BereanPrayerJournalView()
    }
}

struct AddPrayerEntrySheet_Previews: PreviewProvider {
    static var previews: some View {
        AddPrayerEntrySheet(service: BereanPrayerService.shared)
    }
}
#endif
