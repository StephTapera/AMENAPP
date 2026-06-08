import SwiftUI

struct ContactPrivateNotesView: View {
    let contactUID: String
    let contactDisplayName: String
    let onSave: (_ note: String, _ tags: [String]) async -> Void
    let onDismiss: () -> Void

    @State private var noteText: String = ""
    @State private var tagInput: String = ""
    @State private var tags: [String] = []
    @State private var isSaving: Bool = false

    @FocusState private var tagFieldFocused: Bool

    private var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "privateContactNotesEnabled") as? Bool) ?? true
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEnabled {
                    enabledContent
                } else {
                    disabledPlaceholder
                }
            }
            .navigationTitle("Private Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEnabled {
                        Button {
                            Task {
                                isSaving = true
                                await onSave(noteText, tags)
                                AMENAnalyticsService.shared.track(.commOSContactNoteSaved)
                                isSaving = false
                                onDismiss()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        .accessibilityLabel("Save private note")
                    }
                }
            }
        }
    }

    private var enabledContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacyDisclosure
                noteEditor
                tagSection
            }
            .padding(20)
        }
    }

    private var privacyDisclosure: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text("Only you can see these notes. \(contactDisplayName) cannot see this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Private note disclosure: only you can see these notes. \(contactDisplayName) cannot see this.")
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $noteText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Private note text editor")
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if !tags.isEmpty {
                tagChips
            }

            HStack(spacing: 8) {
                TextField("Add a tag…", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($tagFieldFocused)
                    .onSubmit { commitTag() }
                    .accessibilityLabel("Tag input field")

                if !tagInput.isEmpty {
                    Button("Add") { commitTag() }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Add tag")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 5) {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)

                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private var disabledPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Private notes are disabled")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enable this feature in Settings to take private notes about your contacts.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private notes are disabled. Enable this feature in Settings.")
    }

    private func commitTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            tagInput = ""
            return
        }
        tags.append(trimmed)
        tagInput = ""
    }
}
