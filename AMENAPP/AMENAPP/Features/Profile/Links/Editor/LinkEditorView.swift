import SwiftUI

// MARK: - LinkEditorView

/// Sheet for creating a new `LinkSlot` or editing an existing one.
/// Validates that the URL uses an http or https scheme before saving.
struct LinkEditorView: View {

    // MARK: Dependencies

    let store: ProfileLinksStore
    /// Pass an existing slot to edit; pass `nil` to create a new one.
    let existingSlot: LinkSlot?

    @Environment(\.dismiss) private var dismiss

    // MARK: Form State

    @State private var selectedType: LinkType
    @State private var urlText: String
    @State private var label: String
    @State private var showTypePicker = false
    @State private var isSaving = false
    @State private var saveError: String?

    // MARK: Init

    init(store: ProfileLinksStore, existingSlot: LinkSlot? = nil) {
        self.store = store
        self.existingSlot = existingSlot
        _selectedType = State(initialValue: existingSlot?.type ?? .website)
        _urlText     = State(initialValue: existingSlot?.url.absoluteString ?? "")
        _label       = State(initialValue: existingSlot?.label ?? (existingSlot?.type.defaultLabel ?? LinkType.website.defaultLabel))
    }

    // MARK: URL Validation

    private var parsedURL: URL? {
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              !(url.host ?? "").isEmpty
        else { return nil }
        return url
    }

    private var urlIsInvalid: Bool {
        !urlText.isEmpty && parsedURL == nil
    }

    private var canSave: Bool {
        parsedURL != nil && !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                // Type picker row
                Section("Type") {
                    Button {
                        showTypePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedType.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            Text(selectedType.displayName)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .accessibilityLabel("Link type: \(selectedType.displayName). Tap to change.")
                }

                // URL field
                Section {
                    TextField("https://example.com", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .trailing) {
                            if urlIsInvalid {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.red)
                                    .padding(.trailing, 4)
                            }
                        }
                } header: {
                    Text("URL")
                } footer: {
                    if urlIsInvalid {
                        Text("Enter a valid URL beginning with https:// or http://")
                            .foregroundStyle(Color.red)
                    }
                }
                .listRowBackground(
                    urlIsInvalid
                        ? Color.red.opacity(0.06)
                        : Color(uiColor: .secondarySystemGroupedBackground)
                )

                // Label field
                Section("Label") {
                    TextField("Label shown on your profile", text: $label)
                }

                // Error banner
                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(Color.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(existingSlot == nil ? "Add Link" : "Edit Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(!canSave)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showTypePicker) {
                LinkTypePickerView(selectedType: $selectedType)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedType) { _, newType in
                // Auto-fill label only if it still matches the previous default
                // (i.e. the user hasn't customised it).
                let previousDefault = existingSlot?.type.defaultLabel ?? selectedType.defaultLabel
                if label.isEmpty || label == previousDefault {
                    label = newType.defaultLabel
                }
            }
        }
    }

    // MARK: Save

    private func save() {
        guard let url = parsedURL else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        isSaving = true
        saveError = nil

        Task { [weak store] in
            guard let store else { return }
            do {
                if let existing = existingSlot {
                    let updated = LinkSlot(
                        id: existing.id,
                        type: selectedType,
                        url: url,
                        label: trimmedLabel,
                        order: existing.order
                    )
                    try await store.update(updated)
                } else {
                    let newSlot = LinkSlot(
                        type: selectedType,
                        url: url,
                        label: trimmedLabel,
                        order: store.slots.count
                    )
                    try await store.add(newSlot)
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Add") {
    let store = ProfileLinksStore(userId: "preview-user")
    LinkEditorView(store: store)
}
#Preview("Edit") {
    let store = ProfileLinksStore(userId: "preview-user")
    let slot = LinkSlot(
        id: "abc",
        type: .church,
        url: URL(string: "https://mychurch.com")!,
        label: "My Church",
        order: 0
    )
    LinkEditorView(store: store, existingSlot: slot)
}
#endif
