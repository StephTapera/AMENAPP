import SwiftUI

struct LiquidGlassComposerBar: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var placeholder: String
    var onSubmit: (LivingEntryType, String) -> Void
    var onAskBerean: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var selectedType: LivingEntryType = .note

    var body: some View {
        VStack(spacing: 10) {
            if isExpanded {
                VStack(spacing: 12) {
                    HStack {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundStyle(.black)
                            .focused($focused)
                        Button {
                            withAnimation(animation) {
                                isExpanded = false
                                focused = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            actionCapsule(label: "Note", type: .note)
                            actionCapsule(label: "Reminder", type: .reminder)
                            actionCapsule(label: "Prayer", type: .prayer)
                            actionCapsule(label: "Church Note", type: .churchNote)
                            Button("Ask Berean") {
                                onAskBerean?()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.55)))
                        }
                    }

                    Button {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(selectedType, trimmed)
                    } label: {
                        Text("Create Entry")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.black))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Create living entry")
                }
            } else {
                Button {
                    withAnimation(animation) {
                        isExpanded = true
                        focused = true
                    }
                } label: {
                    HStack {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.black)
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open living entry composer")
            }
        }
        .padding(12)
        .background(
            Capsule(style: .continuous)
                .fill(LiquidGlassTokens.blurRegular)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 0.8)
                )
        )
        .shadow(color: LiquidGlassTokens.shadowFloating.color, radius: LiquidGlassTokens.shadowFloating.radius, y: LiquidGlassTokens.shadowFloating.y)
    }

    private func actionCapsule(label: String, type: LivingEntryType) -> some View {
        Button(label) {
            selectedType = type
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(selectedType == type ? Color.black : Color.white.opacity(0.55)))
        .foregroundStyle(selectedType == type ? .white : .black)
        .accessibilityAddTraits(selectedType == type ? .isSelected : [])
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: LiquidGlassTokens.motionFast) : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
    }
}
