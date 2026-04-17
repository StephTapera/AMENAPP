// ChurchNoteSemanticEditorView.swift
// AMENAPP
//
// Full semantic block editor for ChurchNoteV2.
// Design: glass capsule toolbar, block list, floating quick-action bar.
// Each block is rendered inline; tapping a block activates an editing sheet.

import SwiftUI
import FirebaseAuth

// MARK: - Editor ViewModel

@MainActor
final class ChurchNoteSemanticEditorViewModel: ObservableObject {
    @Published var note: ChurchNoteV2
    @Published var blocks: [ChurchNoteBlockV2] = []
    @Published var isSaving = false
    @Published var error: String?
    @Published var showBlockFactory = false
    @Published var editingBlock: ChurchNoteBlockV2?
    @Published var showSelah = false

    private let repository = ChurchNoteBlockRepository.shared
    private var autosaveTask: Task<Void, Never>?

    init(note: ChurchNoteV2? = nil) {
        if let note {
            self.note = note
        } else {
            let uid = Auth.auth().currentUser?.uid ?? ""
            self.note = ChurchNoteV2.empty(userId: uid)
        }
    }

    func startEditing() {
        Task {
            // Ensure the note doc exists before listening for blocks
            if blocks.isEmpty && note.blockCount == 0 {
                try? await repository.createNote(note)
                // Seed with one empty paragraph
                let seed = ChurchNoteBlockV2.paragraph(text: "", order: 0)
                try? await repository.addBlock(seed, to: note.id)
            }
            repository.startListeningToBlocks(noteId: note.id)
        }
    }

    func stopEditing() {
        repository.stopListeningToBlocks()
        autosaveTask?.cancel()
    }

    func addBlock(_ block: ChurchNoteBlockV2) {
        var b = block
        b = ChurchNoteBlockV2(
            id: b.id,
            sortOrder: (blocks.last?.sortOrder ?? -1) + 1,
            type: b.type,
            semanticType: b.semanticType,
            visibility: b.visibility,
            pinnedState: b.pinnedState,
            text: b.text,
            richSpans: b.richSpans,
            versePayload: b.versePayload,
            calloutPayload: b.calloutPayload,
            sectionPayload: b.sectionPayload,
            checklistPayload: b.checklistPayload,
            createdAt: b.createdAt,
            updatedAt: b.updatedAt
        )
        Task {
            try? await repository.addBlock(b, to: note.id)
        }
    }

    func updateBlock(_ block: ChurchNoteBlockV2) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s debounce
            guard !Task.isCancelled else { return }
            try? await repository.updateBlock(block, in: note.id)
        }
    }

    func deleteBlock(_ block: ChurchNoteBlockV2) {
        Task {
            try? await repository.deleteBlock(blockId: block.id, from: note.id)
        }
    }

    func toggleVisibility(for block: ChurchNoteBlockV2) {
        let next: ChurchNoteVisibility = block.visibility == .privateOnly ? .shareable : .privateOnly
        Task {
            try? await repository.updateBlockVisibility(
                blockId: block.id,
                noteId: note.id,
                visibility: next
            )
        }
    }

    func togglePin(_ state: ChurchNotePinnedState, for block: ChurchNoteBlockV2) {
        let next: ChurchNotePinnedState = block.pinnedState == state ? .none : state
        Task {
            try? await repository.updateBlockPinnedState(
                blockId: block.id,
                noteId: note.id,
                pinnedState: next
            )
        }
    }

    var pinnedBlocks: [ChurchNoteBlockV2] {
        blocks.filter { $0.pinnedState != .none }
    }
}

// MARK: - Main Editor View

struct ChurchNoteSemanticEditorView: View {

    @StateObject private var vm: ChurchNoteSemanticEditorViewModel
    @EnvironmentObject private var blockRepo: ChurchNoteBlockRepository
    @Environment(\.dismiss) private var dismiss

