//
//  PrivacySettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct PrivacySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    // Privacy Settings State
    @State private var isProfilePrivate = false
    @State private var allowMessagesFromAnyone = true
    @State private var showOnlineStatus = true
    @State private var allowTagging = true
    @State private var showReadReceipts = true
    @State private var allowCommentsOnPosts = true
    @State private var showActivityStatus = true
    
    // Loading & Error States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        List {
            // Account Privacy Section
            Section {
                Toggle(isOn: $isProfilePrivate) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Private Account")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Only approved followers can see your posts")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: {
                Text("ACCOUNT PRIVACY")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Interactions Section
            Section {
                Toggle(isOn: $allowMessagesFromAnyone) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Messages from Anyone")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Let anyone send you direct messages")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                
                Toggle(isOn: $allowTagging) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Tagging")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Others can tag you in their posts")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                
                Toggle(isOn: $allowCommentsOnPosts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Comments")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Let others comment on your posts")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: {
                Text("INTERACTIONS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Activity Status Section
            Section {
                Toggle(isOn: $showOnlineStatus) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Online Status")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Let others see when you're active")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                
                Toggle(isOn: $showActivityStatus) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Activity Status")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Share what you're currently doing")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                
                Toggle(isOn: $showReadReceipts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Read Receipts")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Let others know when you've read messages")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: {
                Text("ACTIVITY")
                    .font(.custom("OpenSans-Bold", size: 12))
            } footer: {
                Text("Changes to activity settings may take a few moments to apply")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
            
            // Blocked Users Section
            Section {
                NavigationLink(destination: BlockedUsersView()) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.red)
                        Text("Blocked Users")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                    }
                }
            } header: {
                Text("BLOCKED ACCOUNTS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .overlay {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Privacy settings updated successfully")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await loadPrivacySettings()
        }
        .onChange(of: isProfilePrivate) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: allowMessagesFromAnyone) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: showOnlineStatus) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: allowTagging) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: showReadReceipts) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: allowCommentsOnPosts) { _, _ in Task { await savePrivacySettings() } }
        .onChange(of: showActivityStatus) { _, _ in Task { await savePrivacySettings() } }
    }
    
    private func loadPrivacySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if let data = document.data() {
                await MainActor.run {
                    isProfilePrivate = data["isProfilePrivate"] as? Bool ?? false
                    allowMessagesFromAnyone = data["allowMessagesFromAnyone"] as? Bool ?? true
                    showOnlineStatus = data["showOnlineStatus"] as? Bool ?? true
                    allowTagging = data["allowTagging"] as? Bool ?? true
                    showReadReceipts = data["showReadReceipts"] as? Bool ?? true
                    allowCommentsOnPosts = data["allowCommentsOnPosts"] as? Bool ?? true
                    showActivityStatus = data["showActivityStatus"] as? Bool ?? true
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load privacy settings: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func savePrivacySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "isProfilePrivate": isProfilePrivate,
                "allowMessagesFromAnyone": allowMessagesFromAnyone,
                "showOnlineStatus": showOnlineStatus,
                "allowTagging": allowTagging,
                "showReadReceipts": showReadReceipts,
                "allowCommentsOnPosts": allowCommentsOnPosts,
                "showActivityStatus": showActivityStatus,
                "privacyUpdatedAt": FieldValue.serverTimestamp()
            ])
            
            await MainActor.run {
                isSaving = false
            }
            
            print("✅ Privacy settings saved successfully")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save privacy settings: \(error.localizedDescription)"
                isSaving = false
            }
            print("❌ Error saving privacy settings: \(error.localizedDescription)")
        }
    }
}



#Preview {
    NavigationStack {
        PrivacySettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
