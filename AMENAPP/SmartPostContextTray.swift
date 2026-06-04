import SwiftUI

// MARK: - Models

enum DetectedPostContextType {
    case link, music, book, podcast, place, date, sensitiveSignal

    var icon: String {
        switch self {
        case .link:            return "link"
        case .music:           return "music.note"
        case .book:            return "book"
        case .podcast:         return "mic"
        case .place:           return "mappin.and.ellipse"
        case .date:            return "calendar"
        case .sensitiveSignal: return "exclamationmark.triangle"
        }
    }

    var actionLabel: String {
        switch self {
        case .link:            return "Add Preview"
        case .music:           return "Attach Music"
        case .book:            return "Attach Book"
        case .podcast:         return "Attach Podcast"
        case .place:           return "Tag Place"
        case .date:            return "Create Reminder"
        case .sensitiveSignal: return "Review Content"
        }
    }
}

struct DetectedPostContextItem: Identifiable {
    let id: UUID
    let type: DetectedPostContextType
    let displayText: String
    let rawValue: String
}

enum PostContextAction {
    case addLinkPreview, attachMusic, createReminder, saveAsMemory, dismiss
}

// MARK: - View

struct SmartPostContextTray: View {
    let detectedItems: [DetectedPostContextItem]
    let onAction: (PostContextAction, DetectedPostContextItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "smartPostContextEnabled")
    }

    var body: some View {
        if isEnabled && !detectedItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(detectedItems) { item in
                        chip(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.80)) {
                    appeared = true
                }
            }
            .onDisappear { appeared = false }
        }
    }

    private func chip(for item: DetectedPostContextItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.type.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.type == .sensitiveSignal ? Color.orange : Color.secondary)

            Button {
                onAction(primaryAction(for: item.type), item)
            } label: {
                Text(item.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.type.actionLabel): \(item.displayText)")

            Button {
                onAction(.dismiss, item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 20, minHeight: 20)
            .accessibilityLabel("Dismiss \(item.displayText)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    item.type == .sensitiveSignal ? Color.orange.opacity(0.4) : Color.white.opacity(0.4),
                    lineWidth: 0.6
                )
        )
    }

    private func primaryAction(for type: DetectedPostContextType) -> PostContextAction {
        switch type {
        case .link:            return .addLinkPreview
        case .music:           return .attachMusic
        case .date:            return .createReminder
        case .sensitiveSignal: return .saveAsMemory
        default:               return .addLinkPreview
        }
    }
}
