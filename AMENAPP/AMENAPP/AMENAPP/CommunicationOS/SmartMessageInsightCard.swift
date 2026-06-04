import SwiftUI

// MARK: - Models

struct DetectedMessageContext: Identifiable {
    let id: UUID
    let type: DetectedContextType
    let displayText: String
    let actionLabel: String
}

enum DetectedContextType {
    case date, link, music, task, memory

    var icon: String {
        switch self {
        case .date:   return "calendar"
        case .link:   return "link"
        case .music:  return "music.note"
        case .task:   return "checkmark.circle"
        case .memory: return "brain"
        }
    }
}

// MARK: - View

struct SmartMessageInsightCard: View {
    let detectedItems: [DetectedMessageContext]
    let onAction: (DetectedMessageContext) -> Void
    let onDismiss: (DetectedMessageContext) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "smartMessageContextEnabled") as? Bool) ?? true
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

    private func chip(for item: DetectedMessageContext) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.type.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                onAction(item)
            } label: {
                Text(item.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.actionLabel)

            Button {
                onDismiss(item)
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
                .stroke(Color.white.opacity(0.4), lineWidth: 0.6)
        )
    }
}
