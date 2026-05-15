import SwiftUI

// MARK: - Selah AI Concierge View (Primitive 8 / 20)
// Ambient, non-intrusive media concierge. Accessible as a sheet from the Selah toolbar.
// Never mandatory — always dismissible. Language is calm and suggestive, never controlling.

struct SelahAIConciergeView: View {
    @ObservedObject var service: SelahMediaService
    let contextWindow: SelahContextWindow?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var brief: ConciergeBrief?
    @State private var isLoading = true
    @State private var expandedSectionId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        loadingView
                    } else if let b = brief {
                        briefContent(b)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Concierge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            brief = await buildBrief()
            isLoading = false
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your session…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Brief Content

    private func briefContent(_ b: ConciergeBrief) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Session summary card
            sessionSummaryCard(b)

            // Suggestions
            if !b.suggestions.isEmpty {
                suggestionsSection(b.suggestions)
            }

            // Saves organizer
            if !b.savedThemes.isEmpty {
                savedOrganizer(b.savedThemes)
            }

            // Learning path
            if let path = b.learningPathSuggestion {
                learningPathCard(path)
            }

            // Relationship nudge
            if let nudge = b.relationshipNudge {
                relationshipNudgeCard(nudge)
            }
        }
    }

    private func sessionSummaryCard(_ b: ConciergeBrief) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your Session", systemImage: "chart.bar.xaxis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            HStack(spacing: 0) {
                statCell(value: "\(b.postsViewed)", label: "moments")
                Divider().frame(height: 32)
                statCell(value: b.dominantTheme?.rawValue ?? "—", label: "top theme")
                Divider().frame(height: 32)
                statCell(value: b.sessionDuration, label: "time")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 16)
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func suggestionsSection(_ suggestions: [ConciergeSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    conciergeSuggestionRow(suggestion)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func conciergeSuggestionRow(_ s: ConciergeSuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.icon)
                .font(.system(size: 15))
                .foregroundStyle(s.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(s.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = s.subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let action = s.actionLabel {
                Button {
                    s.onAction?()
                    dismiss()
                } label: {
                    Text(action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(s.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(s.color.opacity(0.10)))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func savedOrganizer(_ themes: [SelahMeaningCategory: Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Saved Content")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(themes.sorted(by: { $0.value > $1.value }), id: \.key) { cat, count in
                        VStack(spacing: 4) {
                            Text(cat.emoji)
                                .font(.title2)
                            Text(cat.rawValue)
                                .font(.caption2.weight(.medium))
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 70, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func learningPathCard(_ path: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("Learning path detected")
                    .font(.subheadline.weight(.semibold))
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.teal.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.teal.opacity(0.18), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
    }

    private func relationshipNudgeCard(_ nudge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 16))
                .foregroundStyle(.purple)
            Text(nudge)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.purple.opacity(0.06))
        )
        .padding(.horizontal, 16)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.purple.opacity(0.03)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Brief Building

    private func buildBrief() async -> ConciergeBrief {
        let memories = service.memories
        let continuations = service.continuations

        // Dominant theme from memories
        let catCounts = Dictionary(
            grouping: memories.flatMap { $0.meaningTags },
            by: { SelahMeaningCategory(rawValue: $0.category) }
        )
        .compactMapKeys { $0 }
        .mapValues { $0.count }

        let dominant = catCounts.max(by: { $0.value < $1.value })?.key
        let sessionDuration = contextWindow.map { _ in "active" } ?? "—"
        let postsViewed = service.mediaFeed.count

        // Build suggestions
        var suggestions: [ConciergeSuggestion] = []

        if memories.count > 3 {
            let top = catCounts.sorted(by: { $0.value > $1.value }).prefix(2).map { $0.key.rawValue }.joined(separator: " & ")
            suggestions.append(ConciergeSuggestion(
                text: "You saved several \(top) moments. Want these grouped?",
                subtitle: "\(memories.count) memories to organise",
                icon: "folder.badge.plus",
                color: .purple,
                actionLabel: "Group",
                onAction: nil
            ))
        }

        if let cont = continuations.first(where: { !$0.completed }) {
            suggestions.append(ConciergeSuggestion(
                text: "Continue where you left off?",
                subtitle: cont.promptText,
                icon: "arrow.right.circle",
                color: .teal,
                actionLabel: "Continue",
                onAction: nil
            ))
        }

        if let window = contextWindow, window.restSignalDetected {
            suggestions.append(ConciergeSuggestion(
                text: "You usually watch lighter content around now.",
                subtitle: "Switch to Pause mode?",
                icon: "moon.zzz",
                color: .indigo,
                actionLabel: "Switch",
                onAction: nil
            ))
        }

        if suggestions.isEmpty {
            suggestions.append(ConciergeSuggestion(
                text: "Your feed looks healthy.",
                subtitle: "Keep exploring or take a break.",
                icon: "checkmark.circle",
                color: .green,
                actionLabel: nil,
                onAction: nil
            ))
        }

        // Saved themes map
        let savedThemes = Dictionary(
            grouping: memories.flatMap { $0.meaningTags },
            by: { SelahMeaningCategory(rawValue: $0.category) }
        )
        .compactMapKeys { $0 }
        .mapValues { $0.count }

        // Learning path
        let learningPath: String? = memories.count > 2
            ? "You've saved content on \(dominant?.rawValue ?? "faith") — Part 2 available?"
            : nil

        return ConciergeBrief(
            postsViewed: postsViewed,
            dominantTheme: dominant,
            sessionDuration: sessionDuration,
            suggestions: suggestions,
            savedThemes: savedThemes,
            learningPathSuggestion: learningPath,
            relationshipNudge: nil
        )
    }
}

// MARK: - Concierge Models

struct ConciergeBrief {
    var postsViewed: Int
    var dominantTheme: SelahMeaningCategory?
    var sessionDuration: String
    var suggestions: [ConciergeSuggestion]
    var savedThemes: [SelahMeaningCategory: Int]
    var learningPathSuggestion: String?
    var relationshipNudge: String?
}

struct ConciergeSuggestion: Identifiable {
    let id = UUID()
    var text: String
    var subtitle: String?
    var icon: String
    var color: Color
    var actionLabel: String?
    var onAction: (() -> Void)?
}

// MARK: - Dictionary helper

private extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
