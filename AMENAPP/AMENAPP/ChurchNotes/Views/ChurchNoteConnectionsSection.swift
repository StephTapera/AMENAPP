// ChurchNoteConnectionsSection.swift
// AMENAPP
//
// Sermon threading — shows notes connected to the current note by theme or scripture.
// Displayed as a compact "Connected" section inside the editor or detail view.
// Design: quiet, non-intrusive, compact cards. Only shown when confidence is strong.

import SwiftUI

// MARK: - Connections Section

struct ChurchNoteConnectionsSection: View {

    let connections: [ChurchNoteConnection]
    let onOpenNote: (String) -> Void   // called with noteId to navigate

    @State private var isExpanded = true

    var body: some View {
        if !connections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                headerRow

                if isExpanded {
                    connectionCards
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(ChurchNotesAnimationTokens.sectionExpand) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Connected notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(connections.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Connected notes: \(connections.count)")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
    }

    // MARK: - Cards

    private var connectionCards: some View {
        VStack(spacing: 6) {
            ForEach(connections) { connection in
                connectionCard(connection)
            }
        }
    }

    private func connectionCard(_ connection: ChurchNoteConnection) -> some View {
        Button {
            onOpenNote(connection.relatedNoteId)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Strength indicator dot
                Circle()
                    .fill(strengthColor(connection.connectionStrength))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(connection.relatedNoteTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(connection.relatedNoteDate, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if !connection.sharedThemes.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text(connection.sharedThemes.prefix(2).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(connection.strengthLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(strengthColor(connection.connectionStrength).opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(connection.relatedNoteTitle), \(connection.strengthLabel). Themes: \(connection.sharedThemes.joined(separator: ", "))")
        .accessibilityHint("Tap to open this note")
    }

    private func strengthColor(_ strength: Double) -> Color {
        if strength > 0.7 { return Color(.systemGreen).opacity(0.75) }
        if strength > 0.4 { return Color.secondary.opacity(0.6) }
        return Color(.tertiaryLabel)
    }
}

// MARK: - Thread Count Chip (for note list cards)

/// Shown on a note card to indicate it has connected notes.
struct ChurchNoteThreadChip: View {
    let connectionCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.systemScaled(10))
                .accessibilityHidden(true)
            Text("\(connectionCount)")
                .font(.systemScaled(10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityLabel("\(connectionCount) connected note\(connectionCount == 1 ? "" : "s")")
    }
}

// MARK: - Sermon Thread Count Label

/// Inline label shown when a theme has appeared multiple times.
struct CNThemeOccurrenceLabel: View {
    let theme: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Your \(ordinal(count)) note on \(theme.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityLabel("This is your \(ordinal(count)) note on \(theme)")
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 10 {
        case 1 where n % 100 != 11: suffix = "st"
        case 2 where n % 100 != 12: suffix = "nd"
        case 3 where n % 100 != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

#if DEBUG
struct ChurchNoteConnectionsSection_Previews: PreviewProvider {
    static let sampleConnections = [
        ChurchNoteConnection(
            relatedNoteId: "note1",
            relatedNoteTitle: "Trust and Obedience",
            relatedNoteDate: Calendar.current.date(byAdding: .day, value: -21, to: Date())!,
            sharedThemes: ["trust", "obedience"],
            connectionStrength: 0.82
        ),
        ChurchNoteConnection(
            relatedNoteId: "note2",
            relatedNoteTitle: "Waiting on God",
            relatedNoteDate: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
            sharedThemes: ["waiting"],
            connectionStrength: 0.54
        ),
    ]

    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChurchNoteConnectionsSection(
                    connections: sampleConnections,
                    onOpenNote: { _ in }
                )
                .padding()

                CNThemeOccurrenceLabel(theme: "surrender", count: 4)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
#endif
