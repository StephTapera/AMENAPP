import SwiftUI

struct ChurchNotesHeaderView: View {
    let autosaveText: String
    let isSaving: Bool
    let canSave: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 2) {
                Text("Church Note")
                    .font(.system(size: 16, weight: .semibold))
                Text(autosaveText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onDone) {
                if isSaving { ProgressView().scaleEffect(0.8) }
                else { Text("Done") }
            }
            .disabled(!canSave || isSaving)
            .foregroundStyle(canSave ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .churchNotesGlassCard()
    }
}
