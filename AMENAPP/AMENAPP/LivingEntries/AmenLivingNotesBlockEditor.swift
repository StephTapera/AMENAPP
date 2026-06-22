// AmenLivingNotesBlockEditor.swift
// AMENAPP
// Block-based rich editor for LivingEntry notes.
// Supports text, scripture quote, prayer, task, and reflection blocks.
// Uses the existing LivingEntry / LivingEntryService infrastructure.

import SwiftUI

// MARK: - Block Model

enum LivingNoteBlockType: String, Codable, CaseIterable, Identifiable {
    case paragraph
    case scriptureQuote
    case prayer
    case task
    case reflection
    case separator

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .paragraph:     return "text.alignleft"
        case .scriptureQuote: return "book.fill"
        case .prayer:        return "hands.sparkles"
        case .task:          return "checkmark.circle"
        case .reflection:    return "sparkles"
        case .separator:     return "minus"
        }
    }

    var label: String {
        switch self {
        case .paragraph:     return "Text"
        case .scriptureQuote: return "Scripture"
        case .prayer:        return "Prayer"
        case .task:          return "Task"
        case .reflection:    return "Reflection"
        case .separator:     return "Divider"
        }
    }

    var placeholderText: String {
        switch self {
        case .paragraph:     return "Write something…"
        case .scriptureQuote: return "Verse reference and text"
        case .prayer:        return "Write your prayer…"
        case .task:          return "What needs to happen?"
        case .reflection:    return "What is God saying to you?"
        case .separator:     return ""
        }
    }
}

struct LivingNoteBlock: Identifiable, Equatable {
    var id = UUID()
    var type: LivingNoteBlockType
    var text: String = ""
    var reference: String? = nil     // for scriptureQuote
    var isCompleted: Bool = false    // for task
}

// MARK: - Editor ViewModel

@MainActor
final class LivingNotesBlockEditorViewModel: ObservableObject {
    @Published var blocks: [LivingNoteBlock]
    @Published var isSaving = false
    @Published var focusedBlockId: UUID? = nil

    private let entry: LivingEntry
    private let service = LivingEntryService.shared

    init(entry: LivingEntry) {
        self.entry = entry
        // Deserialise existing body into blocks if it has block markers,
        // otherwise wrap the entire body in one paragraph block.
        if entry.body.contains("⟦BLOCK⟧") {
            self.blocks = Self.deserialise(entry.body)
        } else {
            self.blocks = [
                LivingNoteBlock(type: .paragraph, text: entry.body)
            ]
        }
        if self.blocks.isEmpty {
            self.blocks = [LivingNoteBlock(type: .paragraph)]
        }
    }

    // MARK: Block operations

    func addBlock(_ type: LivingNoteBlockType, after id: UUID? = nil) {
        let new = LivingNoteBlock(type: type)
        if let id, let idx = blocks.firstIndex(where: { $0.id == id }) {
            blocks.insert(new, at: idx + 1)
        } else {
            blocks.append(new)
        }
        focusedBlockId = new.id
    }

    func deleteBlock(_ id: UUID) {
        guard blocks.count > 1 else { return } // always keep at least one
        blocks.removeAll { $0.id == id }
    }

    func moveBlocks(from offsets: IndexSet, to destination: Int) {
        blocks.move(fromOffsets: offsets, toOffset: destination)
    }

    func toggleTask(_ id: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].isCompleted.toggle()
    }

    // MARK: Persistence

    func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = entry
        updated.body = Self.serialise(blocks)
        updated.scriptureRefs = blocks
            .filter { $0.type == .scriptureQuote }
            .compactMap { $0.reference?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        _ = try? await service.updateEntry(updated)
    }

    // MARK: Serialisation (simple text-based)

    static func serialise(_ blocks: [LivingNoteBlock]) -> String {
        blocks.map { block in
            let header = "⟦BLOCK:\(block.type.rawValue)⟧"
            switch block.type {
            case .separator:
                return header
            case .scriptureQuote:
                let ref = block.reference ?? ""
                return "\(header)\(ref)||\(block.text)"
            case .task:
                return "\(header)\(block.isCompleted ? "✓" : "○") \(block.text)"
            default:
                return "\(header)\(block.text)"
            }
        }.joined(separator: "\n")
    }

    static func deserialise(_ raw: String) -> [LivingNoteBlock] {
        raw.components(separatedBy: "\n")
            .filter { $0.hasPrefix("⟦BLOCK:") }
            .compactMap { line -> LivingNoteBlock? in
                guard let closeIdx = line.firstIndex(of: "⟧") else { return nil }
                let typeStr = String(line[line.index(line.startIndex, offsetBy: 7)..<closeIdx])
                guard let type = LivingNoteBlockType(rawValue: typeStr) else { return nil }
                let content = String(line[line.index(after: closeIdx)...])
                var block = LivingNoteBlock(type: type)
                switch type {
                case .separator:
                    break
                case .scriptureQuote:
                    let parts = content.components(separatedBy: "||")
                    block.reference = parts.first
                    block.text = parts.dropFirst().joined(separator: "||")
                case .task:
                    block.isCompleted = content.hasPrefix("✓")
                    block.text = String(content.dropFirst(2)) // remove "✓ " or "○ "
                default:
                    block.text = content
                }
                return block
            }
    }
}

