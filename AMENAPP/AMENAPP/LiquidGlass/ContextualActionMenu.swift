import SwiftUI

/// Floating contextual action menu — a glass card with a content preview and an
/// optional inline prompt, paired with a stack of glass action buttons that
/// animate in beside it.
///
/// Generic over the preview content, so it works for a verse card, a post
/// image, a Berean answer, an ARISE clip thumbnail, etc.
struct ContextualActionMenu<Preview: View>: View {

    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let role: ButtonRole?
        let handler: () -> Void
        init(symbol: String, title: String, role: ButtonRole? = nil,
             handler: @escaping () -> Void) {
            self.symbol = symbol; self.title = title; self.role = role; self.handler = handler
        }
    }

    @Binding var isPresented: Bool
    let items: [Item]
    var promptPlaceholder: String? = nil
    var onSubmitPrompt: (String) -> Void = { _ in }
    @ViewBuilder var preview: () -> Preview

    @State private var prompt = ""
    @FocusState private var promptFocused: Bool

    var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 12) {
                        preview()
                            .frame(width: 220, height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        if let placeholder = promptPlaceholder {
                            promptField(placeholder)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 28)

                    actionStack
                }
                .padding(.horizontal, 20)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.amenSpring, value: isPresented)
    }

    private var actionStack: some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                Button(role: item.role) {
                    item.handler()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                        Text(item.title).fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(item.role == .destructive ? Color.red : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 190)
    }

    private func promptField(_ placeholder: String) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($promptFocused)
            Button {
                onSubmitPrompt(prompt)
                prompt = ""
                promptFocused = false
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.amenPurple)
            }
            .buttonStyle(.plain)
            .opacity(prompt.isEmpty ? 0.4 : 1)
            .disabled(prompt.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 18)
    }

    private func dismiss() {
        promptFocused = false
        isPresented = false
    }
}
