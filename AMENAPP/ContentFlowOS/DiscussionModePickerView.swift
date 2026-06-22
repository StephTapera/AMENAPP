// DiscussionModePickerView.swift
// AMENAPP — ContentFlowOS
// Picker for selecting the mode of a discussion thread.

import SwiftUI

struct DiscussionModePickerView: View {
    @Binding var selectedMode: ContentDiscussionMode
    let availableModes: [ContentDiscussionMode]
    let onConfirm: (ContentDiscussionMode) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(availableModes, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.icon)
                            .font(.systemScaled(18))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(modeDescription(mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selectedMode == mode ? [.isSelected] : [])
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Discussion Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onConfirm(selectedMode)
                        onDismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func modeDescription(_ mode: ContentDiscussionMode) -> String {
        switch mode {
        case .open:            return "Anyone in the space can participate"
        case .leaderModerated: return "Leaders approve replies before they're visible"
        case .anonymous:       return "Participants are not identified"
        case .prayerOnly:      return "Only prayer responses allowed"
        case .study:           return "Structured study discussion with guided questions"
        case .qaMode:          return "One question at a time, voted to the top"
        case .mentorOnly:      return "Only the mentor and mentee can see this thread"
        case .staffReview:     return "Staff review before publishing"
        case .eventFollowUp:   return "Follow-up discussion after an event"
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var mode: ContentDiscussionMode = .open
    DiscussionModePickerView(
        selectedMode: $mode,
        availableModes: ContentDiscussionMode.allCases,
        onConfirm: { _ in },
        onDismiss: {}
    )
}
