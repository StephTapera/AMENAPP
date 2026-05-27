import SwiftUI

struct WellnessJournalView: View {
    @StateObject private var service = WellnessStreakService()
    @State private var selectedEntry: WellnessJournalEntry? = nil
    @State private var showNewEntry = false
    @State private var currentMonth = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthNavigator
                    entriesSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Wellness Journal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        selectedEntry = WellnessJournalEntry(entry: "", shared: false)
                        showNewEntry = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New journal entry")
                }
            }
            .onAppear {
                service.startListening()
                service.loadJournalEntries(month: currentMonth)
            }
            .sheet(isPresented: $showNewEntry) {
                JournalEntryEditorView(service: service)
            }
        }
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                service.loadJournalEntries(month: currentMonth)
            } label: {
                Image(systemName: "chevron.left").foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Button {
                currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                service.loadJournalEntries(month: currentMonth)
            } label: {
                Image(systemName: "chevron.right").foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .accessibilityLabel("Next month")
        }
    }

    private var entriesSection: some View {
        VStack(spacing: 10) {
            if service.journalEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 40))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("No entries this month")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Button("Write First Entry") { showNewEntry = true }
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(service.journalEntries) { entry in
                    journalEntryCard(entry: entry)
                }
            }
        }
    }

    private func journalEntryCard(entry: WellnessJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let mood = entry.mood { Text(mood.emoji).font(.title3) }
                Text(entry.date.map { $0.dateValue().formatted(date: .abbreviated, time: .omitted) } ?? "")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                if entry.shared {
                    Image(systemName: "person.2.fill").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            Text(entry.entry)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(3)
            if let verse = entry.linkedVerse {
                Text("\(verse.book) \(verse.chapter):\(verse.verse)")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            }
        }
        .padding(12)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(12)
        .accessibilityLabel("Journal entry, \(entry.date.map { $0.dateValue().formatted(date: .abbreviated, time: .omitted) } ?? "")")
    }
}

struct JournalEntryEditorView: View {
    let service: WellnessStreakService
    @Environment(\.dismiss) private var dismiss
    @State private var entryText = ""
    @State private var selectedMood: WellnessMood? = nil
    @State private var reflection = ""
    @State private var isShared = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    moodSection
                    textSection
                    reflectionSection
                    shareToggle
                }
                .padding(16)
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        guard !entryText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isSaving = true
                        Task {
                            let entry = WellnessJournalEntry(entry: entryText, mood: selectedMood, reflection: reflection.isEmpty ? nil : reflection, shared: isShared)
                            await service.saveJournalEntry(entry)
                            dismiss()
                        }
                    }
                    .font(.custom("OpenSans-Bold", size: 16))
                    .disabled(entryText.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How are you feeling?")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            HStack(spacing: 12) {
                ForEach(WellnessMood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { selectedMood = mood }
                    } label: {
                        VStack(spacing: 4) {
                            Text(mood.emoji).font(.title2)
                            Text(mood.displayName).font(.custom("OpenSans-Regular", size: 10)).foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        .padding(8)
                        .background(selectedMood == mood ? Color(red: 0.10, green: 0.60, blue: 0.56).opacity(0.15) : Color.clear)
                        .cornerRadius(10)
                    }
                    .accessibilityLabel(mood.displayName)
                    .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                }
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your entry")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            TextEditor(text: $entryText)
                .font(.custom("OpenSans-Regular", size: 15))
                .frame(minHeight: 120)
                .padding(8)
                .background(AmenTheme.Colors.surfaceInput)
                .cornerRadius(10)
                .accessibilityLabel("Journal entry text")
        }
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reflection prompt")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("What's one thing you're grateful for today?")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .italic()
            TextEditor(text: $reflection)
                .font(.custom("OpenSans-Regular", size: 15))
                .frame(minHeight: 80)
                .padding(8)
                .background(AmenTheme.Colors.surfaceInput)
                .cornerRadius(10)
                .accessibilityLabel("Reflection response")
        }
    }

    private var shareToggle: some View {
        Toggle(isOn: $isShared) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share this entry")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Appears on your profile and feed")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .tint(Color(red: 0.10, green: 0.60, blue: 0.56))
        .padding(12)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(10)
    }
}
