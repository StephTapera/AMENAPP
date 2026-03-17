//
//  PrivacyControlsSettingsView.swift
//  AMENAPP
//
//  Trust-by-Design Privacy & Contact Controls Settings UI
//

import SwiftUI
import FirebaseAuth

struct PrivacyControlsSettingsView: View {
    @ObservedObject private var trustService = TrustByDesignService.shared
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = true
    @State private var settings: TrustPrivacySettings?
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else {
                    // DM Controls
                    Section {
                        Picker("Who can message you", selection: Binding(
                            get: { settings?.dmPermissionLevel ?? .mutualsOnly },
                            set: { newValue in
                                settings?.dmPermissionLevel = newValue
                                Task {
                                    guard let userId = Auth.auth().currentUser?.uid else { return }
                                    try await trustService.updateDMPermission(newValue, userId: userId)
                                }
                            }
                        )) {
                            ForEach(DMPermissionLevel.allCases, id: \.self) { level in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(level.displayName)
                                        .font(.custom("OpenSans-SemiBold", size: 15))
                                    Text(level.description)
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .tag(level)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        
                        Toggle("Hide links in message requests", isOn: Binding(
                            get: { settings?.hideLinksInRequests ?? true },
                            set: { newValue in
                                settings?.hideLinksInRequests = newValue
                                saveSettings()
                            }
                        ))
                        
                        Toggle("Hide media in message requests", isOn: Binding(
                            get: { settings?.hideMediaInRequests ?? true },
                            set: { newValue in
                                settings?.hideMediaInRequests = newValue
                                saveSettings()
                            }
                        ))
                    } header: {
                        Text("DIRECT MESSAGES")
                            .font(.custom("OpenSans-Bold", size: 12))
                    } footer: {
                        Text("Message requests appear in a separate inbox. Links and media are hidden until you accept.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                    
                    // Comment Controls
                    Section {
                        Picker("Default comment permission", selection: Binding(
                            get: { settings?.defaultCommentPermission ?? .everyone },
                            set: { newValue in
                                settings?.defaultCommentPermission = newValue
                                Task {
                                    guard let userId = Auth.auth().currentUser?.uid else { return }
                                    try await trustService.updateCommentPermission(newValue, userId: userId)
                                }
                            }
                        )) {
                            ForEach(CommentPermissionLevel.allCases, id: \.self) { level in
                                Text(level.displayName)
                                    .tag(level)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("COMMENTS")
                            .font(.custom("OpenSans-Bold", size: 12))
                    } footer: {
                        Text("Who can comment on your posts by default. You can change this per-post.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                    
                    // Mention Controls
                    Section {
                        Picker("Who can mention you", selection: Binding(
                            get: { settings?.mentionPermissionLevel ?? .followersOnly },
                            set: { newValue in
                                settings?.mentionPermissionLevel = newValue
                                Task {
                                    guard let userId = Auth.auth().currentUser?.uid else { return }
                                    try await trustService.updateMentionPermission(newValue, userId: userId)
                                }
                            }
                        )) {
                            ForEach(MentionPermissionLevel.allCases, id: \.self) { level in
                                Text(level.displayName)
                                    .tag(level)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("MENTIONS")
                            .font(.custom("OpenSans-Bold", size: 12))
                    } footer: {
                        Text("Control who can @mention you in posts and comments.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                    
                    // Anti-Harassment
                    Section {
                        Toggle("Block repeated contact attempts", isOn: Binding(
                            get: { settings?.blockRepeatedMessageAttempts ?? true },
                            set: { newValue in
                                settings?.blockRepeatedMessageAttempts = newValue
                                saveSettings()
                            }
                        ))
                        
                        HStack {
                            Text("Auto-restrict after reports")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Spacer()
                            Stepper(
                                "\(settings?.autoRestrictAfterReports ?? 3)",
                                value: Binding(
                                    get: { settings?.autoRestrictAfterReports ?? 3 },
                                    set: { newValue in
                                        settings?.autoRestrictAfterReports = newValue
                                        saveSettings()
                                    }
                                ),
                                in: 1...10
                            )
                        }
                    } header: {
                        Text("ANTI-HARASSMENT")
                            .font(.custom("OpenSans-Bold", size: 12))
                    } footer: {
                        Text("Automatically restrict users who repeatedly attempt contact after being blocked or who receive multiple reports.")
                            .font(.custom("OpenSans-Regular", size: 12))
                    }
                }
            }
            .navigationTitle("Privacy & Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .task {
                await loadSettings()
            }
        }
    }
    
    private func loadSettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await trustService.loadPrivacySettings(userId: userId)
            settings = trustService.userSettings
            isLoading = false
        } catch {
            print("❌ Error loading privacy settings: \(error)")
            isLoading = false
        }
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        Task {
            do {
                try await trustService.savePrivacySettings(settings)
                print("✅ Privacy settings saved")
            } catch {
                print("❌ Error saving privacy settings: \(error)")
            }
        }
    }
}

#Preview {
    PrivacyControlsSettingsView()
}
