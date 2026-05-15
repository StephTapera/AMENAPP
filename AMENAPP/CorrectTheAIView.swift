import SwiftUI

struct CorrectTheAIView: View {
    let originalText: String
    let onSave: (AlignmentLens, String, Bool) -> Void
    let onApplyRewrite: (AlignmentLens) -> Void
    let onCancel: () -> Void

    @State private var selectedLens: AlignmentLens = .balancedBiblical
    @State private var correctionText = ""
    @State private var rememberPreference = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Guide Berean with your perspective.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.68))

                Picker("Lens", selection: $selectedLens) {
                    ForEach(AlignmentLens.allCases) { lens in
                        Text(lens.title).tag(lens)
                    }
                }
                .pickerStyle(.menu)

                TextEditor(text: $correctionText)
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                Toggle("Remember this preference for Berean", isOn: $rememberPreference)
                    .toggleStyle(.switch)

                HStack(spacing: 10) {
                    Button("Apply Rewrite") {
                        onApplyRewrite(selectedLens)
                    }
                    .buttonStyle(.bordered)

                    Button("Save Correction") {
                        onSave(selectedLens, correctionText, rememberPreference)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Correct the AI")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
