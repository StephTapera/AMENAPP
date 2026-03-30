//
//  StudioJournalView.swift
//  AMENAPP
//
//  Think Tank — private, AI-assisted spiritual journal.
//  Entries are stored locally (encrypted UserDefaults for now).
//  AI reflection prompts are generated via the studioJournalPrompt Cloud Function.
//
//  Privacy: no journal content is ever posted to the feed.
//

import Combine
import SwiftUI
import FirebaseFunctions

// MARK: - Journal Entry Model

struct JournalEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String
    var body: String
    var mood: JournalMood
    var scripture: String
    var aiReflection: String?
}

enum JournalMood: String, CaseIterable, Codable {
    case grateful, hopeful, struggling, peaceful, searching, joyful

    var icon: String {
        switch self {
        case .grateful:   return "heart.fill"
        case .hopeful:    return "sun.horizon.fill"
        case .struggling: return "cloud.drizzle.fill"
        case .peaceful:   return "leaf.fill"
        case .searching:  return "magnifyingglass"
        case .joyful:     return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .grateful:   return .red
        case .hopeful:    return .orange
        case .struggling: return .blue
        case .peaceful:   return .green
        case .searching:  return .purple
        case .joyful:     return .yellow
        }
    }
}

// MARK: - View Model

@MainActor
final class StudioJournalViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    @Published var isLoadingReflection = false

    private let storageKey = "studio_journal_entries_v1"
    private let functions = Functions.functions(region: "us-central1")

    init() { load() }

    func save(entry: JournalEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        persist()
    }

    func delete(entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func requestAIReflection(for entry: JournalEntry) async -> String? {
        isLoadingReflection = true
        defer { isLoadingReflection = false }
        do {
            let payload: [String: Any] = [
                "entry_body": String(entry.body.prefix(1200)), // trim for token limit
                "mood": entry.mood.rawValue,
                "scripture": entry.scripture
            ]
            let result = try await functions
                .httpsCallable("studioJournalPrompt")
                .safeCall(payload)
            if let data = result.data as? [String: Any],
               let text = data["reflection"] as? String {
                return text
            }
        } catch {
            dlog("⚠️ JournalAI error: \(error)")
        }
        return nil
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return }
        entries = decoded
    }
}

// MARK: - Main View

struct StudioJournalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StudioJournalViewModel()
    @State private var showNewEntry = false
    @State private var selectedEntry: JournalEntry?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if vm.entries.isEmpty {
                    emptyState
                } else {
                    entriesList
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.leading, 20)
            }
            .overlay(alignment: .topTrailing) {
                Button { showNewEntry = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 20)
            }
            .sheet(isPresented: $showNewEntry) {
                JournalEntryEditorView(vm: vm, entry: nil)
            }
            .sheet(item: $selectedEntry) { entry in
                JournalEntryEditorView(vm: vm, entry: entry)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.5))
            VStack(spacing: 6) {
                Text("Think Tank")
                    .font(.system(size: 22, weight: .bold))
                Text("Your private space for reflection,\nspiritual wrestling, and growth.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showNewEntry = true } label: {
                Label("Start Your First Entry", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.green))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private var entriesList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Title area
                VStack(alignment: .leading, spacing: 4) {
                    Text("Think Tank")
                        .font(.system(size: 26, weight: .bold))
                    Text("\(vm.entries.count) private \(vm.entries.count == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)

                LazyVStack(spacing: 12) {
                    ForEach(vm.entries) { entry in
                        JournalEntryCard(entry: entry) {
                            selectedEntry = entry
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Entry Card

private struct JournalEntryCard: View {
    let entry: JournalEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: entry.mood.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(entry.mood.color)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(entry.mood.color.opacity(0.1)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.aiReflection != nil {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }

                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !entry.scripture.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 9))
                        Text(entry.scripture)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.green.opacity(0.8))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Entry Editor

struct JournalEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: StudioJournalViewModel

    @State private var title: String
    @State private var entryBody: String
    @State private var mood: JournalMood
    @State private var scripture: String
    @State private var aiReflection: String?
    @State private var showAIReflection = false
    @FocusState private var bodyFocused: Bool

    private let originalEntry: JournalEntry?

    init(vm: StudioJournalViewModel, entry: JournalEntry?) {
        self.vm = vm
        self.originalEntry = entry
        _title = State(initialValue: entry?.title ?? "")
        _entryBody = State(initialValue: entry?.body ?? "")
        _mood = State(initialValue: entry?.mood ?? .grateful)
        _scripture = State(initialValue: entry?.scripture ?? "")
        _aiReflection = State(initialValue: entry?.aiReflection)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Mood row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(JournalMood.allCases, id: \.self) { m in
                                Button { mood = m } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: m.icon)
                                            .font(.system(size: 12))
                                        Text(m.rawValue.capitalized)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(mood == m ? m.color.opacity(0.15) : Color(.secondarySystemBackground))
                                            .overlay(
                                                Capsule().strokeBorder(mood == m ? m.color.opacity(0.4) : Color.clear, lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(mood == m ? m.color : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    VStack(spacing: 12) {
                        TextField("Entry title (optional)", text: $title)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $entryBody)
                                .focused($bodyFocused)
                                .frame(minHeight: 180)
                                .font(.system(size: 15))
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                            if entryBody.isEmpty {
                                Text("What's on your heart…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.top, 19)
                                    .padding(.leading, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                        TextField("Scripture (optional)", text: $scripture)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    }
                    .padding(.horizontal, 20)

                    // AI Reflection
                    if let reflection = aiReflection {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                Text("AI Reflection")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.green)
                                Spacer()
                                Button { aiReflection = nil } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(reflection)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.green.opacity(0.07))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1))
                        )
                        .padding(.horizontal, 20)
                    }

                    // AI Reflect button
                    if aiReflection == nil {
                        Button {
                            Task {
                                let current = JournalEntry(
                                    id: originalEntry?.id ?? UUID(),
                                    date: originalEntry?.date ?? Date(),
                                    title: title, body: entryBody, mood: mood, scripture: scripture
                                )
                                aiReflection = await vm.requestAIReflection(for: current)
                            }
                        } label: {
                            if vm.isLoadingReflection {
                                HStack(spacing: 8) {
                                    ProgressView().progressViewStyle(.circular).tint(.green)
                                    Text("Reflecting…")
                                }
                            } else {
                                Label("Ask AI to Reflect", systemImage: "sparkles")
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 20)
                        .disabled(entryBody.isEmpty || vm.isLoadingReflection)
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.top, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                        .disabled(entryBody.isEmpty)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let entry = JournalEntry(
            id: originalEntry?.id ?? UUID(),
            date: originalEntry?.date ?? Date(),
            title: title,
            body: entryBody,
            mood: mood,
            scripture: scripture,
            aiReflection: aiReflection
        )
        vm.save(entry: entry)
        HapticManager.impact(style: .medium)
        dismiss()
    }
}
