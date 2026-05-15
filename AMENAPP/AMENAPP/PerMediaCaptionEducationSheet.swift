import SwiftUI
import FirebaseAuth

// One-time "A new caption with every swipe" education modal.
// Shown after a user selects media in CreatePost when both flags are ON
// and the user has not dismissed it before.
struct PerMediaCaptionEducationSheet: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Dimmed scrim
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Card
            VStack(spacing: 0) {
                illustrationSection
                    .padding(.top, 32)
                    .padding(.bottom, 20)

                VStack(spacing: 12) {
                    Text("A new caption with every swipe")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text("You can now add a caption for each photo or video in your post.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                Button {
                    dismiss()
                } label: {
                    Text("OK")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary)
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 8)
            .frame(maxWidth: 360)
            .padding(.horizontal, 32)
        }
        .accessibilityAddTraits(.isModal)
        .task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            await MediaCaptionEducationService.shared.markSeen(uid: uid)
        }
    }

    // MARK: - Illustration

    private var illustrationSection: some View {
        HStack(spacing: 12) {
            ForEach(illustrationItems, id: \.icon) { item in
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.color.opacity(0.12))
                            .frame(width: 56, height: 56)
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(item.color)
                    }
                    Text(item.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var illustrationItems: [(icon: String, label: String, color: Color)] {
        [
            ("photo.fill", "Photo", .blue),
            ("video.fill", "Video", .purple),
            ("book.closed.fill", "Scripture", .orange)
        ]
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(UIColor.systemBackground)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    // MARK: - Actions

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
            onDismiss()
        }
    }
}

// MARK: - Modifier

extension View {
    func perMediaCaptionEducation(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                PerMediaCaptionEducationSheet {
                    isPresented.wrappedValue = false
                    onDismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isPresented.wrappedValue)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    PerMediaCaptionEducationSheet {}
}
#endif
