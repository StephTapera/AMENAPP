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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
                    .frame(width: 24, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("John 3:16, Romans 8, Psalm 23", text: $inputText)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addInput)

                        Picker("Bible version", selection: $selectedVersion) {
                            ForEach(bibleVersions, id: \.self) { version in
                                Text(version).tag(version)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                    }

                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: addInput) {
                            Label("Attach reference", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(ChurchNotesDesignTokens.Colors.personalTint)
                    }
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
                suggestionRow(title: "Detected in note", refs: detected.map(\.reference))
            }

            if !suggested.isEmpty {
                suggestionRow(title: "Related suggestions", refs: suggested.map(\.reference))
            }
        }
    }

    private func chip(_ ref: String, removable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(ref)
                .font(.systemScaled(12, weight: .medium))
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(ChurchNotesDesignTokens.Colors.scriptureBlock.opacity(0.12)))
        .overlay(Capsule().strokeBorder(ChurchNotesDesignTokens.Colors.scriptureBlock.opacity(0.22), lineWidth: 0.5))
    }

    private func suggestionRow(title: String, refs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(refs, id: \.self) { ref in
                        if !scriptureReferences.contains(ref) {
                            Button {
                                scriptureReferences.append(ref)
                                onChanged()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.systemScaled(9, weight: .bold))
                                    Text(ref)
                                        .font(.systemScaled(12, weight: .medium))
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
