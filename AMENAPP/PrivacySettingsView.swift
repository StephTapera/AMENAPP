//
//  PrivacySettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Audience Option

enum AudienceOption: String, CaseIterable, Identifiable {
    case everyone  = "everyone"
    case followers = "followers"
    case nobody    = "nobody"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone:  return "Everyone"
        case .followers: return "People You Follow"
        case .nobody:    return "No One"
        }
    }

    var icon: String {
        switch self {
        case .everyone:  return "globe"
        case .followers: return "person.2.fill"
        case .nobody:    return "xmark.circle.fill"
        }
    }
}

// MARK: - PrivacySettingsView

struct PrivacySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    // Account privacy
    @State private var isProfilePrivate = false

    // Granular audience controls (replaces legacy booleans)
    @State private var whoCanComment: AudienceOption = .everyone
    @State private var whoCanMention: AudienceOption = .everyone
    @State private var whoCanDM: AudienceOption = .everyone
    @State private var autoFilterSpamDMs = true

    // Activity
    @State private var showOnlineStatus = true
    @State private var showActivityStatus = true
    @State private var showReadReceipts = true

    // Discovery & Findability
    @State private var showInDiscovery = true
    @State private var findByPhoneOrEmail = false

    // Content preferences
    @State private var personalizedRecommendations = true
    @State private var sensitiveContentLevel: String = "standard" // "standard" | "strict"

    // Followers / Following visibility
    @State private var showFollowerCount = true
    @State private var showFollowingCount = true
    @State private var showFollowersList = true
    @State private var showFollowingList = true

    // Hidden Words Filter
    @State private var hiddenWords: [String] = []
    @State private var hideFromUnfollowedOnly = false
    @State private var showAddWordSheet = false

    // Loading & Error States
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        privacyList
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .overlay {
                if isLoading { ProgressView().scaleEffect(1.2) }
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
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
            .task { await loadPrivacySettings() }
            .modifier(PrivacyAutoSaveModifier(onSave: { Task { await savePrivacySettings() } },
                                              isProfilePrivate: isProfilePrivate,
                                              whoCanComment: whoCanComment,
                                              whoCanMention: whoCanMention,
                                              whoCanDM: whoCanDM,
                                              autoFilterSpamDMs: autoFilterSpamDMs,
                                              showOnlineStatus: showOnlineStatus,
                                              showActivityStatus: showActivityStatus,
                                              showReadReceipts: showReadReceipts,
                                              hideFromUnfollowedOnly: hideFromUnfollowedOnly,
                                              showInDiscovery: showInDiscovery,
                                              findByPhoneOrEmail: findByPhoneOrEmail,
                                              personalizedRecommendations: personalizedRecommendations,
                                              sensitiveContentLevel: sensitiveContentLevel))
            .modifier(PrivacyFollowVisibilityAutoSaveModifier(onSave: { Task { await savePrivacySettings() } },
                                              showFollowerCount: showFollowerCount,
                                              showFollowingCount: showFollowingCount,
                                              showFollowersList: showFollowersList,
                                              showFollowingList: showFollowingList))
    }

    // MARK: - List

    @ViewBuilder
    private var privacyList: some View {
        List {
            // ACCOUNT PRIVACY
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

            interactionsSection
            followersVisibilitySection
            activitySection
            hiddenWordsSection
            contentSection
            discoverySection
            recommendationsSection

            // BLOCKED ACCOUNTS
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
    }

    // MARK: - Interactions Section

    @ViewBuilder
    private var interactionsSection: some View {
        Section {
            // Who can comment
            audiencePicker(
                label: "Who Can Comment",
                subtitle: "Control who can comment on your posts",
                selection: $whoCanComment
            )

            // Who can mention/tag
            audiencePicker(
                label: "Who Can Mention You",
                subtitle: "Control who can tag or mention you",
                selection: $whoCanMention
            )

            // Who can DM
            audiencePicker(
                label: "Who Can Message You",
                subtitle: "Control who can send you direct messages",
                selection: $whoCanDM
            )

            // Auto-filter spam DM requests
            Toggle(isOn: $autoFilterSpamDMs) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Filter Spam Requests")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Move likely spam message requests to a separate folder")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

        } header: {
            Text("INTERACTIONS")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Changing these settings takes effect immediately for new interactions")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }

    // MARK: - Followers / Following Visibility Section

    @ViewBuilder
    private var followersVisibilitySection: some View {
        Section {
            Toggle(isOn: $showFollowerCount) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Follower Count")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Others can see how many followers you have")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            Toggle(isOn: $showFollowingCount) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Following Count")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Others can see how many people you follow")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            Toggle(isOn: $showFollowersList) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Followers List")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Others can see who follows you")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            Toggle(isOn: $showFollowingList) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Following List")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Others can see who you follow")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
        } header: {
            Text("FOLLOWERS & FOLLOWING")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("These settings control what others see on your profile. You can always see your own followers and following.")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }

    // MARK: - Activity Section

    @ViewBuilder
    private var activitySection: some View {
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
    }

    // MARK: - Hidden Words Section

    @ViewBuilder
    private var hiddenWordsSection: some View {
        Section {
            ForEach(hiddenWords, id: \.self) { word in
                HStack {
                    Text(word)
                        .font(.custom("OpenSans-Regular", size: 15))
                    Spacer()
                    Button(action: { removeWord(word) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            Button(action: { showAddWordSheet = true }) {
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
    }

    // MARK: - Sensitive Content Section

    @ViewBuilder
    private var contentSection: some View {
        Section {
            Picker(selection: $sensitiveContentLevel) {
                Text("Standard").tag("standard")
                Text("Strict").tag("strict")
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sensitive Content Filter")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text(sensitiveContentLevel == "strict"
                         ? "Stricter filtering of sensitive or mature content"
                         : "Default filtering of sensitive content")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("CONTENT FILTERS")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Affects what content appears in your feed and search results")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }

    // MARK: - Discovery Section

    @ViewBuilder
    private var discoverySection: some View {
        Section {
            Toggle(isOn: $showInDiscovery) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show in People Discovery")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Allow others to find your profile in People Discovery")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
            Toggle(isOn: $findByPhoneOrEmail) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find by Phone or Email")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Allow others to find you using your phone number or email address")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
        } header: {
            Text("DISCOVERY & FINDABILITY")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("Turn these off to make your account harder to find by new users")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }

    // MARK: - Recommendations Section

    @ViewBuilder
    private var recommendationsSection: some View {
        Section {
            Toggle(isOn: $personalizedRecommendations) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalized Recommendations")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Show posts and people based on your interests and activity")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
        } header: {
            Text("CONTENT RECOMMENDATIONS")
                .font(.custom("OpenSans-Bold", size: 12))
        } footer: {
            Text("When off, your feed shows posts in chronological order without personalization")
                .font(.custom("OpenSans-Regular", size: 12))
        }
    }

    // MARK: - Reusable Audience Picker Row

    @ViewBuilder
    private func audiencePicker(
        label: String,
        subtitle: String,
        selection: Binding<AudienceOption>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(AudienceOption.allCases) { option in
                Label(option.label, systemImage: option.icon)
                    .tag(option)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .pickerStyle(.navigationLink)
    }

    // MARK: - Helpers

    private func removeWord(_ word: String) {
        hiddenWords.removeAll { $0 == word }
        Task { await savePrivacySettings() }
    }

    // MARK: - Load

    private func loadPrivacySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        do {
            let document = try await db.collection("users").document(userId).getDocument()

            if let data = document.data() {
                await MainActor.run {
                    isProfilePrivate             = data["isProfilePrivate"] as? Bool ?? false
                    showOnlineStatus             = data["showOnlineStatus"] as? Bool ?? true
                    showReadReceipts             = data["showReadReceipts"] as? Bool ?? true
                    showActivityStatus           = data["showActivityStatus"] as? Bool ?? true
                    hiddenWords                  = data["hiddenWords"] as? [String] ?? []
                    hideFromUnfollowedOnly       = data["hideFromUnfollowedOnly"] as? Bool ?? false
                    showInDiscovery              = data["showInDiscovery"] as? Bool ?? true
                    findByPhoneOrEmail           = data["findByPhoneOrEmail"] as? Bool ?? false
                    personalizedRecommendations  = data["personalizedRecommendations"] as? Bool ?? true
                    autoFilterSpamDMs            = data["autoFilterSpamDMs"] as? Bool ?? true
                    sensitiveContentLevel        = data["sensitiveContentLevel"] as? String ?? "standard"
                    showFollowerCount            = data["showFollowerCount"] as? Bool ?? true
                    showFollowingCount           = data["showFollowingCount"] as? Bool ?? true
                    showFollowersList            = data["showFollowersList"] as? Bool ?? true
                    showFollowingList            = data["showFollowingList"] as? Bool ?? true

                    // Granular audience controls — migrate legacy booleans on first load
                    whoCanComment = AudienceOption(rawValue: data["whoCanComment"] as? String ?? "") ?? {
                        let legacy = data["allowCommentsOnPosts"] as? Bool ?? true
                        return legacy ? .everyone : .nobody
                    }()
                    whoCanMention = AudienceOption(rawValue: data["whoCanMention"] as? String ?? "") ?? {
                        let legacy = data["allowTagging"] as? Bool ?? true
                        return legacy ? .everyone : .nobody
                    }()
                    whoCanDM = AudienceOption(rawValue: data["whoCanDM"] as? String ?? "") ?? {
                        let legacy = data["allowMessagesFromAnyone"] as? Bool ?? true
                        return legacy ? .everyone : .followers
                    }()

                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load privacy settings: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - Save

    private func savePrivacySettings() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        await MainActor.run { isSaving = true }

        do {
            try await db.collection("users").document(userId).updateData([
                "isProfilePrivate":            isProfilePrivate,
                "whoCanComment":               whoCanComment.rawValue,
                "whoCanMention":               whoCanMention.rawValue,
                "whoCanDM":                    whoCanDM.rawValue,
                "autoFilterSpamDMs":           autoFilterSpamDMs,
                "showOnlineStatus":            showOnlineStatus,
                "showActivityStatus":          showActivityStatus,
                "showReadReceipts":            showReadReceipts,
                "hiddenWords":                 hiddenWords,
                "hideFromUnfollowedOnly":      hideFromUnfollowedOnly,
                "showInDiscovery":             showInDiscovery,
                "findByPhoneOrEmail":          findByPhoneOrEmail,
                "personalizedRecommendations": personalizedRecommendations,
                "sensitiveContentLevel":       sensitiveContentLevel,
                "showFollowerCount":           showFollowerCount,
                "showFollowingCount":          showFollowingCount,
                "showFollowersList":           showFollowersList,
                "showFollowingList":           showFollowingList,
                "privacyUpdatedAt":            FieldValue.serverTimestamp()
            ])
            await MainActor.run { isSaving = false }
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

                Button(action: { addWord() }) {
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
                    Button("Cancel") { dismiss() }
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

// MARK: - Auto-Save Modifier
// Breaks up the long onChange chain to help the Swift type-checker

// Split into two modifiers to keep each chain short enough for the Swift type-checker.

private struct PrivacyAutoSaveModifier: ViewModifier {
    let onSave: () -> Void

    // Tracked values (all Equatable)
    let isProfilePrivate: Bool
    let whoCanComment: AudienceOption
    let whoCanMention: AudienceOption
    let whoCanDM: AudienceOption
    let autoFilterSpamDMs: Bool
    let showOnlineStatus: Bool
    let showActivityStatus: Bool
    let showReadReceipts: Bool
    let hideFromUnfollowedOnly: Bool
    let showInDiscovery: Bool
    let findByPhoneOrEmail: Bool
    let personalizedRecommendations: Bool
    let sensitiveContentLevel: String

    func body(content: Content) -> some View {
        content
            .onChange(of: isProfilePrivate)           { _, _ in onSave() }
            .onChange(of: whoCanComment)              { _, _ in onSave() }
            .onChange(of: whoCanMention)              { _, _ in onSave() }
            .onChange(of: whoCanDM)                   { _, _ in onSave() }
            .onChange(of: autoFilterSpamDMs)          { _, _ in onSave() }
            .onChange(of: showOnlineStatus)           { _, _ in onSave() }
            .onChange(of: showActivityStatus)         { _, _ in onSave() }
            .onChange(of: showReadReceipts)           { _, _ in onSave() }
            .onChange(of: hideFromUnfollowedOnly)     { _, _ in onSave() }
            .onChange(of: showInDiscovery)            { _, _ in onSave() }
            .onChange(of: findByPhoneOrEmail)         { _, _ in onSave() }
            .onChange(of: personalizedRecommendations){ _, _ in onSave() }
            .onChange(of: sensitiveContentLevel)      { _, _ in onSave() }
    }
}

private struct PrivacyFollowVisibilityAutoSaveModifier: ViewModifier {
    let onSave: () -> Void
    let showFollowerCount: Bool
    let showFollowingCount: Bool
    let showFollowersList: Bool
    let showFollowingList: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: showFollowerCount)  { _, _ in onSave() }
            .onChange(of: showFollowingCount) { _, _ in onSave() }
            .onChange(of: showFollowersList)  { _, _ in onSave() }
            .onChange(of: showFollowingList)  { _, _ in onSave() }
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
            .environmentObject(AuthenticationViewModel())
    }
}
