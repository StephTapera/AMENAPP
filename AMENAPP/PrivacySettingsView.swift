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
    
    // Hidden Words Filter
    @State private var hiddenWords: [String] = []
    @State private var hideFromUnfollowedOnly = false
    @State private var showAddWordSheet = false
    @State private var newWord = ""
    
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
            
            // Hidden Words Filter Section
            Section {
                ForEach(hiddenWords, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.custom("OpenSans-Regular", size: 15))
                        Spacer()
                        Button(action: {
                            removeWord(word)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                Button(action: {
                    showAddWordSheet = true
                }) {
                    Label("Add Word", systemImage: "plus.circle.fill")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
                
                Toggle(isOn: $hideFromUnfollowedOnly) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Only hide from people I don't follow")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Show content from people you follow even if it contains hidden words")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: {
                Text("HIDDEN WORDS")
                    .font(.custom("OpenSans-Bold", size: 12))
            } footer: {
                Text("Posts and comments containing these words will be filtered from your feed")
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
        .sheet(isPresented: $showAddWordSheet) {
            AddHiddenWordSheet(hiddenWords: $hiddenWords, onSave: {
                Task { await savePrivacySettings() }
            })
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
        .onChange(of: hideFromUnfollowedOnly) { _, _ in Task { await savePrivacySettings() } }
    }
    
    private func removeWord(_ word: String) {
        hiddenWords.removeAll { $0 == word }
        Task { await savePrivacySettings() }
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
                    hiddenWords = data["hiddenWords"] as? [String] ?? []
                    hideFromUnfollowedOnly = data["hideFromUnfollowedOnly"] as? Bool ?? false
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
                "hiddenWords": hiddenWords,
                "hideFromUnfollowedOnly": hideFromUnfollowedOnly,
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

// MARK: - Add Hidden Word Sheet

struct AddHiddenWordSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var hiddenWords: [String]
    let onSave: () -> Void
    
    @State private var newWord = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)
                    
                    Text("Add Hidden Word")
                        .font(.custom("OpenSans-Bold", size: 24))
                    
                    Text("Posts and comments containing this word will be filtered")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Word or Phrase")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextField("Enter word or phrase", text: $newWord)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal)
                
                Button(action: {
                    addWord()
                }) {
                    Text("Add Word")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(newWord.isEmpty ? Color.gray : Color.blue)
                        )
                }
                .disabled(newWord.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Hidden Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Word Already Added", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This word is already in your hidden words list")
            }
        }
    }
    
    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !trimmed.isEmpty else { return }
        
        if hiddenWords.contains(where: { $0.lowercased() == trimmed }) {
            showError = true
            return
        }
        
        hiddenWords.append(trimmed)
        onSave()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
