import SwiftUI

// MARK: - Action enum

enum MessageAttachmentAction: CaseIterable {
    case camera
    case photoLibrary
    case polls
    case sendLater
    case createReminder
    case saveMemory
    case addContactNote
    case shareLink
    case createEvent
    case createTask

    var icon: String {
        switch self {
        case .camera:          return "camera"
        case .photoLibrary:    return "photo.on.rectangle"
        case .polls:           return "chart.bar.xaxis"
        case .sendLater:       return "clock.arrow.circlepath"
        case .createReminder:  return "bell.badge"
        case .saveMemory:      return "brain"
        case .addContactNote:  return "person.text.rectangle"
        case .shareLink:       return "link"
        case .createEvent:     return "calendar.badge.plus"
        case .createTask:      return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .camera:          return "Camera"
        case .photoLibrary:    return "Photo Library"
        case .polls:           return "Polls"
        case .sendLater:       return "Send Later"
        case .createReminder:  return "Create Reminder"
        case .saveMemory:      return "Save Memory"
        case .addContactNote:  return "Add Contact Note"
        case .shareLink:       return "Share Link"
        case .createEvent:     return "Create Event"
        case .createTask:      return "Create Task"
        }
    }
}

// MARK: - View

struct SmartMessageActionMenu: View {
    var onAction: (MessageAttachmentAction) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(MessageAttachmentAction.allCases, id: \.title) { action in
                        actionRow(action)
                        if action.title != MessageAttachmentAction.allCases.last?.title {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background {
            if reduceTransparency {
                Color.white
                    .ignoresSafeArea()
            } else {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .accessibilityHidden(true)
    }

    private func actionRow(_ action: MessageAttachmentAction) -> some View {
        Button {
            onAction(action)
            onDismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)

                Text(action.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}
