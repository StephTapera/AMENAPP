import SwiftUI

struct ChurchNotesScriptureSection: View {
    @Binding var inputText: String
    @Binding var scriptureReferences: [String]
    let detected: [ChurchNoteScriptureReference]
    let suggested: [ChurchNoteScriptureReference]
    let onChanged: () -> Void

    @State private var selectedVersion = "WEB"
    private let bibleVersions = ["WEB", "KJV", "ASV"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
                    .frame(width: 42, height: 42)
                    .amenLiquidGlassCapsuleSurface(isSelected: false)
                    .accessibilityHidden(true)

                TextField("John 3:16, Romans 8, Psalm 23", text: $inputText)
                    .font(.systemScaled(16, weight: .regular))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addInput)

                Picker("Bible version", selection: $selectedVersion) {
                    ForEach(bibleVersions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .pickerStyle(.menu)
                .font(.systemScaled(14, weight: .semibold))
                .tint(ChurchNotesDesignTokens.Colors.personalTint)

                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: addInput) {
                        Image(systemName: "plus")
                            .font(.systemScaled(16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(ChurchNotesDesignTokens.Colors.personalTint, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach scripture reference")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .amenLiquidGlassCapsuleSurface(isSelected: false)

            if !scriptureReferences.isEmpty {
                TagWrapLayout(spacing: 6) {
                    ForEach(scriptureReferences, id: \.self) { ref in
                        chip(ref, removable: true)
                    }
                }
            }

            if !detected.isEmpty {
                suggestionRow(title: "Detected in note", refs: detected.map(\.reference))
            }

            if !suggested.isEmpty {
                suggestionRow(title: "Related suggestions", refs: suggested.map(\.reference))
            }
        }
    }

    private func chip(_ ref: String, removable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(ref)
                .font(.systemScaled(12, weight: .semibold))
                .lineLimit(1)
            Text(selectedVersion)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(.secondary)
            if removable {
                Button {
                    scriptureReferences.removeAll { $0 == ref }
                    onChanged()
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(8, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(ref)")
            }
        }
        .foregroundStyle(.primary.opacity(0.78))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .amenLiquidGlassCapsuleSurface(isSelected: false)
    }

    private func suggestionRow(title: String, refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.systemScaled(11, weight: .semibold))
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(refs, id: \.self) { ref in
                        if !scriptureReferences.contains(ref) {
                            Button {
                                scriptureReferences.append(ref)
                                onChanged()
                            } label: {
                                Label(ref, systemImage: "plus")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.78))
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .amenLiquidGlassCapsuleSurface(isSelected: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(ref)")
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
