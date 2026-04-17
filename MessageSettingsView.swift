//
//  MessageSettingsView.swift
//  AMENAPP
//
//  Comprehensive message settings UI with grouped sections
//  Notifications, Privacy, Safety, Personalization
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
    
    // Local state for editing
    @State private var settings: MessageSettings = .defaultSettings()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    }
                } else {
                    glassContent
                }
            }
        }
        .animation(.standardUI, value: isLoading)
        .navigationTitle("Message Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSettings()
        }
        .onChange(of: service.settings) { _, newSettings in
            settings = newSettings
        }
    }
    
    private var glassContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                notificationsSection
                privacySection
                safetySection
                personalizationSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Notifications Section
    
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Notifications")
            
            glassCard {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "Mute Unknown Senders",
                        description: "Silence notifications from people you don't follow",
                        isOn: Binding(
                            get: { settings.muteUnknownSenders },
                            set: { settings.muteUnknownSenders = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Message Requests",
                        description: "Get notified about new message requests",
                        isOn: Binding(
                            get: { settings.notifyForMessageRequests },
                            set: { settings.notifyForMessageRequests = $0; saveSettings() }
                        ),
                        disabled: settings.muteUnknownSenders
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Group Messages",
                        description: "Notifications for group conversations",
                        isOn: Binding(
                            get: { settings.notifyForGroupMessages },
                            set: { settings.notifyForGroupMessages = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Privacy")
            
            glassCard {
                VStack(spacing: 0) {
                    toggleRow(
                        title: "Read Receipts",
                        description: "Let others know when you've seen their messages",
                        isOn: Binding(
                            get: { settings.allowReadReceipts },
                            set: { settings.allowReadReceipts = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Typing Indicators",
                        description: "Show when you're typing a message",
                        isOn: Binding(
                            get: { settings.showTypingIndicators },
                            set: { settings.showTypingIndicators = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Activity Status",
                        description: "Let others see when you're active",
                        isOn: Binding(
                            get: { settings.showActivityStatus },
                            set: { settings.showActivityStatus = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    navigationRow(
                        title: "Who Can Send Requests",
                        value: settings.whoCanSendMessageRequests.displayName
                    ) {
                        showRequestPermissionPicker = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Safety")
            
            glassCard {
                VStack(spacing: 0) {
                    navigationRow(
                        title: "Safety Mode",
                        value: settings.safetyMode.displayName
                    ) {
                        showSafetyModePicker = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Filter Offensive Words",
                        description: "Hide messages containing offensive language",
                        isOn: Binding(
                            get: { settings.filterOffensiveWords },
                            set: { settings.filterOffensiveWords = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    navigationRow(
                        title: "Hidden Words",
                        value: settings.customHiddenWords.isEmpty ? "None" : "\(settings.customHiddenWords.count) words"
                    ) {
                        showHiddenWordsSheet = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Blur Sensitive Images",
                        description: "Blur potentially sensitive media until you tap to reveal",
                        isOn: Binding(
                            get: { settings.blurSensitiveImages },
                            set: { settings.blurSensitiveImages = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Hide Media from Unknown Senders",
                        description: "Don't show photos or videos from message requests",
                        isOn: Binding(
                            get: { settings.hideMediaFromUnknownSenders },
                            set: { settings.hideMediaFromUnknownSenders = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    toggleRow(
                        title: "Warn About Suspicious Links",
                        description: "Show a warning before opening untrusted links",
                        isOn: Binding(
                            get: { settings.warnAboutSuspiciousLinks },
                            set: { settings.warnAboutSuspiciousLinks = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Personalization")
            
            glassCard {
                VStack(spacing: 0) {
                    navigationRow(
                        title: "Chat Accent Color",
                        value: settings.chatAccentColor.displayName
                    ) {
                        showAccentColorPicker = true
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    pickerRow(
                        title: "Conversation Tint",
                        selection: Binding(
                            get: { settings.conversationTint },
                            set: { settings.conversationTint = $0; saveSettings() }
                        )
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    pickerRow(
                        title: "Message Appearance",
                        selection: Binding(
                            get: { settings.messageAppearance },
                            set: { settings.messageAppearance = $0; saveSettings() }
                        )
                    )
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
            .font(.systemScaled(15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }
    
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            }
    }
    
    private func toggleRow(title: String, description: String? = nil, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.systemScaled(16))
                    .foregroundStyle(disabled ? .white.opacity(0.4) : .white)
                
                if let description = description {
                    Text(description)
                        .font(.systemScaled(13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.white)
                .disabled(disabled)
        }
        .padding(16)
    }
    
    private func navigationRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.systemScaled(16))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(value)
                    .font(.systemScaled(15))
                    .foregroundStyle(.white.opacity(0.6))
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func pickerRow<T: CaseIterable & Hashable & RawRepresentable>(
        title: String,
        selection: Binding<T>
    ) -> some View where T.RawValue == String, T: CustomStringConvertible {
        VStack(spacing: 0) {
            Text(title)
                .font(.systemScaled(16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(String(describing: option))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(16)
        }
    }
    
    // MARK: - Permission Picker Sheet
    
    private func permissionPickerSheet(
        title: String,
        selected: Binding<MessageRequestPermission>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(MessageRequestPermission.allCases, id: \.self) { permission in
                            Button {
                                selected.wrappedValue = permission
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(permission.displayName)
                                            .font(.systemScaled(16, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        Text(permission.description)
                                            .font(.systemScaled(14))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                    
                                    if selected.wrappedValue == permission {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.systemScaled(20))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected.wrappedValue == permission ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                }
                            }
                            .buttonStyle(.plain)
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
                    .foregroundStyle(.white)
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
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(SafetyMode.allCases, id: \.self) { mode in
                            Button {
                                selected.wrappedValue = mode
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mode.displayName)
                                            .font(.systemScaled(16, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        Text(mode.description)
                                            .font(.systemScaled(14))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                    
                                    if selected.wrappedValue == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.systemScaled(20))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected.wrappedValue == mode ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                }
                            }
                            .buttonStyle(.plain)
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
                    .foregroundStyle(.white)
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
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ChatAccentColor.allCases, id: \.self) { color in
                            Button {
                                selected.wrappedValue = color
                                HapticManager.impact(style: .light)
                                dismiss()
                                onDismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(colorForAccent(color))
                                        .frame(width: 32, height: 32)
                                    
                                    Text(color.displayName)
                                        .font(.systemScaled(16))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    if selected.wrappedValue == color {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.systemScaled(20))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selected.wrappedValue == color ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                }
                            }
                            .buttonStyle(.plain)
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
                    .foregroundStyle(.white)
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
        
        do {
            try await service.loadSettings()
            settings = service.settings
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func saveSettings() {
        Task {
            do {
                try await service.saveSettings(settings)
            } catch {
                errorMessage = error.localizedDescription
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
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Add word field
                HStack(spacing: 12) {
                    TextField("Add word to hide", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.systemScaled(16))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
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
                            .font(.systemScaled(24))
                            .foregroundStyle(.white)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.3 : 1)
                }
                .padding(16)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Words list
                if hiddenWords.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.badge.minus")
                            .font(.systemScaled(40))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No hidden words")
                            .font(.systemScaled(16))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Words you add will be filtered from message requests")
                            .font(.systemScaled(14))
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(hiddenWords.enumerated()), id: \.offset) { index, word in
                                HStack {
                                    Text(word)
                                        .font(.systemScaled(15))
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Button {
                                        withAnimation(.standardUI) {
                                            hiddenWords.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.systemScaled(20))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .navigationTitle("Hidden Words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.white)
            }
        }
    }
    
    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !hiddenWords.contains(trimmed), hiddenWords.count < 100 else {
            return
        }
        
        withAnimation(.standardUI) {
            hiddenWords.append(trimmed)
        }
        
        newWord = ""
        HapticManager.impact(style: .light)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessageSettingsView()
    }
}
