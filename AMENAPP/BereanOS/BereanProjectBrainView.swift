// BereanProjectBrainView.swift
// AMENAPP — BereanOS
// Project-scoped memory brain browser with extract-from-text sheet.

import SwiftUI

// MARK: - BereanProjectMemoryEntryType display helpers

private extension BereanProjectMemoryEntryType {
    var displayName: String {
        switch self {
        case .insight: return "Insight"
        case .fact: return "Fact"
        case .question: return "Question"
        case .decision: return "Decision"
        case .reference: return "Reference"
        case .note: return "Note"
        }
    }

    var systemIcon: String {
        switch self {
        case .insight: return "lightbulb"
        case .fact: return "checkmark.circle"
        case .question: return "questionmark.circle"
        case .decision: return "checkmark.diamond"
        case .reference: return "link"
        case .note: return "note.text"
        }
    }

    var accentColor: Color {
        switch self {
        case .insight: return .yellow
        case .fact: return .green
        case .question: return .blue
        case .decision: return .purple
        case .reference: return .orange
        case .note: return .secondary
        }
    }
}

// MARK: - BereanProjectBrainView

struct BereanProjectBrainView: View {
    let projectId: String

    @StateObject private var service = BereanProjectMemoryService.shared
    @State private var selectedType: BereanProjectMemoryEntryType? = nil
    @State private var showingExtractSheet = false
    @State private var extractText = ""
    @State private var isExtracting = false

    // MARK: Computed

    private var displayedEntries: [BereanProjectMemoryEntry] {
        guard let selectedType else { return service.entries }
        return service.entriesByType(selectedType)
    }

    // MARK: Body

    var body: some View {
        Group {
            if !AMENFeatureFlags.shared.bereanOSMemoryBrainEnabled {
                ContentUnavailableView(
                    "Memory Brain Unavailable",
                    systemImage: "brain",
                    description: Text("This feature is not yet enabled. Check back soon.")
                )
            } else {
                mainContent
            }
        }
        .navigationTitle("Project Brain")
        .navigationBarTitleDisplayMode(.large)
        .task(id: projectId) {
            try? await service.fetchEntries(projectId: projectId)
        }
        .sheet(isPresented: $showingExtractSheet) {
            extractSheet
        }
    }

    // MARK: Main content

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                typeFilterChips
                    .padding(.vertical, 8)
                Divider()

                if service.entries.isEmpty {
                    emptyStateView
                } else if displayedEntries.isEmpty, let type = selectedType {
                    typeEmptyState(for: type)
                } else {
                    entriesList
                }
            }

            extractButton
                .padding(.bottom, 20)
        }
        .overlay {
            if let error = service.lastError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.red, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 80)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(), value: service.lastError)
            }
        }
    }

    // MARK: Type filter chip row

    private var typeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                chipButton(label: "All",
                           icon: "square.grid.2x2.fill",
                           isSelected: selectedType == nil) {
                    selectedType = nil
                }

                ForEach(BereanProjectMemoryEntryType.allCases, id: \.self) { type in
                    chipButton(label: type.displayName,
                               icon: type.systemIcon,
                               isSelected: selectedType == type) {
                        selectedType = (selectedType == type) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func chipButton(label: String,
                            icon: String,
                            isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.systemScaled(13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color(.systemGray5),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Entries list

    private var entriesList: some View {
        List {
            ForEach(displayedEntries) { entry in
                entryRow(entry)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button("Resolve") {
                            Task {
                                try? await service.resolveEntry(id: entry.id, projectId: projectId)
                            }
                        }
                        .tint(.green)
                    }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Entry row

    @ViewBuilder
    private func entryRow(_ entry: BereanProjectMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Type indicator dot
            Circle()
                .fill(entry.entryType.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                // Content body — 3 lines
                Text(entry.content)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    // Type icon
                    Image(systemName: entry.entryType.systemIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(entry.entryType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Relative timestamp
                    Text(entry.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.entryType.displayName): \(entry.content).")
    }

    // MARK: Empty states

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Memory Entries",
            systemImage: "brain",
            description: Text("Paste text below to extract structured knowledge.")
        )
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func typeEmptyState(for type: BereanProjectMemoryEntryType) -> some View {
        ContentUnavailableView(
            "No \(type.displayName) Entries",
            systemImage: type.systemIcon,
            description: Text("Nothing here yet. Try extracting from text.")
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: Extract FAB

    private var extractButton: some View {
        Button {
            showingExtractSheet = true
        } label: {
            Label("Extract from text", systemImage: "text.badge.plus")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Extract knowledge from text")
    }

    // MARK: Extract sheet

    private var extractSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste notes, research, or any text you want the Memory Brain to analyze.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $extractText)
                    .font(.body)
                    .padding(10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
                    .accessibilityLabel("Text to extract knowledge from")

                HStack {
                    Text("\(extractText.count)/10000")
                        .font(.caption)
                        .foregroundStyle(extractText.count > 10000 ? .red : .secondary)
                        .padding(.leading)
                    Spacer()
                }
            }
            .navigationTitle("Extract Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingExtractSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isExtracting = true
                            do {
                                try await service.extractMemory(from: extractText, projectId: projectId)
                                extractText = ""
                                showingExtractSheet = false
                            } catch {
                                // lastError is published by the service
                            }
                            isExtracting = false
                        }
                    } label: {
                        if isExtracting || service.isExtracting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Extract")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(extractText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || extractText.count > 10000
                              || isExtracting
                              || service.isExtracting)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BereanProjectBrainView(projectId: "preview-project-id")
    }
}
