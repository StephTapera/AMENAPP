import SwiftUI

// MARK: - Selah Memory View
// Displays the user's semantic memory graph — saved moments, scripture,
// and meaning connections. Lets users search by theme and journal further.

struct SelahMemoryView: View {
    @ObservedObject var service: SelahMediaService
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var selectedCategory: SelahMeaningCategory?
    @State private var selectedMemory: SelahMediaMemory?
    @State private var showComposer = false

    private var filteredMemories: [SelahMediaMemory] {
        var result = service.memories
        if let cat = selectedCategory {
            result = result.filter { $0.meaningTags.contains { $0.category == cat.rawValue } }
        }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(lower)
                || $0.bodyText.lowercased().contains(lower)
                || $0.linkedScriptureRefs.contains { $0.lowercased().contains(lower) }
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow
                categoryFilter
                if filteredMemories.isEmpty {
                    emptyState
                } else {
                    memoriesGrid
                }
            }
            .padding(.bottom, 40)
        }
        .searchable(text: $searchText, prompt: "Search memories…")
        .sheet(item: $selectedMemory) { memory in
            SelahMemoryDetailSheet(memory: memory, service: service)
        }
        .sheet(isPresented: $showComposer) {
            SelahMemoryComposerSheet(service: service)
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Memory")
                    .font(.largeTitle.weight(.bold))
                Text("\(service.memories.count) saved moments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showComposer = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(26))
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Add memory")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(SelahMeaningCategory.allCases) { cat in
                    categoryChip(cat, label: "\(cat.emoji) \(cat.rawValue)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryChip(_ cat: SelahMeaningCategory?, label: String) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedCategory = isSelected ? nil : cat
            }
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.purple : Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private var memoriesGrid: some View {
        LazyVStack(spacing: 14) {
            ForEach(filteredMemories) { memory in
                SelahMemoryCard(memory: memory)
                    .onTapGesture { selectedMemory = memory }
                    .padding(.horizontal, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "brain")
                .font(.systemScaled(48, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(service.memories.isEmpty
                 ? "No memories yet"
                 : "No matches for this filter")
                .font(.headline)
                .foregroundStyle(.secondary)
            if service.memories.isEmpty {
                Text("Save moments from media or Pause mode to build your memory graph.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 40)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Memory Card

struct SelahMemoryCard: View {
    let memory: SelahMediaMemory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.title.isEmpty ? "Untitled memory" : memory.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(memory.intentEnum.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.tertiarySystemBackground)))
            }

            if !memory.bodyText.isEmpty {
                Text(memory.bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !memory.linkedScriptureRefs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(memory.linkedScriptureRefs.prefix(3), id: \.self) { ref in
                        Label(ref, systemImage: "book.fill")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .lineLimit(1)
                    }
                }
            }

            if !memory.meaningTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(memory.meaningTags) { tag in
                            Text("\(tag.categoryEnum.emoji) \(tag.label)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.purple.opacity(0.10))
                                )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.06),
                        radius: 8, y: 2)
        )
    }
}

// MARK: - Memory Detail Sheet

struct SelahMemoryDetailSheet: View {
    let memory: SelahMediaMemory
    let service: SelahMediaService
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !memory.bodyText.isEmpty {
                        Text(memory.bodyText)
                            .font(.body)
                            .padding(.horizontal, 20)
                    }

                    if !memory.linkedScriptureRefs.isEmpty {
                        scripturePill
                    }

                    if !memory.meaningTags.isEmpty {
                        meaningTagSection
                    }

                    if let aiSummary = memory.aiSummary, !aiSummary.isEmpty {
                        aiSummaryCard(aiSummary)
                    }

                    linkedMediaSection

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .navigationTitle(memory.title.isEmpty ? "Memory" : memory.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog("Delete this memory?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await service.deleteMemory(id: memory.id ?? "")
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var scripturePill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(memory.linkedScriptureRefs, id: \.self) { ref in
                    Label(ref, systemImage: "book.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.purple.opacity(0.10)))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var meaningTagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Themes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(memory.meaningTags) { tag in
                        SelahMeaningTagBadge(tag: tag)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func aiSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Berean Insight", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.purple.opacity(0.07))
        )
        .padding(.horizontal, 20)
    }

    private var linkedMediaSection: some View {
        Group {
            if !memory.linkedMediaIds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linked Moments")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    Text("\(memory.linkedMediaIds.count) media item(s) linked")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - Memory Composer Sheet

struct SelahMemoryComposerSheet: View {
    let service: SelahMediaService
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var scriptureRef = ""
    @State private var selectedCategories: Set<SelahMeaningCategory> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Name this memory", text: $title)
                }
                Section("Reflection") {
                    TextField("Write what this means to you…", text: $bodyText, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section("Scripture") {
                    TextField("e.g. Psalm 23:1", text: $scriptureRef)
                }
                Section("Themes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(SelahMeaningCategory.allCases) { cat in
                            Toggle(isOn: Binding(
                                get: { selectedCategories.contains(cat) },
                                set: { if $0 { selectedCategories.insert(cat) } else { selectedCategories.remove(cat) } }
                            )) {
                                Label("\(cat.emoji) \(cat.rawValue)", systemImage: "")
                                    .font(.caption)
                            }
                            .toggleStyle(.button)
                        }
                    }
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let tags = selectedCategories.map {
            SelahMeaningTag(category: $0, label: $0.rawValue)
        }
        let refs = scriptureRef.trimmingCharacters(in: .whitespaces).isEmpty
            ? [] : [scriptureRef]
        let memory = SelahMediaMemory(
            title: title,
            bodyText: bodyText,
            linkedScriptureRefs: refs,
            meaningTags: tags
        )
        Task {
            _ = try? await service.saveMemory(memory)
            isSaving = false
            dismiss()
        }
    }
}
