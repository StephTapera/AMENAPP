// AmenReadingCompanionEngine.swift
// AMENAPP

import SwiftUI
import Combine

// MARK: - Companion State

enum AmenCompanionState {
    case idle
    case expanded
    case highlightMode
    case noteMode
    case prayerMode
    case askingBerean
}

struct AmenTextSelection {
    let text: String
    let bookId: String
    let bookTitle: String
}

// MARK: - ViewModel

@MainActor
final class AmenReadingCompanionViewModel: ObservableObject {

    @Published var state: AmenCompanionState = .idle
    @Published var currentSelection: AmenTextSelection?
    @Published var bereanResponse: String?
    @Published var isLoadingBerean = false
    @Published var noteText: String = ""
    @Published var savedNoteConfirmation: String?

    private let memoryService = AmenLibraryMemoryService.shared

    func expandCompanion() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            state = state == .expanded ? .idle : .expanded
        }
    }

    func selectAction(_ action: AmenCompanionAction, for selection: AmenTextSelection?) {
        currentSelection = selection
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch action {
            case .highlight:    handleHighlight()
            case .note:         state = .noteMode
            case .askBerean:    state = .askingBerean; fetchBereanInsight()
            case .scripture:    state = .highlightMode
            case .prayer:       state = .prayerMode
            case .share:        shareSelection()
            }
        }
    }

    func saveNote() {
        guard let sel = currentSelection, !noteText.isEmpty else { return }
        let note = AmenBookNote(bookId: sel.bookId, bookTitle: sel.bookTitle,
                                highlightText: sel.text, noteBody: noteText, savedAt: Date())
        AmenBookNoteStore.shared.save(note)
        memoryService.recordNote(bookId: sel.bookId)
        noteText = ""
        state = .idle
        savedNoteConfirmation = "Note saved"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            savedNoteConfirmation = nil
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            state = .idle
            bereanResponse = nil
        }
    }

    // MARK: - Private

    private func handleHighlight() {
        guard let sel = currentSelection else { state = .idle; return }
        let highlight = AmenBookNote(bookId: sel.bookId, bookTitle: sel.bookTitle,
                                     highlightText: sel.text, noteBody: nil, savedAt: Date())
        AmenBookNoteStore.shared.save(highlight)
        memoryService.recordNote(bookId: sel.bookId)
        state = .idle
    }

    private func fetchBereanInsight() {
        guard let sel = currentSelection else { return }
        isLoadingBerean = true
        Task {
            let result = try? await BereanAPIClient.shared.studyPassage(reference: sel.text)
            isLoadingBerean = false
            bereanResponse = result?.summary ?? "Berean couldn't find a specific insight for this passage — try a shorter selection."
        }
    }

    private func shareSelection() {
        guard let sel = currentSelection else { return }
        let text = "\"\(sel.text)\"\n— \(sel.bookTitle)"
        // Surfaces a standard share sheet via UIActivityViewController
        AmenShareTrigger.shared.share(text: text)
        state = .idle
    }
}

// MARK: - Actions

enum AmenCompanionAction: String, CaseIterable {
    case highlight  = "Highlight"
    case note       = "Note"
    case askBerean  = "Ask Berean"
    case scripture  = "Scripture"
    case prayer     = "Prayer"
    case share      = "Share"

    var icon: String {
        switch self {
        case .highlight: return "highlighter"
        case .note:      return "note.text"
        case .askBerean: return "brain"
        case .scripture: return "book.closed"
        case .prayer:    return "hands.sparkles"
        case .share:     return "square.and.arrow.up"
        }
    }
}

// MARK: - Floating Companion View

struct AmenReadingCompanionView: View {

    @StateObject private var vm = AmenReadingCompanionViewModel()
    let bookId: String
    let bookTitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if vm.state != .idle {
                Color.black.opacity(0.01)   // hit-test backdrop
                    .ignoresSafeArea()
                    .onTapGesture { vm.dismiss() }
            }

            VStack(alignment: .trailing, spacing: 12) {
                expandedPanel
                orbButton
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
        .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.78), value: vm.state)
        .overlay(noteOverlay)
        .overlay(bereanOverlay)
        .overlay(confirmationToast)
    }

    // MARK: - Orb

    private var orbButton: some View {
        Button(action: vm.expandCompanion) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                Image(systemName: vm.state == .expanded ? "xmark" : "brain")
                    .font(.systemScaled(20, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(vm.state == .expanded ? "Close companion" : "Open Berean companion")
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Expanded Panel

    @ViewBuilder
    private var expandedPanel: some View {
        if vm.state == .expanded {
            VStack(spacing: 0) {
                Text("Reading Companion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)

                Divider().opacity(0.3)

                ForEach(AmenCompanionAction.allCases, id: \.self) { action in
                    companionActionRow(action)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
            .frame(width: 200)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity),
                removal: .scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity)
            ))
        }
    }

    private func companionActionRow(_ action: AmenCompanionAction) -> some View {
        Button {
            vm.selectAction(action, for: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(action.rawValue)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.rawValue)
    }

    // MARK: - Note Overlay

    @ViewBuilder
    private var noteOverlay: some View {
        if vm.state == .noteMode {
            VStack(spacing: 0) {
                Text("Add a Note")
                    .font(.headline)
                    .padding(.top, 20)
                TextEditor(text: $vm.noteText)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                HStack {
                    Button("Cancel") { vm.dismiss() }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { vm.saveNote() }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(20)
            .shadow(radius: 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Berean Overlay

    @ViewBuilder
    private var bereanOverlay: some View {
        if vm.state == .askingBerean {
            VStack(spacing: 12) {
                HStack {
                    Text("Berean Insight")
                        .font(.headline)
                    Spacer()
                    Button(action: vm.dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                if vm.isLoadingBerean {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let response = vm.bereanResponse {
                    Text(response)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(20)
            .shadow(radius: 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var confirmationToast: some View {
        if let msg = vm.savedNoteConfirmation {
            VStack {
                Spacer()
                Text(msg)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 100)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Note Model + Store

struct AmenBookNote: Codable, Identifiable {
    let id: UUID
    let bookId: String
    let bookTitle: String
    let highlightText: String
    let noteBody: String?
    let savedAt: Date

    init(bookId: String, bookTitle: String, highlightText: String, noteBody: String?, savedAt: Date) {
        self.id = UUID()
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.highlightText = highlightText
        self.noteBody = noteBody
        self.savedAt = savedAt
    }
}

final class AmenBookNoteStore {
    static let shared = AmenBookNoteStore()
    private let key = "amen_book_notes_v1"
    private init() {}

    func save(_ note: AmenBookNote) {
        var all = load()
        all.append(note)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [AmenBookNote] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let notes = try? JSONDecoder().decode([AmenBookNote].self, from: data) else { return [] }
        return notes
    }

    func notes(for bookId: String) -> [AmenBookNote] {
        load().filter { $0.bookId == bookId }
    }
}

// MARK: - Share Trigger (bridges to UIKit share sheet)

final class AmenShareTrigger {
    static let shared = AmenShareTrigger()
    private init() {}

    func share(text: String) {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            root.present(vc, animated: true)
        }
    }
}
