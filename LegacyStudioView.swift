//
//  LegacyStudioView.swift
//  AMENAPP
//
//  AMEN Legacy Studio — preserve life stories for generations.
//
//  Features:
//   • AI-guided life interview (question-by-question)
//   • Memory timeline  (chronological life moments)
//   • Time capsule letters (sealed until a chosen date)
//   • Oral history (record audio, transcribe via Cloud Function)
//   • Story-to-Book export (PDF compilation — coming soon)
//   • Memorial Space (tribute posts for loved ones)
//

import Combine
import SwiftUI

// MARK: - Legacy Models

enum LegacyEntryType: String, CaseIterable, Codable {
    case interview    = "Interview"
    case memory       = "Memory"
    case timeCapsule  = "Time Capsule"
    case memorial     = "Memorial"

    var icon: String {
        switch self {
        case .interview:   return "mic.circle.fill"
        case .memory:      return "clock.arrow.circlepath"
        case .timeCapsule: return "lock.rectangle.stack.fill"
        case .memorial:    return "flame.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .interview:   return .orange
        case .memory:      return .blue
        case .timeCapsule: return .purple
        case .memorial:    return .pink
        }
    }

    var description: String {
        switch self {
        case .interview:   return "AI-guided life story interview"
        case .memory:      return "A moment you want to preserve"
        case .timeCapsule: return "A letter sealed until a future date"
        case .memorial:    return "A tribute for someone you love"
        }
    }
}

struct LegacyEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var type: LegacyEntryType
    var title: String
    var body: String
    var date: Date = Date()
    var eventYear: Int?        // for memory timeline
    var sealUntil: Date?       // for time capsule
    var isSealed: Bool = false
}

// MARK: - View Model

@MainActor
final class LegacyStudioViewModel: ObservableObject {
    @Published var entries: [LegacyEntry] = []
    @Published var interviewMessages: [InterviewMessage] = []
    @Published var isGeneratingQuestion = false

    private let storageKey = "legacy_studio_entries_v1"
    private let interviewKey = "legacy_interview_v1"

    struct InterviewMessage: Identifiable, Codable {
        var id: UUID = UUID()
        var isAI: Bool
        var text: String
        var date: Date = Date()
    }

    private let interviewQuestions: [String] = [
        "Where were you born, and what's your earliest memory of that place?",
        "Who was the most influential person in your childhood, and why?",
        "What's a moment that changed the direction of your life?",
        "How did your faith journey begin? Was there a turning point?",
        "What's a lesson you learned the hard way that you'd want to pass on?",
        "Describe a time you felt closest to God.",
        "What do you want the people who come after you to know about you?",
        "What has love — in all its forms — taught you?",
        "If you could go back and give your younger self one piece of advice, what would it be?",
        "What is your legacy? What do you hope people will say about your life?"
    ]

    init() {
        load()
        if interviewMessages.isEmpty {
            interviewMessages.append(InterviewMessage(
                isAI: true,
                text: "Welcome to your Life Interview. I'm here to help you capture your story, one question at a time. Ready to begin?\n\n\(interviewQuestions[0])"
            ))
        }
    }

    func answerInterview(answer: String) {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        interviewMessages.append(InterviewMessage(isAI: false, text: answer))
        let aiCount = interviewMessages.filter { $0.isAI }.count
        if aiCount < interviewQuestions.count {
            let next = interviewQuestions[aiCount]
            interviewMessages.append(InterviewMessage(isAI: true, text: next))
        } else {
            interviewMessages.append(InterviewMessage(
                isAI: true,
                text: "Thank you for sharing your story. Your answers have been saved. You can review and edit them anytime."
            ))
        }
        persistInterview()
    }

    func save(entry: LegacyEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        persist()
    }

