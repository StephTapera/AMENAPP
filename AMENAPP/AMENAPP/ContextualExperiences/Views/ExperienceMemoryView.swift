import SwiftUI

// MARK: - ExperienceMemoryView

/// Grid of ExperienceMemory items for an experience.
/// "Add Memory" button shown to admins only.
struct ExperienceMemoryView: View {

    let experience: ContextualExperience
    let userRole: OrgMemberRole

    @State private var memories: [ExperienceMemory] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedMemory: ExperienceMemory?
    @State private var showAddMemory = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let service = ContextualExperienceService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingSkeleton
                } else if let error {
                    errorState(error)
                } else if memories.isEmpty {
                    emptyState
                } else {
                    memoryGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if userRole.isAdmin {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            HapticManager.impact(style: .light)
                            showAddMemory = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add memory")
                        .accessibilityHint("Opens the add memory form")
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedMemory) { memory in
            memoryDetailSheet(memory)
        }
        .sheet(isPresented: $showAddMemory) {
            AddMemorySheet(experience: experience) {
                Task { await load() }
            }
        }
    }

    // MARK: - Memory grid

    private var memoryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(memories) { memory in
                    memoryCellButton(memory)
                }
            }
            .padding(16)
        }
    }

    private func memoryCellButton(_ memory: ExperienceMemory) -> some View {
        Button {
            HapticManager.impact(style: .light)
            selectedMemory = memory
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                imageThumbnail(memory)
                Text(memory.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .padding(10)
            .background(cellBackground)
            .overlay(cellStroke)
            .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(memory.title), \(memory.createdAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Tap to view memory details")
    }

    @ViewBuilder
    private func imageThumbnail(_ memory: ExperienceMemory) -> some View {
        if let urlString = memory.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipped()
                default:
                    imagePlaceholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AmenTheme.Colors.surfaceChip)
            .frame(height: 100)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .font(.system(size: 24))
            )
    }

    // MARK: - Memory detail sheet

    @ViewBuilder
    private func memoryDetailSheet(_ memory: ExperienceMemory) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let urlString = memory.imageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(memory.title)
                            .font(AMENFont.bold(20))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)

                        Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(AMENFont.regular(12))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)

                        if let scripture = memory.scriptureReference {
                            HStack(spacing: 6) {
                                Image(systemName: "book.closed.fill")
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                    .imageScale(.small)
                                Text(scripture)
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                        }

                        Text(memory.note)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        HapticManager.impact(style: .light)
                        selectedMemory = nil
                    }
                    .accessibilityLabel("Close memory detail")
                }
            }
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
            }
        }
        .padding(16)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.fill")
                .font(.system(size: 40))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("No Memories Yet")
                .font(AMENFont.bold(16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Be the first to add a memory to this experience.")
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if userRole.isAdmin {
                Button {
                    HapticManager.impact(style: .light)
                    showAddMemory = true
                } label: {
                    Text("Add Memory")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a memory")
            }
        }
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.statusError)
            Text(message)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                HapticManager.impact(style: .light)
                Task { await load() }
            } label: {
                Text("Retry")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading memories")
        }
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var cellBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.3))
            }
        }
    }

    private var cellStroke: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil
        do {
            memories = try await service.fetchMemories(experienceId: experience.id ?? "")
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - AddMemorySheet

private struct AddMemorySheet: View {
    let experience: ContextualExperience
    let onSaved: () -> Void

    @State private var title = ""
    @State private var note = ""
    @State private var scripture = ""
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private let service = ContextualExperienceService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("Title", text: $title)
                        .accessibilityLabel("Memory title")
                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Memory notes")
                    TextField("Scripture Reference (optional)", text: $scripture)
                        .accessibilityLabel("Scripture reference")
                }

                if let error {
                    Section {
                        Text(error)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(AmenTheme.Colors.statusError)
                    }
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Add Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticManager.impact(style: .light)
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityLabel("Save memory")
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            _ = try await service.addMemory(
                to: experience.id ?? "",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURL: nil,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                scripture: scripture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : scripture.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