// MARK: - Editor View

struct AmenLivingNotesBlockEditor: View {
    let entry: LivingEntry
    var onSave: (() -> Void)? = nil

    @StateObject private var vm: LivingNotesBlockEditorViewModel
    @State private var showBlockPicker = false
    @State private var insertAfterBlockId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    init(entry: LivingEntry, onSave: (() -> Void)? = nil) {
        self.entry = entry
        self.onSave = onSave
        self._vm = StateObject(wrappedValue: LivingNotesBlockEditorViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach($vm.blocks) { $block in
                        BlockRow(
                            block: $block,
                            isFocused: vm.focusedBlockId == block.id,
                            onDelete: { vm.deleteBlock(block.id) },
                            onAddBelow: {
                                insertAfterBlockId = block.id
                                showBlockPicker = true
                            },
                            onToggleTask: { vm.toggleTask(block.id) },
                            onFocus: { vm.focusedBlockId = block.id }
                        )
                    }

                    // Add block button at bottom
                    Button {
                        insertAfterBlockId = nil
                        showBlockPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add block")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showBlockPicker) {
                BlockPickerSheet { type in
                    vm.addBlock(type, after: insertAfterBlockId)
                    showBlockPicker = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    await vm.save()
                    onSave?()
                    dismiss()
                }
            } label: {
                if vm.isSaving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text("Save").fontWeight(.semibold)
                }
            }
            .disabled(vm.isSaving)
        }

        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
        }
    }
}

// MARK: - Block Row

private struct BlockRow: View {
    @Binding var block: LivingNoteBlock
    var isFocused: Bool
    var onDelete: () -> Void
    var onAddBelow: () -> Void
    var onToggleTask: () -> Void
    var onFocus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Type indicator strip
            blockTypeAccent
                .frame(width: 3)
                .padding(.trailing, 10)
                .padding(.top, 14)

            // Block content
            VStack(alignment: .leading, spacing: 4) {
                blockContent
            }
            .padding(.vertical, 10)
            .padding(.trailing, 16)

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .background(isFocused ? Color.accentColor.opacity(0.04) : Color.clear)
        .contextMenu {
            Button("Add Block Below", systemImage: "plus", action: onAddBelow)
            Divider()
            Button("Delete Block", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .onTapGesture { onFocus() }
    }

    @ViewBuilder
    private var blockTypeAccent: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(accentColor)
    }

    private var accentColor: Color {
        switch block.type {
        case .paragraph:     return Color.clear
        case .scriptureQuote: return .accentColor
        case .prayer:        return .purple
        case .task:          return block.isCompleted ? .green : .orange
        case .reflection:    return .yellow
        case .separator:     return Color.secondary.opacity(0.3)
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.type {

        case .paragraph:
            TextEditor(text: $block.text)
                .font(.body)
                .frame(minHeight: 40)
                .scrollContentBackground(.hidden)
                .background(Color.clear)

        case .scriptureQuote:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Reference (e.g. John 3:16)", text: Binding(
                    get: { block.reference ?? "" },
                    set: { block.reference = $0 }
                ))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)

                TextEditor(text: $block.text)
                    .font(.body.italic())
                    .frame(minHeight: 36)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

        case .prayer:
            VStack(alignment: .leading, spacing: 4) {
                Label("Prayer", systemImage: "hands.sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)

                TextEditor(text: $block.text)
                    .font(.body)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(10)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

        case .task:
            Button(action: onToggleTask) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: block.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(block.isCompleted ? .green : .secondary)
                        .padding(.top, 2)

                    TextField(LivingNoteBlockType.task.placeholderText, text: $block.text, axis: .vertical)
                        .font(.body)
                        .strikethrough(block.isCompleted, color: .secondary)
                        .foregroundStyle(block.isCompleted ? .secondary : .primary)
                }
            }
            .buttonStyle(.plain)

        case .reflection:
            VStack(alignment: .leading, spacing: 4) {
                Label("Reflection", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)

                TextEditor(text: $block.text)
                    .font(.body)
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

        case .separator:
            Divider()
                .padding(.vertical, 6)
        }
    }
}

// MARK: - Block Picker Sheet

private struct BlockPickerSheet: View {
    var onSelect: (LivingNoteBlockType) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(LivingNoteBlockType.allCases.filter { $0 != .separator }) { type in
                    Button {
                        onSelect(type)
                    } label: {
                        Label(type.label, systemImage: type.icon)
                    }
                    .tint(.primary)
                }

                Section {
                    Button {
                        onSelect(.separator)
                    } label: {
                        Label("Divider", systemImage: "minus")
                    }
                    .tint(.secondary)
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
