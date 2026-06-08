import SwiftUI

struct ChurchNotesScriptureSection: View {
    @Binding var inputText: String
    @Binding var scriptureReferences: [String]
    let detected: [ChurchNoteScriptureReference]
    let suggested: [ChurchNoteScriptureReference]
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book")
                    .foregroundStyle(.tertiary)
                TextField("Add scripture", text: $inputText)
                    .onSubmit(addInput)
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: addInput) { Image(systemName: "plus.circle.fill") }
                }
            }
            .padding(12)
            .churchNotesGlassCard()

            if !scriptureReferences.isEmpty {
                TagWrapLayout(spacing: 6) {
                    ForEach(scriptureReferences, id: \.self) { ref in
                        chip(ref, removable: true)
                    }
                }
            }

            if !detected.isEmpty {
                suggestionRow(title: "Detected", refs: detected.map(\.reference))
            }

            if !suggested.isEmpty {
                suggestionRow(title: "Suggested", refs: suggested.map(\.reference))
            }
        }
    }

    private func chip(_ ref: String, removable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(ref).font(.systemScaled(12, weight: .medium))
            if removable {
                Button {
                    scriptureReferences.removeAll { $0 == ref }
                    onChanged()
                } label: { Image(systemName: "xmark").font(.systemScaled(8, weight: .bold)) }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func suggestionRow(title: String, refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.systemScaled(11, weight: .medium)).foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(refs, id: \.self) { ref in
                        if !scriptureReferences.contains(ref) {
                            Button {
                                scriptureReferences.append(ref)
                                onChanged()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus").font(.systemScaled(9, weight: .bold))
                                    Text(ref).font(.systemScaled(12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func addInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !scriptureReferences.contains(trimmed) else { return }
        scriptureReferences.append(trimmed)
        inputText = ""
        onChanged()
    }
}
