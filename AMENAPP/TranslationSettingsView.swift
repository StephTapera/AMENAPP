// TranslationSettingsView.swift
// AMEN App — Translation System
//
// Translation & Language settings screen.
// Embed in AccountSettingsView as a navigation link.

import SwiftUI

struct TranslationSettingsView: View {

    @ObservedObject private var settings = TranslationSettingsManager.shared
    @ObservedObject private var flags = TranslationFeatureFlags.shared
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared

    @State private var showLanguagePicker = false
    @State private var showCreationLanguagePicker = false
    @State private var showUnderstoodLanguagesPicker = false
    @State private var showPerLanguagePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Section 1 — My Languages
                sectionHeader("MY LANGUAGES")

                settingsCard {
                    // App Language
                    Button(action: { showLanguagePicker = true }) {
                        settingsRow(
                            icon: "globe",
                            label: "App Language",
                            value: SupportedLanguage.displayName(for: settings.preferences.appLanguage)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Creation Language (gated behind feature flag)
                    if featureFlags.creationLanguageEnabled {
                        Divider().padding(.leading, 16)

                        Button(action: { showCreationLanguagePicker = true }) {
                            settingsRow(
                                icon: "pencil.line",
                                label: "Creation Language",
                                value: SupportedLanguage.displayName(
                                    for: settings.preferences.effectiveCreationLanguage
                                )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                sectionFooter("The language you read in. AMEN uses this to offer translations when content is in a different language.")

                // Languages I Understand
                sectionHeader("LANGUAGES I UNDERSTAND")

                settingsCard {
                    if settings.preferences.understoodLanguages.isEmpty {
                        Text("No additional languages added")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)
                    } else {
                        ForEach(settings.preferences.understoodLanguages, id: \.self) { code in
                            HStack {
                                Text(SupportedLanguage.displayName(for: code))
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Button {
                                    Task { await settings.removeUnderstoodLanguage(code) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }
                    }

                    Button {
                        showUnderstoodLanguagesPicker = true
                    } label: {
                        Label("Add language", systemImage: "plus.circle")
                            .font(AMENFont.semiBold(15))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                sectionFooter("AMEN won't offer to translate content written in these languages.")

                // MARK: Section 2 — Translation Behavior
                sectionHeader("TRANSLATION BEHAVIOR")

                settingsCard {
                    Picker("Translation", selection: Binding(
                        get: { settings.preferences.contentTranslationMode },
                        set: { mode in Task { await settings.update(mode: mode) } }
                    )) {
                        ForEach(ContentTranslationMode.allCases, id: \.self) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                sectionFooter(
                    settings.preferences.contentTranslationMode == .never
                    ? "Translation is turned off."
                    : settings.preferences.contentTranslationMode == .auto
                    ? "Content in other languages is translated automatically."
                    : "Tap \"See translation\" on posts in other languages."
                )

                // MARK: Section 3 — Translation Quality (gated)
                if flags.meaningAwareTranslationEnabled {
                    sectionHeader("TRANSLATION QUALITY")

                    settingsCard {
                        ForEach(TranslationMode.allCases, id: \.self) { mode in
                            if mode != .original || settings.preferences.defaultTranslationMode == .original {
                                // Show .original only if already selected (don't clutter default view)
                                if mode != TranslationMode.allCases.first {
                                    Divider().padding(.leading, 16)
                                }
                                translationModeRow(mode)
                            } else if mode == .original {
                                // Always show original as first option
                                translationModeRow(mode)
                            }
                        }
                    }

                    sectionFooter("Controls the default quality level for translations. Natural and Contextual modes use AI for more fluent results.")
                }

                // MARK: Section 4 — Auto-Translate Options
                if settings.preferences.contentTranslationMode == .auto {
                    sectionHeader("AUTO-TRANSLATE")

                    settingsCard {
                        Toggle(isOn: Binding(
                            get: { settings.preferences.autoTranslatePosts },
                            set: { val in Task { await settings.update(autoTranslatePosts: val) } }
                        )) {
                            Label("Posts & Testimonies", systemImage: "doc.text")
                                .font(AMENFont.semiBold(15))
                        }
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: Binding(
                            get: { settings.preferences.autoTranslateComments },
                            set: { val in Task { await settings.update(autoTranslateComments: val) } }
                        )) {
                            Label("Comments & Replies", systemImage: "bubble.left")
                                .font(AMENFont.semiBold(15))
                        }
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }

                    // Per-language auto-translate overrides
                    if featureFlags.perLanguageAutoTranslateEnabled {
                        sectionHeader("PER-LANGUAGE AUTO-TRANSLATE")

                        settingsCard {
                            let langs = settings.preferences.perLanguageAutoTranslate
                            if langs.isEmpty {
                                Text("No per-language rules")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                Divider().padding(.leading, 16)
                            } else {
                                ForEach(Array(langs.keys.sorted()), id: \.self) { code in
                                    HStack {
                                        Text(SupportedLanguage.displayName(for: code))
                                            .font(AMENFont.regular(15))
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { langs[code] ?? false },
                                            set: { val in
                                                Task { await settings.setPerLanguageAutoTranslate(languageCode: code, enabled: val) }
                                            }
                                        ))
                                        .labelsHidden()
                                        .tint(.blue)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                    Divider().padding(.leading, 16)
                                }
                            }

                            Button {
                                showPerLanguagePicker = true
                            } label: {
                                Label("Add language rule", systemImage: "plus.circle")
                                    .font(AMENFont.semiBold(15))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        sectionFooter("Always auto-translate content from these specific languages, even if global auto-translate is off for that content type.")
                    }
                }

                // MARK: Section 5 — Display
                sectionHeader("DISPLAY")

                settingsCard {
                    Toggle(isOn: Binding(
                        get: { settings.preferences.showOriginalAlongTranslation },
                        set: { val in Task { await settings.update(showOriginalAlongTranslation: val) } }
                    )) {
                        Label("Show original text", systemImage: "text.below.photo")
                            .font(AMENFont.semiBold(15))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if featureFlags.sideBySideTranslationEnabled {
                        Divider().padding(.leading, 16)

                        Toggle(isOn: Binding(
                            get: { settings.preferences.sideBySideEnabled },
                            set: { val in Task { await settings.update(sideBySideEnabled: val) } }
                        )) {
                            Label("Side-by-side view", systemImage: "square.split.2x1")
                                .font(AMENFont.semiBold(15))
                        }
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }

                sectionFooter("Show the original text alongside the translated version.")

                // MARK: Section 6 — Audio Narration
                // Always shown so users can discover and opt in.
                // The Listen pill only appears after they enable it inside AudioPreferencesView.
                sectionHeader("AUDIO")

                settingsCard {
                    NavigationLink {
                        AudioPreferencesView()
                    } label: {
                        settingsRow(
                            icon: "speaker.wave.2",
                            label: "Audio Narration",
                            value: "Speed, voice, pauses"
                        )
                    }
                }

                // MARK: - Privacy Note
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How translations work", systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                        Text("Language detection happens on your device and is never sent anywhere. Translations use Apple on-device translation and are cached to improve performance. Private messages are not translated automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Language & Translation")
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
        .sheet(isPresented: $showCreationLanguagePicker) {
            LanguagePickerSheet(
                title: "Creation Language",
                selectedCode: settings.preferences.effectiveCreationLanguage
            ) { code in
                Task { await settings.update(creationLanguage: code) }
                showCreationLanguagePicker = false
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
        .sheet(isPresented: $showPerLanguagePicker) {
            LanguagePickerSheet(
                title: "Add Language Rule",
                selectedCode: nil,
                excludeCodes: Array(settings.preferences.perLanguageAutoTranslate.keys)
                    + [settings.preferences.appLanguage]
                    + settings.preferences.understoodLanguages
            ) { code in
                Task { await settings.setPerLanguageAutoTranslate(languageCode: code, enabled: true) }
                showPerLanguagePicker = false
            }
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AMENFont.bold(11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.regular(12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func settingsRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func translationModeRow(_ mode: TranslationMode) -> some View {
        Button {
            Task { await settings.update(translationMode: mode) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.body)
                    .foregroundStyle(settings.preferences.defaultTranslationMode == mode ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayLabel)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if settings.preferences.defaultTranslationMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
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
