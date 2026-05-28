import SwiftUI

// MARK: - ReactionWithNoteSheet
// GlassSheet(.medium) allowing the user to pair a reaction with a private note
// (max 140 characters). Send is disabled until the note field contains text.

@MainActor
struct ReactionWithNoteSheet: View {
    @Binding var isPresented: Bool
    var reactionType: MediaReactionType
    var onSend: (MediaReactionType, String) -> Void

    @State private var noteText: String = ""
    @FocusState private var isNoteFocused: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let maxNoteLength = 140

    var body: some View {
        Color.clear
            .glassSheet(isPresented: $isPresented, detent: .medium) {
                sheetContent
            }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            // Large emoji header
            Text(emoji(for: reactionType))
                .font(.system(size: 56))
                .padding(.top, 28)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            Text(reactionTitle(for: reactionType))
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.bottom, 20)

            // Private note field
            VStack(alignment: .leading, spacing: 6) {
                TextField("Add a private note…", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(3...5)
                    .focused($isNoteFocused)
                    .onChange(of: noteText) { _, newValue in
                        if newValue.count > maxNoteLength {
                            noteText = String(newValue.prefix(maxNoteLength))
                        }
                    }
                    .padding(12)
                    .background { noteFieldBackground }
                    .accessibilityLabel("Private note")
                    .accessibilityHint("Maximum \(maxNoteLength) characters")

                HStack {
                    Spacer()
                    Text("\(noteText.count)/\(maxNoteLength)")
                        .font(.caption)
                        .foregroundStyle(
                            noteText.count >= maxNoteLength
                                ? Color.amenError
                                : AmenTheme.Colors.textTertiary
                        )
                        .accessibilityLabel("\(noteText.count) of \(maxNoteLength) characters used")
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Action row
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and close")

                Button {
                    let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSend(reactionType, trimmed)
                    isPresented = false
                } label: {
                    Text("Send")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(noteIsEmpty ? Color.secondary : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                                .fill(noteIsEmpty ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(Color.amenGold))
                        }
                }
                .buttonStyle(.plain)
                .disabled(noteIsEmpty)
                .accessibilityLabel("Send reaction with note")
                .accessibilityHint(noteIsEmpty ? "Enter a note to enable" : "Sends your reaction and private note")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .onAppear {
            isNoteFocused = true
        }
    }

    private var noteIsEmpty: Bool {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var noteFieldBackground: some View {
        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(LiquidGlassTokens.blurThin))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.75)
            }
    }

    // MARK: - Helpers

    private func emoji(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "❤️"
        case .laugh:   return "😂"
        case .prayer:  return "🙏"
        case .fire:    return "🔥"
        case .cross:   return "✝️"
        case .custom:  return "😊"
        }
    }

    private func reactionTitle(for type: MediaReactionType) -> String {
        switch type {
        case .heart:   return "Heart Reaction"
        case .laugh:   return "Laugh Reaction"
        case .prayer:  return "Prayer Reaction"
        case .fire:    return "Fire Reaction"
        case .cross:   return "Cross Reaction"
        case .custom:  return "Custom Reaction"
        }
    }
}
