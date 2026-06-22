// VoicePrayerVisibilityPickerView.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Liquid Glass visibility selector sheet for voice comments.

import SwiftUI

struct VoicePrayerVisibilityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selected: VoiceCommentVisibility

    // Feature-flagged: prayer circle only shown when flag is on
    private var availableOptions: [VoiceCommentVisibility] {
        let flags = AMENFeatureFlags.shared
        var opts: [VoiceCommentVisibility] = [.public, .followers, .church]
        if flags.voiceCommentPrayerCircleVisibilityEnabled {
            opts.append(.prayerCircle)
        }
        opts.append(.private)
        return opts
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(uiColor: .separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("Who can hear this?")
                    .font(.systemScaled(18, weight: .bold))
                    .foregroundStyle(Color(uiColor: .label))
                    .padding(.horizontal, 20)

                Text("Your voice \(selected.rawValue == "private" ? "note" : "comment") will only be visible to the audience you choose.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(availableOptions, id: \.self) { option in
                        Button {
                            selected = option
                            HapticManager.impact(style: .light)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.systemIcon)
                                    .font(.systemScaled(16, weight: .medium))
                                    .frame(width: 24)
                                    .foregroundStyle(selected == option
                                                     ? Color(uiColor: .label)
                                                     : Color(uiColor: .secondaryLabel))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(.systemScaled(15, weight: selected == option ? .semibold : .regular))
                                        .foregroundStyle(Color(uiColor: .label))
                                    if let desc = optionDescription(option) {
                                        Text(desc)
                                            .font(.systemScaled(12))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                }

                                Spacer()

                                if selected == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.systemScaled(18, weight: .medium))
                                        .foregroundStyle(Color(uiColor: .label))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected == option
                                          ? (reduceTransparency
                                             ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                             : AnyShapeStyle(.regularMaterial))
                                          : AnyShapeStyle(Color(uiColor: .tertiarySystemBackground)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        selected == option
                                            ? Color(uiColor: .separator).opacity(0.5)
                                            : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.displayName). \(optionDescription(option) ?? "")")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func optionDescription(_ option: VoiceCommentVisibility) -> String? {
        switch option {
        case .public:      return "Anyone on AMEN can hear this"
        case .followers:   return "Only people who follow you"
        case .church:      return "Your connected church community"
        case .prayerCircle: return "Your private prayer group only"
        case .private:     return "Only you can hear this"
        }
    }
}
