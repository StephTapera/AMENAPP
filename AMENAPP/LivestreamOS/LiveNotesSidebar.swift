// LiveNotesSidebar.swift
// AMENAPP — LivestreamOS
// Live notes, prayer, polls, Q&A, and reactions panel shown during a livestream.

import SwiftUI

// MARK: - Live Panel Mode

enum LivePanelMode: String, CaseIterable {
    case notes, prayer, qa, reactions

    var label: String {
        switch self {
        case .notes:     return "Notes"
        case .prayer:    return "Pray"
        case .qa:        return "Q&A"
        case .reactions: return "React"
        }
    }

    var icon: String {
        switch self {
        case .notes:     return "note.text"
        case .prayer:    return "hands.sparkles.fill"
        case .qa:        return "questionmark.bubble.fill"
        case .reactions: return "heart.fill"
        }
    }
}

// MARK: - Live Q&A Item

struct LiveQAItem: Identifiable {
    let id: String
    var question: String
    var askerName: String?
    var isAnonymous: Bool
    var votes: Int
    var isAnswered: Bool
}

// MARK: - Live Notes Sidebar

struct LiveNotesSidebar: View {
    let streamId: String
    let isHost: Bool

    @State private var mode: LivePanelMode = .notes
    @State private var noteText = ""
    @State private var prayerText = ""
    @State private var questionText = ""
    @State private var qaItems: [LiveQAItem] = []
    @State private var reactionCounts: [String: Int] = ["🙏": 0, "❤️": 0, "🔥": 0, "✝️": 0, "⭐": 0]
    @State private var myReaction: String? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            HStack(spacing: 0) {
                ForEach(LivePanelMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.25)) { mode = m }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: m.icon).font(.system(size: 16))
                            Text(m.label).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(mode == m ? Color.accentColor : .secondary)
                        .background(mode == m ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.label)
                    .accessibilityAddTraits(mode == m ? [.isSelected] : [])
                }
            }
            .background {
                if reduceTransparency { Color(.secondarySystemBackground) }
                else { Rectangle().fill(.thinMaterial) }
            }

            Divider().opacity(0.3)

            // Panel content
            switch mode {
            case .notes:    notesPanel
            case .prayer:   prayerPanel
            case .qa:       qaPanel
            case .reactions: reactionsPanel
            }
        }
        .background(reduceTransparency ? Color(.systemBackground) : Color(.systemBackground).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Notes Panel

    @ViewBuilder
    private var notesPanel: some View {
        VStack(spacing: 0) {
            TextEditor(text: $noteText)
                .font(.subheadline)
                .frame(minHeight: 120)
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Take notes during the stream…")
                            .font(.subheadline).foregroundStyle(.quaternary).padding(16).allowsHitTesting(false)
                    }
                }
            Divider().opacity(0.3)
            Button {
                // Save note stub — real impl writes to ChurchNotes
            } label: {
                Label("Save Note", systemImage: "note.text.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .frame(height: 40)
            .accessibilityLabel("Save note")
        }
    }

    // MARK: - Prayer Panel

    @ViewBuilder
    private var prayerPanel: some View {
        VStack(spacing: 12) {
            TextEditor(text: $prayerText)
                .font(.subheadline)
                .frame(height: 80)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if prayerText.isEmpty {
                        Text("Share a prayer request or praise…")
                            .font(.subheadline).foregroundStyle(.quaternary).padding(14).allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Button {
                    // Submit anonymous prayer request
                    prayerText = ""
                } label: {
                    Text("Submit Anonymously")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    // Submit prayer request with name
                    prayerText = ""
                } label: {
                    Text("Submit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    // MARK: - Q&A Panel

    @ViewBuilder
    private var qaPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Ask a question…", text: $questionText)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    guard !questionText.isEmpty else { return }
                    let item = LiveQAItem(id: UUID().uuidString, question: questionText,
                                         askerName: nil, isAnonymous: true, votes: 0, isAnswered: false)
                    qaItems.insert(item, at: 0)
                    questionText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(questionText.isEmpty ? .secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(questionText.isEmpty)
                .accessibilityLabel("Submit question")
            }
            .padding(12)

            Divider().opacity(0.3)

            if qaItems.isEmpty {
                Text("No questions yet. Be the first!").font(.caption).foregroundStyle(.secondary).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(qaItems.sorted { $0.votes > $1.votes }) { item in
                            QAItemRow(item: item, isHost: isHost) {
                                if let idx = qaItems.firstIndex(where: { $0.id == item.id }) {
                                    qaItems[idx].votes += 1
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Reactions Panel

    @ViewBuilder
    private var reactionsPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(["🙏", "❤️", "🔥", "✝️", "⭐"], id: \.self) { emoji in
                    Button {
                        myReaction = emoji
                        reactionCounts[emoji, default: 0] += 1
                    } label: {
                        VStack(spacing: 4) {
                            Text(emoji).font(.system(size: 28))
                                .scaleEffect(myReaction == emoji && !reduceMotion ? 1.3 : 1.0)
                                .animation(reduceMotion ? nil : .spring(response: 0.25), value: myReaction)
                            Text("\(reactionCounts[emoji] ?? 0)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("React with \(emoji)")
                }
            }
            .padding(.horizontal, 12)

            if let r = myReaction {
                Text("You reacted with \(r)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Q&A Item Row

private struct QAItemRow: View {
    let item: LiveQAItem
    let isHost: Bool
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.up").font(.caption.weight(.bold))
                    Text("\(item.votes)").font(.caption2)
                }
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vote for question. \(item.votes) votes.")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.question).font(.caption)
                Text(item.isAnonymous ? "Anonymous" : (item.askerName ?? "Member"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if item.isAnswered {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
