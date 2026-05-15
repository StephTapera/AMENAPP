import SwiftUI

struct SpiritualDiscernmentPromptView: View {
    let prompt: DiscernmentPromptResult
    let onSelect: (DiscernmentPromptOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.promptTitle)
                .font(.system(size: 20, weight: .semibold))
            Text(prompt.promptMessage)
                .font(.system(size: 14))
                .foregroundStyle(.black.opacity(0.7))

            ForEach(prompt.options) { option in
                Button {
                    onSelect(option)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.label)
                            .font(.system(size: 15, weight: .semibold))
                        Text(option.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.black.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button("Not now", role: .cancel, action: onDismiss)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(20)
    }
}