    init(note: ChurchNoteV2? = nil) {
        _vm = StateObject(wrappedValue: ChurchNoteSemanticEditorViewModel(note: note))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        noteHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        if !vm.pinnedBlocks.isEmpty {
                            pinnedStrip
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        LazyVStack(spacing: 4) {
                            ForEach(blockRepo.activeBlocks) { block in
                                SemanticBlockCellView(
                                    block: block,
                                    onEdit: { vm.editingBlock = block },
                                    onDelete: { vm.deleteBlock(block) },
                                    onToggleVisibility: { vm.toggleVisibility(for: block) },
                                    onPin: { vm.togglePin(.anchorInsight, for: block) }
                                )
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 140)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    vm.startEditing()
                }
                .onDisappear {
                    vm.stopEditing()
                }

                floatingToolbar
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showSelah = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Open Selah view")
                }
            }
            .sheet(isPresented: $vm.showBlockFactory) {
                BlockFactorySheet { block in
                    vm.addBlock(block)
                    vm.showBlockFactory = false
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $vm.editingBlock) { block in
                BlockEditSheet(block: block) { updated in
                    vm.updateBlock(updated)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $vm.showSelah) {
                ChurchNoteSelahRenderView(noteId: vm.note.id)
            }
        }
    }

    // MARK: - Note Header