    func delete(entry: LegacyEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    var timeline: [LegacyEntry] {
        entries.filter { $0.type == .memory }.sorted { ($0.eventYear ?? 0) < ($1.eventYear ?? 0) }
    }

    var capsules: [LegacyEntry] {
        entries.filter { $0.type == .timeCapsule }
    }

    var memorials: [LegacyEntry] {
        entries.filter { $0.type == .memorial }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persistInterview() {
        if let data = try? JSONEncoder().encode(interviewMessages) {
            UserDefaults.standard.set(data, forKey: interviewKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([LegacyEntry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: interviewKey),
           let decoded = try? JSONDecoder().decode([InterviewMessage].self, from: data) {
            interviewMessages = decoded
        }
    }
}

// MARK: - Main View

struct LegacyStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LegacyStudioViewModel()

    enum LegacyTab: String, CaseIterable {
        case interview = "Interview"
        case timeline  = "Timeline"
        case capsules  = "Capsules"
        case memorial  = "Memorial"

        var icon: String {
            switch self {
            case .interview: return "mic.circle.fill"
            case .timeline:  return "clock.arrow.circlepath"
            case .capsules:  return "lock.rectangle.stack.fill"
            case .memorial:  return "flame.fill"
            }
        }
    }

    @State private var selectedTab: LegacyTab = .interview
    @State private var showNewMemory = false
    @State private var showNewCapsule = false
    @State private var showNewMemorial = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    tabPicker
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    Divider()

                    switch selectedTab {
                    case .interview: InterviewTab(vm: vm)
                    case .timeline:  TimelineTab(vm: vm, showNew: $showNewMemory)
                    case .capsules:  CapsulesTab(vm: vm, showNew: $showNewCapsule)
                    case .memorial:  MemorialTab(vm: vm, showNew: $showNewMemorial)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewMemory) {
                LegacyEntryEditorView(vm: vm, type: .memory, existing: nil)
            }
            .sheet(isPresented: $showNewCapsule) {
                LegacyEntryEditorView(vm: vm, type: .timeCapsule, existing: nil)
            }
            .sheet(isPresented: $showNewMemorial) {
                LegacyEntryEditorView(vm: vm, type: .memorial, existing: nil)
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Legacy Studio")
                    .font(.system(size: 16, weight: .bold))
                Text("Your story. For generations.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance
            Color.clear.frame(width: 33, height: 33)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(LegacyTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedTab == tab ? Color.orange.opacity(0.12) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Interview Tab

private struct InterviewTab: View {
    @ObservedObject var vm: LegacyStudioViewModel
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.interviewMessages) { msg in
                            InterviewBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: vm.interviewMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(vm.interviewMessages.last?.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Your answer…", text: $input, axis: .vertical)
                    .focused($inputFocused)
                    .lineLimit(4)
                    .font(.system(size: 14))
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                Button {
                    let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !answer.isEmpty else { return }
                    vm.answerInterview(answer: answer)
                    input = ""
                    inputFocused = false
                    HapticManager.impact(style: .light)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.tertiaryLabel) : .orange)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}

private struct InterviewBubble: View {
    let message: LegacyStudioViewModel.InterviewMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isAI {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    )
            } else {
                Spacer(minLength: 60)
            }

            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(message.isAI ? Color.primary : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.isAI ? Color(.secondarySystemBackground) : Color.orange)
                )
                .frame(maxWidth: .infinity, alignment: message.isAI ? .leading : .trailing)

            if !message.isAI {
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Timeline Tab

private struct TimelineTab: View {
    @ObservedObject var vm: LegacyStudioViewModel
    @Binding var showNew: Bool
    @State private var selectedEntry: LegacyEntry?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if vm.timeline.isEmpty {
                LegacyEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "Memory Timeline",
                    subtitle: "Add moments from your life to build a visual history.",
                    buttonLabel: "Add a Memory",
                    color: .blue
                ) { showNew = true }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(vm.timeline.enumerated()), id: \.element.id) { idx, entry in
                            TimelineRow(entry: entry, isLast: idx == vm.timeline.count - 1) {
                                selectedEntry = entry
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
            }

            if !vm.timeline.isEmpty {
                Button { showNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.blue))
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(24)
            }
        }
        .sheet(item: $selectedEntry) { e in
            LegacyEntryEditorView(vm: vm, type: .memory, existing: e)
        }
    }
}

private struct TimelineRow: View {
    let entry: LegacyEntry
    let isLast: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    if let year = entry.eventYear {
                        Text(String(year))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    Text(entry.title.isEmpty ? "Untitled Memory" : entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !entry.body.isEmpty {
                        Text(entry.body)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Capsules Tab

private struct CapsulesTab: View {
    @ObservedObject var vm: LegacyStudioViewModel
    @Binding var showNew: Bool
    @State private var selectedEntry: LegacyEntry?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if vm.capsules.isEmpty {
                LegacyEmptyState(
                    icon: "lock.rectangle.stack.fill",
                    title: "Time Capsules",
                    subtitle: "Write a letter to your future self or loved ones. Sealed until a date you choose.",
                    buttonLabel: "Write a Capsule",
                    color: .purple
                ) { showNew = true }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.capsules) { entry in
                            CapsuleCard(entry: entry) { selectedEntry = entry }
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
            }

            if !vm.capsules.isEmpty {
                Button { showNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.purple))
                        .shadow(color: Color.purple.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(24)
            }
        }
        .sheet(item: $selectedEntry) { e in
            LegacyEntryEditorView(vm: vm, type: .timeCapsule, existing: e)
        }
    }
}

private struct CapsuleCard: View {
    let entry: LegacyEntry
    let onTap: () -> Void

    private var isSealed: Bool {
        guard let seal = entry.sealUntil else { return false }
        return Date() < seal
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: isSealed ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title.isEmpty ? "Untitled Capsule" : entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let seal = entry.sealUntil {
                        Text(isSealed ? "Sealed until \(seal.formatted(date: .abbreviated, time: .omitted))"
                             : "Opened \(seal.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(isSealed ? .purple : .secondary)
                    }
                }

                Spacer()

                if isSealed {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.purple.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Memorial Tab

private struct MemorialTab: View {
    @ObservedObject var vm: LegacyStudioViewModel
    @Binding var showNew: Bool
    @State private var selectedEntry: LegacyEntry?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if vm.memorials.isEmpty {
                LegacyEmptyState(
                    icon: "flame.fill",
                    title: "Memorial Space",
                    subtitle: "Create a lasting tribute for someone you love. A place to remember, celebrate, and grieve.",
                    buttonLabel: "Create a Memorial",
                    color: .pink
                ) { showNew = true }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.memorials) { entry in
                            MemorialCard(entry: entry) { selectedEntry = entry }
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
            }

            if !vm.memorials.isEmpty {
                Button { showNew = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.pink))
                        .shadow(color: Color.pink.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(24)
            }
        }
        .sheet(item: $selectedEntry) { e in
            LegacyEntryEditorView(vm: vm, type: .memorial, existing: e)
        }
    }
}

private struct MemorialCard: View {
    let entry: LegacyEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.pink.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.pink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title.isEmpty ? "Untitled Memorial" : entry.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !entry.body.isEmpty {
                        Text(entry.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.pink.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generic Empty State

private struct LegacyEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonLabel: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(color.opacity(0.5))
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button(action: action) {
                Label(buttonLabel, systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(color))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Entry Editor

struct LegacyEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: LegacyStudioViewModel
    let type: LegacyEntryType
    let existing: LegacyEntry?

    @State private var title: String
    @State private var entryBody: String
    @State private var eventYear: String
    @State private var sealUntil: Date
    @State private var useSealDate: Bool
    @FocusState private var bodyFocused: Bool

    init(vm: LegacyStudioViewModel, type: LegacyEntryType, existing: LegacyEntry?) {
        self.vm = vm
        self.type = type
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _entryBody = State(initialValue: existing?.body ?? "")
        _eventYear = State(initialValue: existing?.eventYear.map(String.init) ?? "")
        _sealUntil = State(initialValue: existing?.sealUntil ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        _useSealDate = State(initialValue: existing?.sealUntil != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // Type badge
                    HStack(spacing: 8) {
                        Image(systemName: type.icon)
                            .font(.system(size: 14))
                        Text(type.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(type.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(type.accentColor.opacity(0.1)))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Title", text: $title)
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
                            Text(type == .timeCapsule ? "Write your letter…" : "Write your story…")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(.placeholderText))
                                .padding(.top, 19)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    }

                    if type == .memory {
                        TextField("Year (e.g. 1998)", text: $eventYear)
                            .keyboardType(.numberPad)
                            .font(.system(size: 15))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    }

                    if type == .timeCapsule {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Seal this letter", isOn: $useSealDate)
                                .font(.system(size: 15, weight: .medium))
                            if useSealDate {
                                DatePicker("Open on", selection: $sealUntil, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(20)
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
                        .foregroundStyle(type.accentColor)
                        .disabled(entryBody.isEmpty)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let entry = LegacyEntry(
            id: existing?.id ?? UUID(),
            type: type,
            title: title,
            body: entryBody,
            date: existing?.date ?? Date(),
            eventYear: Int(eventYear),
            sealUntil: (type == .timeCapsule && useSealDate) ? sealUntil : nil,
            isSealed: (type == .timeCapsule && useSealDate) ? Date() < sealUntil : false
        )
        vm.save(entry: entry)
        HapticManager.impact(style: .medium)
        dismiss()
    }
}
