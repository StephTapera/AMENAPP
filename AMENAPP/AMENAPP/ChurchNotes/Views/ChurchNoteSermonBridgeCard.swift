// ChurchNoteSermonBridgeCard.swift
// AMENAPP
//
// "Sermon to Monday" bridge card — helps users carry the sermon into their week.
// Replaces / extends the existing ChurchNotesGrowthCard with spiritually-aligned framing.
//
// Design: glass card, calm spacing, no corporate productivity language.
// Language is spiritually warm and personal, not task-list driven.

import SwiftUI

struct ChurchNoteSermonBridgeCard: View {

    @Binding var bridge: CNSermonBridge
    let onChanged: () -> Void

    @State private var isExpanded = false
    @State private var editingField: BridgeField?

    enum BridgeField: Hashable {
        case oneLine, action, prayer, person
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(16)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                bridgeFields
                    .padding(16)

                if bridge.isPopulated {
                    obedienceTracker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        }
        .churchNotesGlassCard()
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(ChurchNotesAnimationTokens.sectionExpand) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.systemGreen).opacity(0.8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Carry into your week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !isExpanded && bridge.isPopulated {
                        Text(bridge.oneLineToRemember.isEmpty
                             ? "Tap to review"
                             : bridge.oneLineToRemember)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !isExpanded {
                        Text("One sentence, one action, one prayer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Carry into your week section")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
    }

    // MARK: - Bridge Fields

    private var bridgeFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            bridgeField(
                label: "One sentence to carry with me",
                placeholder: "What one truth do you want to hold onto?",
                icon: "quote.closing",
                text: $bridge.oneLineToRemember
            )

            bridgeField(
                label: "One action to take this week",
                placeholder: "What will you do before Sunday?",
                icon: "checkmark.circle",
                text: $bridge.actionThisWeek
            )

            bridgeField(
                label: "One prayer to pray this week",
                placeholder: "What do you want to bring to God?",
                icon: "hands.sparkles",
                text: $bridge.prayerThisWeek
            )

            bridgeField(
                label: "One person to encourage",
                placeholder: "Who came to mind during the sermon?",
                icon: "person.wave.2",
                text: $bridge.personToEncourage
            )
        }
    }

    private func bridgeField(
        label: String,
        placeholder: String,
        icon: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            TextField(placeholder, text: text, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2...4)
                .onChange(of: text.wrappedValue) { _, _ in
                    bridge.updatedAt = Date()
                    onChanged()
                }
        }
    }

    // MARK: - Obedience Tracker

    private var obedienceTracker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How did it go?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                if !bridge.actionThisWeek.isEmpty {
                    obedienceChip(
                        label: "Action",
                        status: $bridge.actionStatus
                    )
                }
                if !bridge.prayerThisWeek.isEmpty {
                    obedienceChip(
                        label: "Prayer",
                        status: $bridge.prayerStatus
                    )
                }
                if !bridge.personToEncourage.isEmpty {
                    obedienceChip(
                        label: "Encourage",
                        status: $bridge.personStatus
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func obedienceChip(
        label: String,
        status: Binding<CNObedienceStatus>
    ) -> some View {
        Menu {
            ForEach(CNObedienceStatus.allCases, id: \.self) { s in
                Button {
                    withAnimation(ChurchNotesAnimationTokens.quickTap) {
                        status.wrappedValue = s
                        bridge.updatedAt = Date()
                        onChanged()
                    }
                } label: {
                    Label(s.displayName, systemImage: s.icon)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: status.wrappedValue.icon)
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(status.wrappedValue.isResolved ? Color(.systemGreen) : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(status.wrappedValue.isResolved
                          ? Color(.systemGreen).opacity(0.1)
                          : Color(.tertiarySystemFill))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                status.wrappedValue.isResolved
                                    ? Color(.systemGreen).opacity(0.3)
                                    : Color.primary.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .accessibilityLabel("\(label): \(status.wrappedValue.displayName). Tap to change.")
    }
}

// MARK: - Compact preview chip for note list card

struct CNBridgeStatusChip: View {
    let bridge: CNSermonBridge

    private var allDone: Bool {
        bridge.actionStatus.isResolved && bridge.prayerStatus.isResolved
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: allDone ? "checkmark.circle.fill" : "calendar.badge.checkmark")
                .font(.system(size: 10))
                .accessibilityHidden(true)
            Text(allDone ? "Week complete" : "This week")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(allDone ? Color(.systemGreen).opacity(0.85) : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(allDone
                      ? Color(.systemGreen).opacity(0.08)
                      : Color(.tertiarySystemFill))
        )
        .accessibilityLabel(allDone ? "Week complete" : "Active this week")
    }
}

#if DEBUG
struct ChurchNoteSermonBridgeCard_Previews: PreviewProvider {
    @State static var bridge = CNSermonBridge.empty(noteId: "preview")

    static var previews: some View {
        ScrollView {
            ChurchNoteSermonBridgeCard(
                bridge: $bridge,
                onChanged: {}
            )
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}
#endif
