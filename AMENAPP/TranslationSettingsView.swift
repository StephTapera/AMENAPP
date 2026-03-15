// TranslationSettingsView.swift
// AMEN App — Translation System
//
// Translation & Language settings screen.
// Embed in AccountSettingsView as a navigation link.

import SwiftUI

struct TranslationSettingsView: View {

    @ObservedObject private var settings = TranslationSettingsManager.shared
    @ObservedObject private var flags = TranslationFeatureFlags.shared

    @State private var showLanguagePicker = false
    @State private var showUnderstoodLanguagesPicker = false
    @State private var isSaving = false

    var body: some View {
        List {
            // MARK: - App Language
            Section {
                HStack {
                    Label("App Language", systemImage: "globe")
                    Spacer()
                    Text(SupportedLanguage.displayName(for: settings.preferences.appLanguage))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showLanguagePicker = true }
            } header: {
                Text("Language")
            } footer: {
                Text("This is the language you read and write in. AMEN uses this to offer translations when content is in a different language.")
            }

            // MARK: - Content Translation
            Section {
                Picker("Translation", selection: Binding(
                    get: { settings.preferences.contentTranslationMode },
                    set: { mode in Task { await settings.update(mode: mode) } }
                )) {
                    ForEach(ContentTranslationMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayLabel)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Content Translation")
            } footer: {
                Text("Controls how AMEN handles content written in languages different from your app language.")
            }

            // MARK: - Auto-Translate Toggles (visible only when mode = auto)
            if settings.preferences.contentTranslationMode == .auto {
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.preferences.autoTranslatePosts },
                        set: { val in Task { await settings.update(autoTranslatePosts: val) } }
                    )) {
                        Label("Auto-translate posts", systemImage: "doc.text")
                    }

                    Toggle(isOn: Binding(
                        get: { settings.preferences.autoTranslateComments },
                        set: { val in Task { await settings.update(autoTranslateComments: val) } }
                    )) {
                        Label("Auto-translate comments", systemImage: "bubble.left")
                    }

                    Toggle(isOn: Binding(
                        get: { settings.preferences.showOriginalAlongTranslation },
                        set: { val in Task { await settings.update(showOriginalAlongTranslation: val) } }
                    )) {
                        Label("Show original alongside translation", systemImage: "square.split.2x1")
                    }
                } header: {
                    Text("Auto-Translation Options")
                }
            }

            // MARK: - Languages I Understand
            Section {
                if settings.preferences.understoodLanguages.isEmpty {
                    Text("No additional languages added")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(settings.preferences.understoodLanguages, id: \.self) { code in
                        HStack {
                            Text(SupportedLanguage.displayName(for: code))
                            Spacer()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await settings.removeUnderstoodLanguage(code) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showUnderstoodLanguagesPicker = true
                } label: {
                    Label("Add language", systemImage: "plus.circle")
                }
            } header: {
                Text("Languages I Understand")
            } footer: {
                Text("Add languages you can read without translation. AMEN won't offer to translate content written in these languages.")
            }

            // MARK: - Privacy Note
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How translations work", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                    Text("Language detection happens on your device and is never sent anywhere. Translations for public content use Google Cloud Translation and are cached to improve performance. Private messages are not translated automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Translation & Language")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                title: "App Language",
                selectedCode: settings.preferences.appLanguage
            ) { code in
                Task { await settings.update(appLanguage: code) }
                showLanguagePicker = false
            }
        }
        .sheet(isPresented: $showUnderstoodLanguagesPicker) {
            LanguagePickerSheet(
                title: "Languages I Understand",
                selectedCode: nil,
                excludeCodes: settings.preferences.understoodLanguages
                    + [settings.preferences.appLanguage]
            ) { code in
                Task { await settings.addUnderstoodLanguage(code) }
                showUnderstoodLanguagesPicker = false
            }
        }
    }
}

// MARK: - Language Picker Sheet

struct LanguagePickerSheet: View {
    let title: String
    let selectedCode: String?
    var excludeCodes: [String] = []
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredLanguages: [SupportedLanguage] {
        SupportedLanguage.all
            .filter { !excludeCodes.contains($0.id) }
            .filter {
                searchText.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.nativeName.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        NavigationStack {
            List(filteredLanguages) { lang in
                Button {
                    onSelect(lang.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.displayName)
                                .foregroundStyle(.primary)
                            Text(lang.nativeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lang.id == selectedCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
