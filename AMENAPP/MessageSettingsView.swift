//
//  MessageSettingsView.swift
//  AMENAPP
//
//  Comprehensive message settings UI matching app's design system
//  White background, black text, subtle liquid glass, grouped sections
//

import SwiftUI

struct MessageSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var service = MessageSettingsService.shared
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showHiddenWordsSheet = false
    @State private var showRequestPermissionPicker = false
    @State private var showCallPermissionPicker = false
    @State private var showSafetyModePicker = false
    @State private var showAccentColorPicker = false
    @State private var showErrorAlert = false
    
    // Local state for editing
    @State private var settings: MessageSettings = .defaultSettings()
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.black)
                        Text("Loading settings...")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                        Spacer()
                    }
                } else {
                    scrollContent
                }
            }
        }
        .animation(Motion.adaptive(.easeInOut(duration: 0.2)), value: isLoading)
        .navigationTitle("Message Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadSettings()
        }
        .onChange(of: service.settings) { _, newSettings in
            settings = newSettings
        }
        .alert("Error Loading Settings", isPresented: $showErrorAlert) {
            Button("Retry") {
                Task { await loadSettings() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }
    
    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                notificationsSection
                privacySection
                safetySection
                personalizationSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Notifications Section
    
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notifications")
            
            cardContainer {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "Mute Unknown Senders",
                        description: "Silence notifications from people you don't follow",
                        isOn: Binding(
                            get: { settings.muteUnknownSenders },
                            set: { settings.muteUnknownSenders = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Message Requests",
                        description: "Get notified about new message requests",
                        isOn: Binding(
                            get: { settings.notifyForMessageRequests },
                            set: { settings.notifyForMessageRequests = $0; saveSettings() }
                        ),
                        disabled: settings.muteUnknownSenders
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Group Messages",
                        description: "Notifications for group conversations",
                        isOn: Binding(
                            get: { settings.notifyForGroupMessages },
                            set: { settings.notifyForGroupMessages = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Calls",
                        description: "Ring when someone calls you",
                        isOn: Binding(
                            get: { settings.notifyForCalls },
                            set: { settings.notifyForCalls = $0; saveSettings() }
                        )
                    )
                }
            }
        }
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Privacy")
            
            cardContainer {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "Read Receipts",
                        description: "Let others know when you've seen their messages",
                        isOn: Binding(
                            get: { settings.allowReadReceipts },
                            set: { settings.allowReadReceipts = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Typing Indicators",
                        description: "Show when you're typing a message",
                        isOn: Binding(
                            get: { settings.showTypingIndicators },
                            set: { settings.showTypingIndicators = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Activity Status",
                        description: "Let others see when you're active",
                        isOn: Binding(
                            get: { settings.showActivityStatus },
                            set: { settings.showActivityStatus = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    navigationRow(
                        title: "Who Can Send Requests",
                        value: settings.whoCanSendMessageRequests.displayName
                    ) {
                        showRequestPermissionPicker = true
                    }
                    
                    rowDivider
                    
                    navigationRow(
                        title: "Who Can Call You",
                        value: settings.whoCanCallYou.displayName
                    ) {
                        showCallPermissionPicker = true
                    }
                }
            }
        }
        .sheet(isPresented: $showRequestPermissionPicker) {
            permissionPickerSheet(
                title: "Who Can Send Requests",
                selected: $settings.whoCanSendMessageRequests,
                onDismiss: { saveSettings() }
            )
        }
        .sheet(isPresented: $showCallPermissionPicker) {
            permissionPickerSheet(
                title: "Who Can Call You",
                selected: $settings.whoCanCallYou,
                onDismiss: { saveSettings() }
            )
        }
    }
    
    // MARK: - Safety Section
    
    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Safety")
            
            cardContainer {
                VStack(spacing: 0) {
                    navigationRow(
                        title: "Safety Mode",
                        value: settings.safetyMode.displayName
                    ) {
                        showSafetyModePicker = true
                    }
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Filter Offensive Words",
                        description: "Hide messages containing offensive language",
                        isOn: Binding(
                            get: { settings.filterOffensiveWords },
                            set: { settings.filterOffensiveWords = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    navigationRow(
                        title: "Hidden Words",
                        value: settings.customHiddenWords.isEmpty ? "None" : "\(settings.customHiddenWords.count) words"
                    ) {
                        showHiddenWordsSheet = true
                    }
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Blur Sensitive Images",
                        description: "Blur potentially sensitive media until you tap to reveal",
                        isOn: Binding(
                            get: { settings.blurSensitiveImages },
                            set: { settings.blurSensitiveImages = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Hide Media from Unknown Senders",
                        description: "Don't show photos or videos from message requests",
                        isOn: Binding(
                            get: { settings.hideMediaFromUnknownSenders },
                            set: { settings.hideMediaFromUnknownSenders = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Warn About Suspicious Links",
                        description: "Show a warning before opening untrusted links",
                        isOn: Binding(
                            get: { settings.warnAboutSuspiciousLinks },
                            set: { settings.warnAboutSuspiciousLinks = $0; saveSettings() }
                        )
                    )
                    
                    rowDivider
                    
                    toggleRow(
                        title: "Limit Repeat Requests",
                        description: "Block repeated unsolicited messages automatically",
                        isOn: Binding(
                            get: { settings.autoLimitRepeatRequests },
                            set: { settings.autoLimitRepeatRequests = $0; saveSettings() }
                        )
                    )
                }
            }
        }
        .sheet(isPresented: $showSafetyModePicker) {
            safetyModePickerSheet(
                selected: $settings.safetyMode,
                onDismiss: { saveSettings() }
            )
        }
        .sheet(isPresented: $showHiddenWordsSheet) {
            hiddenWordsSheet(
                words: $settings.customHiddenWords,
                onDismiss: { saveSettings() }
            )
        }
    }
    
    // MARK: - Personalization Section
    
    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Personalization")
            
            VStack(spacing: 12) {
                // Note: Simplified for consistency with app design
                cardContainer {
                    VStack(spacing: 0) {
                        navigationRow(
                            title: "Chat Accent Color",
                            value: settings.chatAccentColor.displayName
                        ) {
                            showAccentColorPicker = true
                        }
                    }
                }
                
                // Conversation Tint Card
                cardContainer {
                    VStack(spacing: 0) {
                        Text("Conversation Tint")
                            .font(AMENFont.medium(15))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        
                        Picker("Conversation Tint", selection: Binding(
                            get: { settings.conversationTint },
                            set: { settings.conversationTint = $0; saveSettings() }
                        )) {
                            ForEach(ConversationTint.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(16)
                    }
                }
                
                // Message Appearance Card
                cardContainer {
                    VStack(spacing: 0) {
                        Text("Message Appearance")
                            .font(AMENFont.medium(15))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        
                        Picker("Message Appearance", selection: Binding(
                            get: { settings.messageAppearance },
                            set: { settings.messageAppearance = $0; saveSettings() }
                        )) {
                            ForEach(MessageAppearance.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(16)
                    }
                }
            }
        }
        .sheet(isPresented: $showAccentColorPicker) {
            accentColorPickerSheet(
                selected: $settings.chatAccentColor,
                onDismiss: { saveSettings() }
            )
        }
    }
    
    // MARK: - Reusable Components
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AMENFont.medium(13))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
    
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.systemGray5), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
    }
    
    private var rowDivider: some View {
        Divider()
            .background(Color(.systemGray5))
            .padding(.leading, 16)
    }
    
    private func toggleRow(title: String, description: String? = nil, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(disabled ? .secondary : .primary)
                
                if let description = description {
                    Text(description)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 12)
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .disabled(disabled)
        }
        .padding(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
    
    private func navigationRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 12)
                
                Text(value)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Tap to change")
    }
    
    // MARK: - Permission Picker Sheet
    
    private func permissionPickerSheet(
        title: String,
        selected: Binding<MessageRequestPermission>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(MessageRequestPermission.allCases, id: \.self) { permission in
                            permissionOptionRow(permission: permission, selected: selected) {
                                selected.wrappedValue = permission
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Safety Mode Picker Sheet
    
    private func safetyModePickerSheet(
        selected: Binding<SafetyMode>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(SafetyMode.allCases, id: \.self) { mode in
                            safetyModeOptionRow(mode: mode, selected: selected) {
                                selected.wrappedValue = mode
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Safety Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Accent Color Picker Sheet
    
    private func accentColorPickerSheet(
        selected: Binding<ChatAccentColor>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ChatAccentColor.allCases, id: \.self) { color in
                            accentColorOptionRow(color: color, selected: selected) {
                                selected.wrappedValue = color
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Chat Accent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Hidden Words Sheet
    
    private func hiddenWordsSheet(
        words: Binding<[String]>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            HiddenWordsEditorView(hiddenWords: words)
        }
        .presentationDetents([.large])
        .onDisappear {
            onDismiss()
        }
    }
    
    // MARK: - Picker Option Rows
    
    private func permissionOptionRow(permission: MessageRequestPermission, selected: Binding<MessageRequestPermission>, action: @escaping () -> Void) -> some View {
        let isSelected = selected.wrappedValue == permission
        return Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.displayName)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Text(permission.description)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(22))
                        .foregroundStyle(.primary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.black : Color(.systemGray5),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func safetyModeOptionRow(mode: SafetyMode, selected: Binding<SafetyMode>, action: @escaping () -> Void) -> some View {
        let isSelected = selected.wrappedValue == mode
        return Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Text(mode.description)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(22))
                        .foregroundStyle(.primary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.black : Color(.systemGray5),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    private func accentColorOptionRow(color: ChatAccentColor, selected: Binding<ChatAccentColor>, action: @escaping () -> Void) -> some View {
        let isSelected = selected.wrappedValue == color
        return Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(colorForAccent(color))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(.systemGray5), lineWidth: 0.5)
                    }
                
                Text(color.displayName)
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(22))
                        .foregroundStyle(.primary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.black : Color(.systemGray5),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private func colorForAccent(_ accent: ChatAccentColor) -> Color {
        switch accent {
        case .amenRed: return Color(red: 0.82, green: 0.1, blue: 0.09)
        case .softBlue: return Color(red: 0.4, green: 0.6, blue: 0.85)
        case .forest: return Color(red: 0.2, green: 0.5, blue: 0.3)
        case .olive: return Color(red: 0.5, green: 0.5, blue: 0.35)
        case .warmGray: return Color(red: 0.6, green: 0.55, blue: 0.5)
        case .burgundy: return Color(red: 0.5, green: 0.13, blue: 0.13)
        case .gold: return Color(red: 0.85, green: 0.65, blue: 0.13)
        }
    }
    
    // MARK: - Data Operations
    
    private func loadSettings() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await service.loadSettings()
            settings = service.settings
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
            isLoading = false
            dlog("❌ [MessageSettings] Load error: \(error)")
        }
    }
    
    private func saveSettings() {
        Task {
            do {
                try await service.saveSettings(settings)
                dlog("✅ [MessageSettings] Settings saved successfully")
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                dlog("❌ [MessageSettings] Save error: \(error)")
            }
        }
    }
}

// MARK: - Hidden Words Editor View

struct HiddenWordsEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var hiddenWords: [String]
    @State private var newWord = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            contentView
        }
        .navigationTitle("Hidden Words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .font(AMENFont.bold(17))
                .foregroundStyle(.primary)
            }
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // Helper text
            VStack(alignment: .leading, spacing: 8) {
                Text("Words you add will be filtered from message requests and hidden from conversations.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground))
            
            Divider()
                .background(Color(.systemGray5))
            
            addWordField
                .padding(16)
                .background(Color(.systemBackground))

            Divider()
                .background(Color(.systemGray5))

            if hiddenWords.isEmpty {
                emptyStateView
            } else {
                wordsList
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.badge.minus")
                .font(.systemScaled(48))
                .foregroundStyle(.tertiary)
            Text("No hidden words")
                .font(AMENFont.bold(17))
                .foregroundStyle(.secondary)
            Text("Add words to filter from messages")
                .font(AMENFont.regular(14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wordsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(hiddenWords.indices, id: \.self) { index in
                    wordRow(at: index)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func wordRow(at index: Int) -> some View {
        let word = hiddenWords[index]
        return HStack {
            Text(word)
                .font(AMENFont.regular(16))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                removeWord(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.systemGray5), lineWidth: 0.5)
        }
    }

    private var addWordField: some View {
        HStack(spacing: 12) {
            TextField("Add word to hide", text: $newWord)
                .textFieldStyle(.plain)
                .font(AMENFont.regular(16))
                .foregroundStyle(.primary)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($isTextFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    addWord()
                }

            Button {
                addWord()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(28))
                    .foregroundStyle(.primary)
            }
            .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1)
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !hiddenWords.contains(trimmed), hiddenWords.count < 100 else {
            if hiddenWords.count >= 100 {
                HapticManager.notification(type: .warning)
            }
            return
        }

        withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) {
            hiddenWords.append(trimmed)
        }

        newWord = ""
        HapticManager.impact(style: .light)
    }

    private func removeWord(at index: Int) {
        _ = withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) {
            hiddenWords.remove(at: index)
        }
        HapticManager.impact(style: .light)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessageSettingsView()
    }
}
