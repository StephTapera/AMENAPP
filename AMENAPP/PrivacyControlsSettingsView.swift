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
            ScrollView {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {

                        // MARK: - DIRECT MESSAGES
                        Text("DIRECT MESSAGES")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            // Who can message picker
                            Picker("Who can message you", selection: Binding(
                                get: { settings?.dmPermissionLevel ?? .mutualsOnly },
                                set: { newValue in
                                    settings?.dmPermissionLevel = newValue
                                    Task {
                                        guard let userId = Auth.auth().currentUser?.uid else { return }
                                        do {
                                            try await trustService.updateDMPermission(newValue, userId: userId)
                                        } catch {
                                            dlog("❌ Error updating DM permission: \(error)")
                                        }
                                    }
                                }
                            )) {
                                ForEach(DMPermissionLevel.allCases, id: \.self) { level in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(level.displayName)
                                            .font(AMENFont.semiBold(15))
                                        Text(level.description)
                                            .font(AMENFont.regular(12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(level)
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            Toggle("Hide links in message requests", isOn: Binding(
                                get: { settings?.hideLinksInRequests ?? true },
                                set: { newValue in
                                    settings?.hideLinksInRequests = newValue
                                    saveSettings()
                                }
                            ))
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            Toggle("Hide media in message requests", isOn: Binding(
                                get: { settings?.hideMediaInRequests ?? true },
                                set: { newValue in
                                    settings?.hideMediaInRequests = newValue
                                    saveSettings()
                                }
                            ))
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Message requests appear in a separate inbox. Links and media are hidden until you accept.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // MARK: - COMMENTS
                        Text("COMMENTS")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            Picker("Default comment permission", selection: Binding(
                                get: { settings?.defaultCommentPermission ?? .everyone },
                                set: { newValue in
                                    settings?.defaultCommentPermission = newValue
                                    Task {
                                        guard let userId = Auth.auth().currentUser?.uid else { return }
                                        do {
                                            try await trustService.updateCommentPermission(newValue, userId: userId)
                                        } catch {
                                            dlog("❌ Error updating comment permission: \(error)")
                                        }
                                    }
                                }
                            )) {
                                ForEach(CommentPermissionLevel.allCases, id: \.self) { level in
                                    Text(level.displayName)
                                        .tag(level)
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Who can comment on your posts by default. You can change this per-post.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // MARK: - MENTIONS
                        Text("MENTIONS")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            Picker("Who can mention you", selection: Binding(
                                get: { settings?.mentionPermissionLevel ?? .followersOnly },
                                set: { newValue in
                                    settings?.mentionPermissionLevel = newValue
                                    Task {
                                        guard let userId = Auth.auth().currentUser?.uid else { return }
                                        do {
                                            try await trustService.updateMentionPermission(newValue, userId: userId)
                                        } catch {
                                            dlog("❌ Error updating mention permission: \(error)")
                                        }
                                    }
                                }
                            )) {
                                ForEach(MentionPermissionLevel.allCases, id: \.self) { level in
                                    Text(level.displayName)
                                        .tag(level)
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Control who can @mention you in posts and comments.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // MARK: - ANTI-HARASSMENT
                        Text("ANTI-HARASSMENT")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            Toggle("Block repeated contact attempts", isOn: Binding(
                                get: { settings?.blockRepeatedMessageAttempts ?? true },
                                set: { newValue in
                                    settings?.blockRepeatedMessageAttempts = newValue
                                    saveSettings()
                                }
                            ))
                            .font(AMENFont.semiBold(15))
                            .tint(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            HStack {
                                Text("Auto-restrict after reports")
                                    .font(AMENFont.semiBold(15))
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)

                        Text("Automatically restrict users who repeatedly attempt contact after being blocked or who receive multiple reports.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        Spacer(minLength: 32)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Privacy & Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
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
            dlog("❌ Error loading privacy settings: \(error)")
            isLoading = false
        }
    }

    private func saveSettings() {
        guard let settings = settings else { return }

        Task {
            do {
                try await trustService.savePrivacySettings(settings)
                dlog("✅ Privacy settings saved")
            } catch {
                dlog("❌ Error saving privacy settings: \(error)")
            }
        }
    }
}

#Preview {
    PrivacyControlsSettingsView()
}
