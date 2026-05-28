//
//  SelahScriptureSurfaces.swift
//  AMENAPP
//
//  Three calm, additive surfaces for the Selah Scripture experience:
//
//   * `SelahScriptureTimelineView` — chronological reading history derived
//     from real `SelahService.sessions` and the engagement store.
//   * `SelahTopicExplorationView` — search by spiritual state, returns
//     real reflections + saved verses from the user's own data.
//   * `SelahScriptureShareCardView` — Apple-style verse share card.
//
//  Everything here is read-only on real persisted data; nothing fabricates.
//

import SwiftUI

// MARK: - Scripture Timeline

struct SelahScriptureTimelineView: View {
    @ObservedObject private var selahService = SelahService.shared
    @ObservedObject private var saved = SelahSavedScriptureStore.shared
    @ObservedObject private var engagements = SelahVerseEngagementStore.shared
    @Environment(\.dismiss) private var dismiss

    /// A merged, chronological feed of meaningful scripture moments.
    private struct TimelineItem: Identifiable {
        enum Kind { case reading, saved, highlight, reaction, prayed }
        let id = UUID()
        let kind: Kind
        let title: String
        let subtitle: String
        let date: Date
        let icon: String
    }

    private var items: [TimelineItem] {
        var merged: [TimelineItem] = []

        for session in selahService.sessions {
            if let ref = session.scriptureRefs.first {
                merged.append(.init(
                    kind: .reading,
                    title: ref,
                    subtitle: session.title.isEmpty ? "Read" : session.title,
                    date: session.createdAt,
                    icon: "book.fill"
                ))
            }
        }

        for entry in saved.saved {
            merged.append(.init(
                kind: .saved,
                title: entry.reference.displayString,
                subtitle: "Saved · \(entry.translationId.uppercased())",
                date: entry.savedAt,
                icon: "bookmark.fill"
            ))
        }

        for entry in saved.highlights {
            merged.append(.init(
                kind: .highlight,
                title: entry.reference.displayString,
                subtitle: "Highlighted (\(entry.toneKey))",
                date: entry.createdAt,
                icon: "highlighter"
            ))
        }

        for entry in engagements.reactions {
            merged.append(.init(
                kind: .reaction,
                title: entry.reference.displayString,
                subtitle: "Reacted: \(entry.kind.label)",
                date: entry.createdAt,
                icon: entry.kind.icon
            ))
        }

        for entry in engagements.prayedThrough {
            merged.append(.init(
                kind: .prayed,
                title: entry.reference.displayString,
                subtitle: "Prayed through",
                date: entry.createdAt,
                icon: "hands.sparkles.fill"
            ))
        }

        return merged.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyState
                        .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            Divider().opacity(0.15)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Scripture Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.05)).frame(width: 32, height: 32)
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.date, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.pages")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No scripture moments yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Read, save, react, or pray a verse\nand it will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Topic Exploration

struct SelahTopicExplorationView: View {
    @ObservedObject private var selahService = SelahService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTopic: String?

    private let topics: [String] = [
        "Anxiety", "Grief", "Wisdom", "Loneliness",
        "Healing", "Forgiveness", "Hope", "Faith",
        "Peace", "Identity", "Purpose", "Joy"
    ]

    private var filteredSessions: [SelahSession] {
        guard let topic = selectedTopic else { return selahService.sessions }
        let lower = topic.lowercased()
        return selahService.sessions.filter { session in
            session.tags.contains(where: { $0.lowercased().contains(lower) }) ||
            session.title.lowercased().contains(lower) ||
            session.responsePreview.lowercased().contains(lower)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chipRow
                    if let topic = selectedTopic {
                        sectionHeader("Real moments on \(topic.lowercased())")
                        if filteredSessions.isEmpty {
                            Text("Nothing matched yet. Try another topic — or open this in scripture search.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        } else {
                            sessionList
                        }
                    } else {
                        Text("Pick a spiritual state to explore real moments from your own reading and reflection.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    SelahTopicChip(
                        label: topic,
                        isSelected: selectedTopic == topic
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedTopic = selectedTopic == topic ? nil : topic
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSessions, id: \.id) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.title.isEmpty ? (session.scriptureRefs.first ?? "Study") : session.title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(session.createdAt, format: .relative(presentation: .named))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let ref = session.scriptureRefs.first {
                        Text(ref)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    if !session.responsePreview.isEmpty {
                        Text(session.responsePreview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider().opacity(0.12)
            }
        }
    }
}

// MARK: - Scripture Share Card

struct SelahScriptureShareCardView: View {
    let reference: ScriptureReference
    let text: String
    let translationAbbreviation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AMEN · SELAH")
                .font(.system(size: 9, weight: .semibold))
                .tracking(3)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            HStack {
                Text(reference.displayString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(translationAbbreviation)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color.white, Color(red: 0.97, green: 0.96, blue: 0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.0), Color.accentColor.opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 22, y: 8)
    }
}
