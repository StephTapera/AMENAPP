import SwiftUI

// MARK: - Models

struct ConversationMemoryItem: Identifiable {
    let id: UUID
    let type: ConversationMemoryType
    let title: String
    let body: String?
    let timestamp: Date
}

enum ConversationMemoryType {
    case link, date, music, note, task, event, memory

    var icon: String {
        switch self {
        case .link:   return "link"
        case .date:   return "calendar"
        case .music:  return "music.note"
        case .note:   return "note.text"
        case .task:   return "checkmark.circle"
        case .event:  return "calendar.badge.plus"
        case .memory: return "brain"
        }
    }
}

// MARK: - View

struct ConversationMemoryCard: View {
    let memories: [ConversationMemoryItem]
    let onDelete: (ConversationMemoryItem) -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "conversationMemoryEnabled") as? Bool) ?? true
    }

    var body: some View {
        if isEnabled {
            VStack(spacing: 0) {
                headerRow
                if isExpanded {
                    memoryList
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
            )
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82),
                value: isExpanded
            )
        } else {
            EmptyView()
        }
    }

    private var headerRow: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("\(memories.count) Saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(memories.count) saved memories")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }

    private var memoryList: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            if memories.isEmpty {
                Text("No saved memories yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(memories) { item in
                    memoryRow(item)
                    if item.id != memories.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func memoryRow(_ item: ConversationMemoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let body = item.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Delete \(item.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