    private var noteHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Sermon title", text: Binding(
                get: { vm.note.sermonTitle ?? "" },
                set: { vm.note.sermonTitle = $0.isEmpty ? nil : $0 }
            ))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)

            TextField("Speaker (optional)", text: Binding(
                get: { vm.note.sermonSpeaker ?? "" },
                set: { vm.note.sermonSpeaker = $0.isEmpty ? nil : $0 }
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Pinned Strip

    private var pinnedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pinned")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.pinnedBlocks) { block in
                        pinnedChip(block)
                    }
                }
            }
        }
    }

    private func pinnedChip(_ block: ChurchNoteBlockV2) -> some View {
        HStack(spacing: 6) {
            Image(systemName: block.pinnedState.icon)
                .font(.caption2)
                .foregroundStyle(block.semanticType.accentColor)
            Text(block.text.isEmpty ? block.type.displayName : String(block.text.prefix(30)))
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    vm.showBlockFactory = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Block")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary)
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Add a new block")

                Spacer()

                // Quick semantic presets
                ForEach([ChurchNoteCalloutStyle.prayer, .action, .reflection], id: \.self) { style in
                    Button {
                        vm.addBlock(ChurchNoteBlockV2.callout(style: style, order: (blockRepo.activeBlocks.last?.sortOrder ?? -1) + 1))
                    } label: {
                        Image(systemName: style.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(style.fillColor.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Add \(style.displayName) callout")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Semantic Block Cell

struct SemanticBlockCellView: View {

    let block: ChurchNoteBlockV2
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleVisibility: () -> Void
    let onPin: () -> Void

    @State private var showMenu = false

    var body: some View {
        Button(action: onEdit) {
            blockContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button {
                onToggleVisibility()
            } label: {
                Label(
                    block.visibility == .privateOnly ? "Mark Shareable" : "Make Private",
                    systemImage: block.visibility == .privateOnly ? "square.and.arrow.up" : "lock"
                )
            }
            Button {
                onPin()
            } label: {
                Label(
                    block.pinnedState == .none ? "Pin as Anchor" : "Unpin",
                    systemImage: block.pinnedState == .none ? "pin.fill" : "pin.slash"
                )
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Block", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.type.displayName): \(block.text.prefix(60))")
        .accessibilityHint("Double tap to edit. Long press for options.")
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {
        case .paragraph, .heading, .subheading, .annotation:
            paragraphCell

        case .quote, .takeaway, .prayer, .action, .scripture:
            semanticPillCell

        case .callout:
            calloutCell

        case .verseEmbed:
            verseCell

        case .checklist:
            checklistCell

        case .divider:
            Divider().padding(.vertical, 4)

        case .section:
            sectionCell

        case .bulletList, .numberedList:
            listCell
        }
    }

    private var paragraphCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            if block.type == .heading {
                Text(block.text.isEmpty ? "Heading" : block.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            } else if block.type == .subheading {
                Text(block.text.isEmpty ? "Subheading" : block.text)
                    .font(.headline)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            } else {
                Text(block.text.isEmpty ? "Type something..." : block.text)
                    .font(.body)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .overlay(alignment: .leading) {
            if block.semanticType != .general {
                Rectangle()
                    .fill(block.semanticType.accentColor.opacity(0.5))
                    .frame(width: 2)
                    .clipShape(Capsule())
            }
        }
    }

    private var semanticPillCell: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(block.semanticType.accentColor)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(block.semanticType.accentColor)

                Text(block.text.isEmpty ? "Type here..." : block.text)
                    .font(.subheadline)
                    .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            visibilityBadge
        }
        .padding(12)
        .background(
            block.semanticType.accentColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(block.semanticType.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var calloutCell: some View {
        let style = block.calloutPayload?.style ?? .reflection
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.system(size: 15))
                .foregroundStyle(style.borderColor)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(style.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.borderColor)

                if let prompt = block.calloutPayload?.prompt, !prompt.isEmpty, block.text.isEmpty {
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text(block.text.isEmpty ? "Tap to write..." : block.text)
                        .font(.subheadline)
                        .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
                }
            }
            Spacer()
            visibilityBadge
        }
        .padding(14)
        .background(style.fillColor, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var verseCell: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "book.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "8AA8D8"))
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let payload = block.versePayload {
                    Text(payload.reference)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: "8AA8D8"))

                    Text(payload.verseText.isEmpty ? "Verse text loading..." : payload.verseText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .italic()

                    Text(payload.translation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add verse reference")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            visibilityBadge
        }
        .padding(12)
        .background(Color(hex: "DCE7F7").opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: "B9CBE7").opacity(0.6), lineWidth: 1)
        )
    }

    private var checklistCell: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let payload = block.checklistPayload {
                HStack {
                    Image(systemName: payload.category.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(payload.category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                ForEach(payload.items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.completed ? .primary : Color(.tertiaryLabel))
                            .font(.system(size: 16))
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(.subheadline)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? .secondary : .primary)
                    }
                }

                if payload.items.isEmpty {
                    Text("Tap to add items")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sectionCell: some View {
        HStack {
            Image(systemName: block.sectionPayload?.isCollapsed == true
                  ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(block.sectionPayload?.heading ?? "Section")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private var listCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.text.isEmpty ? "List item..." : block.text)
                .font(.body)
                .foregroundStyle(block.text.isEmpty ? .tertiary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var visibilityBadge: some View {
        if block.visibility != .privateOnly {
            Image(systemName: "square.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Shareable block")
        }
        if block.pinnedState != .none {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Pinned block")
        }
    }
}

// MARK: - Block Factory Sheet

struct BlockFactorySheet: View {

    let onSelect: (ChurchNoteBlockV2) -> Void

    private let insertableTypes = ChurchNoteBlockV2Type.insertableTypes
    private let calloutStyles = ChurchNoteCalloutStyle.allCases
    private let checklistCategories = ChurchNoteChecklistCategory.allCases

    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Blocks").tag(0)
                    Text("Callouts").tag(1)
                    Text("Checklists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(16)

                ScrollView {
                    if tab == 0 {
                        blockTypeGrid
                    } else if tab == 1 {
                        calloutGrid
                    } else {
                        checklistGrid
                    }
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var blockTypeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
            ForEach(insertableTypes.filter { ![.callout, .checklist, .verseEmbed].contains($0) }) { type in
                blockTypeButton(type)
            }
            // Verse embed gets its own cell
            Button {
                onSelect(ChurchNoteBlockV2.verseEmbed(reference: "", text: ""))
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: ChurchNoteBlockV2Type.verseEmbed.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "8AA8D8"))
                    Text(ChurchNoteBlockV2Type.verseEmbed.displayName)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "DCE7F7").opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add verse embed block")
        }
        .padding(16)
    }

    private func blockTypeButton(_ type: ChurchNoteBlockV2Type) -> some View {
        Button {
            onSelect(ChurchNoteBlockV2(type: type))
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                Text(type.displayName)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(type.displayName) block")
    }

    private var calloutGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
            ForEach(calloutStyles) { style in
                Button {
                    onSelect(ChurchNoteBlockV2.callout(style: style))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(style.borderColor)
                        Text(style.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(style.fillColor, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style.borderColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(style.displayName) callout")
            }
        }
        .padding(16)
    }

    private var checklistGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
            ForEach(checklistCategories) { category in
                Button {
                    onSelect(ChurchNoteBlockV2.checklist(category: category))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        Text(category.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(category.displayName) checklist")
            }
        }
        .padding(16)
    }
}

// MARK: - Block Edit Sheet

struct BlockEditSheet: View {
    @State private var block: ChurchNoteBlockV2
    let onSave: (ChurchNoteBlockV2) -> Void
    @Environment(\.dismiss) private var dismiss

    init(block: ChurchNoteBlockV2, onSave: @escaping (ChurchNoteBlockV2) -> Void) {
        _block = State(initialValue: block)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Text editor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Content")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        TextEditor(text: $block.text)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Semantic type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meaning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ChurchNoteSemanticType.allCases) { type in
                                    semanticChip(type)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    // Visibility picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Visibility")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            ForEach(ChurchNoteVisibility.allCases, id: \.self) { v in
                                visibilityChip(v)
                            }
                        }
                    }

                    // Pin picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ChurchNotePinnedState.allCases, id: \.self) { state in
                                    pinChip(state)
                                }
                            }
                        }
                    }

                    // Checklist items (if applicable)
                    if block.type == .checklist {
                        checklistEditor
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(block.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(block)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func semanticChip(_ type: ChurchNoteSemanticType) -> some View {
        let selected = block.semanticType == type
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: type, visibility: block.visibility, pinnedState: block.pinnedState,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.caption2)
                Text(type.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? type.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? type.accentColor : Color.primary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? type.accentColor.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func visibilityChip(_ visibility: ChurchNoteVisibility) -> some View {
        let selected = block.visibility == visibility
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: block.semanticType, visibility: visibility, pinnedState: block.pinnedState,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: visibility.icon).font(.caption2)
                Text(visibility.displayName).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.primary : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visibility.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func pinChip(_ state: ChurchNotePinnedState) -> some View {
        let selected = block.pinnedState == state
        return Button {
            block = ChurchNoteBlockV2(
                id: block.id, sortOrder: block.sortOrder, type: block.type,
                semanticType: block.semanticType, visibility: block.visibility, pinnedState: state,
                text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
                calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
                checklistPayload: block.checklistPayload,
                createdAt: block.createdAt, updatedAt: Date()
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.icon).font(.caption2)
                Text(state.displayName).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color(.secondarySystemGroupedBackground) : Color(.tertiarySystemFill))
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.primary.opacity(0.3) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var checklistEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let items = block.checklistPayload?.items ?? []
            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: 8) {
                    Image(systemName: items[idx].completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(items[idx].completed ? .primary : Color(.tertiaryLabel))
                        .onTapGesture {
                            toggleChecklistItem(at: idx)
                        }
                        .accessibilityHidden(true)
                    Text(items[idx].text)
                        .font(.subheadline)
                }
            }

            Button {
                addChecklistItem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.subheadline)
                    Text("Add Item").font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleChecklistItem(at index: Int) {
        guard var payload = block.checklistPayload else { return }
        payload.items[index].completed.toggle()
        block = ChurchNoteBlockV2(
            id: block.id, sortOrder: block.sortOrder, type: block.type,
            semanticType: block.semanticType, visibility: block.visibility, pinnedState: block.pinnedState,
            text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
            calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
            checklistPayload: payload, createdAt: block.createdAt, updatedAt: Date()
        )
    }

    private func addChecklistItem() {
        var payload = block.checklistPayload ?? ChecklistPayload(
            category: .actionSteps,
            items: []
        )
        payload.items.append(CNChecklistItem(text: ""))
        block = ChurchNoteBlockV2(
            id: block.id, sortOrder: block.sortOrder, type: block.type,
            semanticType: block.semanticType, visibility: block.visibility, pinnedState: block.pinnedState,
            text: block.text, richSpans: block.richSpans, versePayload: block.versePayload,
            calloutPayload: block.calloutPayload, sectionPayload: block.sectionPayload,
            checklistPayload: payload, createdAt: block.createdAt, updatedAt: Date()
        )
    }
}


