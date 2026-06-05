// GivingJournalView.swift
// AMENAPP
//
// Private giving journal — spiritual record, never social.
// Amounts hidden by default. No sharing surface. Private first.

import SwiftUI

struct GivingJournalView: View {
    @ObservedObject var store: StewardshipLocalStore
    @State private var showComposer = false
    @State private var editingEntry: GivingJournalEntry? = nil
    @State private var newNote = ""
    @State private var newScripture = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.journalEntries.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(store.journalEntries) { entry in
                            journalRow(entry)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteJournalEntry(id: entry.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.grouped)
                }
            }
            .navigationTitle("Giving Journal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            journalComposerSheet
        }
    }

    // MARK: - Entry Row

    private func journalRow(_ entry: GivingJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.destinationName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                if let date = entry.createdAt {
                    Text(date, style: .date)
                        .font(.system(size: 11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(4)
            }

            if let scripture = entry.scriptureRef, !scripture.isEmpty {
                Label(scripture, systemImage: "book.closed.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            if !entry.privateTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.privateTags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 40))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Your giving journal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("A private record of why you gave. Dates, notes, scripture — visible only to you.")
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 20)
            Button {
                showComposer = true
            } label: {
                Text("Add first entry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textInverse)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(AmenTheme.Colors.buttonPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer Sheet

    private var journalComposerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("Private. Not visible to anyone.")
                        .font(.system(size: 13))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Organization / cause")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    TextField("Who did you give to?", text: .constant(""))
                        .font(.system(size: 15))
                        .padding(12)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Why did you give?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    TextEditor(text: $newNote)
                        .font(.system(size: 15))
                        .frame(minHeight: 100)
                        .padding(10)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scripture (optional)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    TextField("e.g. Matthew 6:3", text: $newScripture)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(AmenTheme.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()

                Button {
                    // Save entry
                    let entry = GivingJournalEntry(
                        id: UUID().uuidString,
                        userId: "",
                        destinationType: .org,
                        destinationId: "",
                        destinationName: "Manual entry",
                        givingSessionId: nil,
                        note: newNote,
                        scriptureRef: newScripture.isEmpty ? nil : newScripture,
                        privateTags: [],
                        createdAt: Date()
                    )
                    store.addJournalEntry(entry)
                    showComposer = false
                    newNote = ""
                    newScripture = ""
                } label: {
                    Text("Save to journal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AmenTheme.Colors.buttonPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            .navigationTitle("Journal entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showComposer = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}
