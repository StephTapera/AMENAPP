import SwiftUI

struct PollComposerCard: View {
    @Binding var options: [String]
    @Binding var duration: CreatePostView.PollDuration
    let onRemove: () -> Void

    @FocusState private var focusedIndex: Int?

    private let maxOptions = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Poll")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Remove poll")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 14)

            VStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            Text(optionLabel(index))
                                .font(.systemScaled(11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        TextField(index < 2 ? "Option \(index + 1)" : "Add option \(index + 1)",
                                  text: $options[index])
                            .font(AMENFont.regular(15))
                            .focused($focusedIndex, equals: index)
                            .submitLabel(index < options.count - 1 ? .next : .done)
                            .onSubmit {
                                if index < options.count - 1 {
                                    focusedIndex = index + 1
                                } else {
                                    focusedIndex = nil
                                }
                            }

                        if index >= 2 {
                            removeOptionButton(at: index)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if index < options.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }

            if options.count < maxOptions {
                Divider().padding(.horizontal, 14)

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                        options.append("")
                        focusedIndex = options.count - 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.systemScaled(15, weight: .medium))
                        Text("Add option")
                            .font(AMENFont.regular(14))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .accessibilityLabel("Add poll option")
            }

            Divider().padding(.horizontal, 14)

            HStack {
                Image(systemName: "clock")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                Text("Duration")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Duration", selection: $duration) {
                    ForEach(CreatePostView.PollDuration.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.menu)
                .font(AMENFont.regular(14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.systemGray5), lineWidth: 1)
        )
    }

    private func optionLabel(_ index: Int) -> String {
        let labels = ["A", "B", "C", "D"]
        return index < labels.count ? labels[index] : "\(index + 1)"
    }

    @ViewBuilder
    private func removeOptionButton(at index: Int) -> some View {
        let accessLabel = "Remove option \(index + 1)"
        Button {
            var copy = options
            copy.remove(at: index)
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                options = copy
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.systemScaled(18))
                .foregroundStyle(Color(.systemGray3))
        }
        .accessibilityLabel(accessLabel)
    }
}

struct CompactGlassButton: View {
    let icon: String
    let isActive: Bool
    var count: Int = 0
    let action: () -> Void

    @State private var isPressed = false

    private var isClose: Bool { icon == "xmark" }

    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) {
                isPressed = true
            }
            action()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) {
                    isPressed = false
                }
            }
        }) {
            ZStack(alignment: .topTrailing) {
                if isClose {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.91, green: 0.91, blue: 0.93))
                            .frame(width: 38, height: 38)
                            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                        Image(systemName: icon)
                            .font(.systemScaled(15, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                    .scaleEffect(isPressed ? 0.88 : 1.0)
                } else {
                    Image(systemName: icon)
                        .font(.systemScaled(16, weight: .light))
                        .foregroundStyle(isActive ? Color.primary.opacity(0.7) : Color.primary.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .scaleEffect(isPressed ? 0.85 : 1.0)

                    if count > 0 {
                        Text("\(count)")
                            .font(AMENFont.bold(9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                            .offset(x: 8, y: -8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
    }
}
