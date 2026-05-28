//
//  SettingsDestinationViews.swift
//  AMENAPP
//
//  All settings destination views that don't have their own dedicated file.
//  Includes: AccountType, MutedAccounts, HiddenWords, MessageControls,
//  ActivityStatus, SensitiveContent, QuietMode, ChangePassword, DownloadData,
//  LanguageSettings, DefaultPostSettings, SundayFocusMode, TakeABreak,
//  BereanAISettings, CreatorInsights, Drafts, ReportProblem, LegalDoc,
//  DeleteAccount, AccessibilitySettings, CaptionsAltText.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SafariServices

// MARK: - Account Type Settings

struct AccountTypeSettingsView: View {
    @AppStorage("accountType") private var accountType: String = "personal"
    @Environment(\.dismiss) var dismiss

    private let types: [(id: String, label: String, icon: String, description: String)] = [
        ("personal", "Personal", "person.fill", "For individuals sharing faith, reflections, and testimonies."),
        ("creator", "Creator", "megaphone.fill", "For content creators, pastors, and ministry voices."),
        ("organization", "Organization", "building.2.fill", "For churches, ministries, and faith-based organizations.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("ACCOUNT TYPE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                        Button {
                            HapticManager.impact(style: .light)
                            accountType = type.id
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: type.icon)
                                    .font(.systemScaled(18))
                                    .foregroundStyle(accountType == type.id ? .blue : .secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.label)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Text(type.description)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if accountType == type.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if index < types.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Changing account type affects what features and analytics are available to you.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Account Type")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Muted Accounts

struct MutedAccountsView: View {
    @State private var mutedUsers: [MutedUserEntry] = []
    @State private var isLoading = true

    struct MutedUserEntry: Identifiable {
        let id: String
        let displayName: String
        let username: String
        let profileImageURL: String?
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if mutedUsers.isEmpty {
                    ContentUnavailableView(
                        "No Muted Accounts",
                        systemImage: "speaker.slash",
                        description: Text("Accounts you mute won't appear in your feed.")
                    )
                    .padding(.top, 40)
                } else {
                    Text("\(mutedUsers.count) MUTED ACCOUNT\(mutedUsers.count == 1 ? "" : "S")")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(mutedUsers.indices, id: \.self) { index in
                            let user = mutedUsers[index]
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(String(user.displayName.prefix(1)).uppercased())
                                            .font(.systemScaled(18, weight: .semibold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(AMENFont.semiBold(15))
                                    Text("@\(user.username)")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Unmute") {
                                    unmute(userId: user.id)
                                }
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if index < mutedUsers.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Muted Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMutedUsers() }
    }

    private func loadMutedUsers() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        lazy var db = Firestore.firestore()
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let ids = doc.data()?["mutedUsers"] as? [String] ?? []
            var entries: [MutedUserEntry] = []
            for id in ids {
                if let userDoc = try? await db.collection("users").document(id).getDocument(),
                   let data = userDoc.data() {
                    entries.append(MutedUserEntry(
                        id: id,
                        displayName: data["displayName"] as? String ?? "User",
                        username: data["username"] as? String ?? id,
                        profileImageURL: data["profileImageURL"] as? String
                    ))
                }
            }
            mutedUsers = entries
        } catch {
            dlog("⚠️ [SettingsDestination] loadMutedUsers failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func unmute(userId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        mutedUsers.removeAll { $0.id == userId }
        lazy var db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "mutedUsers": FieldValue.arrayRemove([userId])
        ])
    }
}

// MARK: - Hidden Words & Filters

struct HiddenWordsSettingsView: View {
    @State private var hiddenWords: [String] = []
    @State private var filterPosts = true
    @State private var filterComments = true
    @State private var showAddWord = false
    @State private var newWord = ""
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Apply filters to section
                Text("APPLY FILTERS TO")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle("Filter from posts", isOn: $filterPosts)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle("Filter from comments", isOn: $filterComments)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // Hidden words section
                Text("HIDDEN WORDS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    if hiddenWords.isEmpty {
                        Text("No words added yet")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)
                    } else {
                        ForEach(Array(hiddenWords.enumerated()), id: \.element) { index, word in
                            Text(word)
                                .font(AMENFont.regular(15))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }
                        .onDelete { offsets in
                            deleteWord(at: offsets)
                        }
                    }

                    Button {
                        showAddWord = true
                    } label: {
                        Label("Add keyword or phrase", systemImage: "plus.circle.fill")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Posts and comments containing these words will be hidden from your feed and comments.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Hidden Words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("Add Word or Phrase", isPresented: $showAddWord) {
            TextField("e.g. politics, spoiler", text: $newWord)
                .autocorrectionDisabled()
            Button("Add") {
                let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !trimmed.isEmpty, !hiddenWords.contains(trimmed) {
                    hiddenWords.append(trimmed)
                    saveToFirestore()
                }
                newWord = ""
            }
            Button("Cancel", role: .cancel) { newWord = "" }
        }
        .task { await load() }
        .onChange(of: filterPosts) { _, _ in saveToFirestore() }
        .onChange(of: filterComments) { _, _ in saveToFirestore() }
    }

    private func deleteWord(at offsets: IndexSet) {
        hiddenWords.remove(atOffsets: offsets)
        saveToFirestore()
    }

    private func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        lazy var db = Firestore.firestore()
        let doc = try? await db.collection("users").document(uid).getDocument()
        hiddenWords = doc?.data()?["hiddenWords"] as? [String] ?? []
        filterPosts = doc?.data()?["hiddenWordFilterPosts"] as? Bool ?? true
        filterComments = doc?.data()?["hiddenWordFilterComments"] as? Bool ?? true
        isLoading = false
    }

    private func saveToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData([
            "hiddenWords": hiddenWords,
            "hiddenWordFilterPosts": filterPosts,
            "hiddenWordFilterComments": filterComments
        ], merge: true)
    }
}

// MARK: - Message Controls

struct MessageControlsSettingsView: View {
    @AppStorage("dmPermission") private var dmPermission: String = "everyone"
    @AppStorage("messageRequestsEnabled") private var messageRequestsEnabled: Bool = true

    private let options = [
        ("everyone", "Everyone", "All users can message you"),
        ("following", "People I follow", "Only people you follow can message"),
        ("followers", "Followers only", "Only your followers can message"),
        ("none", "No one", "Disable all direct messages")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("WHO CAN MESSAGE YOU")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.0) { index, option in
                        let (id, label, description) = option
                        Button {
                            HapticManager.impact(style: .light)
                            dmPermission = id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(label)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Text(description)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if dmPermission == id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if index < options.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("MESSAGE REQUESTS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle("Message requests", isOn: $messageRequestsEnabled)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("People you don't follow will appear in Requests instead of your main inbox.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Message Controls")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Activity Status

struct ActivityStatusSettingsView: View {
    @AppStorage("showOnlineStatus") private var showOnlineStatus: Bool = true
    @AppStorage("showReadReceipts") private var showReadReceipts: Bool = true
    @AppStorage("showTypingIndicator") private var showTypingIndicator: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("VISIBILITY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $showOnlineStatus) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show activity status")
                                .font(AMENFont.semiBold(15))
                            Text("Let others see when you were last active")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showReadReceipts) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Read receipts")
                                .font(AMENFont.semiBold(15))
                            Text("Show when you've read messages")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showTypingIndicator) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Typing indicator")
                                .font(AMENFont.semiBold(15))
                            Text("Show \"typing…\" in conversations")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Turning off activity status also hides other people's status from you.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Activity Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sensitive Content

struct SensitiveContentSettingsView: View {
    @AppStorage("sensitiveContentLevel") private var sensitiveContentLevel: String = "standard"

    private let levels: [(id: String, label: String, description: String)] = [
        ("less", "Less", "Show fewer sensitive or mature topics in your feed."),
        ("standard", "Standard", "The default experience for your community."),
        ("more", "More", "You may see more mature or sensitive content where permitted.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("CONTENT LEVEL")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                        Button {
                            HapticManager.impact(style: .light)
                            sensitiveContentLevel = level.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(level.label)
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)
                                    Text(level.description)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if sensitiveContentLevel == level.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if index < levels.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("AMEN is a faith-centered community. All content is held to our Community Guidelines regardless of this setting.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Sensitive Content")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Quiet Mode

struct QuietModeSettingsView: View {
    @AppStorage("quietModeEnabled") private var quietModeEnabled: Bool = false
    @AppStorage("quietModeStartHour") private var quietModeStartHour: Int = 22
    @AppStorage("quietModeDuration") private var quietModeDuration: Int = 8

    var endHour: Int { (quietModeStartHour + quietModeDuration) % 24 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("SCHEDULE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle("Quiet mode", isOn: $quietModeEnabled)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                if quietModeEnabled {
                    Text("Notifications will be silenced from \(formatted(quietModeStartHour)) to \(formatted(endHour)).")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Text("WINDOW")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Stepper("Start: \(formatted(quietModeStartHour))", value: $quietModeStartHour, in: 0...23)
                            .font(AMENFont.regular(15))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Stepper("Duration: \(quietModeDuration) hr\(quietModeDuration == 1 ? "" : "s")", value: $quietModeDuration, in: 1...12)
                            .font(AMENFont.regular(15))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Quiet Mode")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: quietModeEnabled)
    }

    private func formatted(_ hour: Int) -> String {
        let h = hour % 24
        let period = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display):00 \(period)"
    }
}

// MARK: - Download Your Data

struct DownloadDataView: View {
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showError = false
    @State private var shareItem: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("WHAT'S INCLUDED")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your data export will include:")
                            .font(AMENFont.semiBold(15))
                        ForEach(["Posts and testimonies", "Comments and replies", "Messages (yours)", "Prayer entries", "Church notes", "Profile information", "Followed/following lists"], id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    Button {
                        guard !isExporting else { return }
                        Task { await requestExport() }
                    } label: {
                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView().tint(.primary)
                                Text("Preparing export…")
                                    .font(AMENFont.semiBold(15))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Label("Download My Data", systemImage: "arrow.down.circle")
                                .font(AMENFont.semiBold(15))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isExporting)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Text("Your data is exported immediately as a JSON file you can save or share.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Download Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { url in
            SettingsShareSheet(items: [url])
        }
        .alert("Export Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "An error occurred. Please try again.")
        }
    }

    private func requestExport() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let functions = Functions.functions(region: "us-central1")
            let result = try await functions.httpsCallable("exportUserData").call()

            guard let dict = result.data as? [String: Any] else {
                throw NSError(domain: "DataExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
            }

            let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
            let filename = "AMEN_data_export_\(Int(Date().timeIntervalSince1970)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)

            await MainActor.run { shareItem = url }
        } catch {
            await MainActor.run {
                exportError = error.localizedDescription
                showError = true
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct SettingsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Default Post Settings

struct DefaultPostSettingsView: View {
    @AppStorage("defaultReplyAudience") private var defaultReplyAudience: String = "everyone"
    @AppStorage("defaultAllowRepost") private var defaultAllowRepost: Bool = true
    @AppStorage("defaultCommentFilter") private var defaultCommentFilter: String = "standard"
    @AppStorage("holdCommentsForReview") private var holdCommentsForReview: Bool = false
    @AppStorage("slowModeSeconds") private var slowModeSeconds: Int = 0

    @State private var blockedKeywords: [String] = []
    @State private var showAddKeyword = false
    @State private var newKeyword = ""
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Default reply audience
                Text("DEFAULT REPLY AUDIENCE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker("Who can reply", selection: $defaultReplyAudience) {
                        Text("Everyone").tag("everyone")
                        Text("Followers").tag("followers")
                        Text("People I follow").tag("following")
                        Text("No one").tag("none")
                    }
                    .font(AMENFont.regular(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // Sharing
                Text("SHARING")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle("Allow reposts/shares", isOn: $defaultAllowRepost)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // Comment safety
                Text("COMMENT SAFETY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker("Comment filter level", selection: $defaultCommentFilter) {
                        Text("Off").tag("off")
                        Text("Standard").tag("standard")
                        Text("Strict").tag("strict")
                    }
                    .font(AMENFont.regular(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $holdCommentsForReview) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hold Comments for Review")
                                .font(AMENFont.semiBold(15))
                            Text("New comments must be approved before they appear publicly")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .onChange(of: holdCommentsForReview) { _, enabled in
                        Task { await syncCommentApprovalSetting(enabled) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Standard filters obvious spam and harassment. Strict applies additional AI moderation.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Slow mode
                Text("SLOW MODE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker("Slow mode interval", selection: $slowModeSeconds) {
                        Text("Off").tag(0)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                        Text("15 minutes").tag(900)
                    }
                    .font(AMENFont.regular(15))
                    .onChange(of: slowModeSeconds) { _, val in
                        Task { await syncSlowMode(val) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Limits how often a single user can comment. Helps prevent spam in active discussions.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Keyword blocklist
                Text("BLOCKED COMMENT KEYWORDS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(Array(blockedKeywords.enumerated()), id: \.element) { index, kw in
                            HStack {
                                Text(kw)
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Button {
                                    removeKeyword(kw)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }

                        if blockedKeywords.isEmpty {
                            Text("No blocked keywords added yet")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                            Divider().padding(.leading, 16)
                        }

                        Button {
                            showAddKeyword = true
                        } label: {
                            Label("Add keyword", systemImage: "plus.circle.fill")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Comments containing these words are automatically held for your review, regardless of the filter level above.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Default Post Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSettings() }
        .alert("Add Blocked Keyword", isPresented: $showAddKeyword) {
            TextField("e.g. spam, hate", text: $newKeyword)
                .autocorrectionDisabled()
            Button("Add") {
                let kw = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !kw.isEmpty, !blockedKeywords.contains(kw) {
                    blockedKeywords.append(kw)
                    Task { await saveKeywords() }
                }
                newKeyword = ""
            }
            Button("Cancel", role: .cancel) { newKeyword = "" }
        } message: {
            Text("Comments containing this word will be held for your review.")
        }
    }

    private func loadSettings() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        lazy var db = Firestore.firestore()
        let doc = try? await db.collection("users").document(uid).getDocument()
        let data = doc?.data()
        blockedKeywords = data?["commentBlockedKeywords"] as? [String] ?? []
        isLoading = false
    }

    private func saveKeywords() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["commentBlockedKeywords": blockedKeywords])
    }

    private func removeKeyword(_ kw: String) {
        blockedKeywords.removeAll { $0 == kw }
        Task { await saveKeywords() }
    }

    private func syncCommentApprovalSetting(_ enabled: Bool) async {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        try? await FirebaseFirestore.Firestore.firestore()
            .collection("users").document(uid)
            .updateData(["commentApproval": enabled ? "manual" : "auto"])
    }

    private func syncSlowMode(_ seconds: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["commentSlowModeSeconds": seconds])
    }
}

// MARK: - Sunday Focus Mode Settings (Shabbat Mode)

struct SundayFocusModeSettingsView: View {
    @ObservedObject private var focusManager = SundayChurchFocusManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("FEATURE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { focusManager.isEnabled },
                        set: { focusManager.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shabbat Mode (Sundays)")
                                .font(AMENFont.semiBold(15))
                            Text("Restricts social features all day Sunday to encourage church focus. Church Notes and Find a Church remain available.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("SCHEDULE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    HStack {
                        Text("Active on")
                            .font(AMENFont.regular(15))
                        Spacer()
                        Text("Every Sunday")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    HStack {
                        Text("Allowed features")
                            .font(AMENFont.regular(15))
                        Spacer()
                        Text("Church Notes, Find a Church")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if focusManager.isInChurchFocusWindow && focusManager.isEnabled {
                        Divider().padding(.leading, 16)

                        Label("Currently active", systemImage: "building.columns.fill")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Shabbat Mode is ON by default. You can turn it off at any time. Changes sync across your devices.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Shabbat Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Take a Break Reminders

struct TakeABreakSettingsView: View {
    @AppStorage("takeABreakEnabled") private var takeABreakEnabled: Bool = false
    @AppStorage("takeABreakInterval") private var intervalMinutes: Int = 30

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("REMINDERS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle("Take a break reminders", isOn: $takeABreakEnabled)
                        .font(AMENFont.semiBold(15))
                        .tint(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                if takeABreakEnabled {
                    Text("INTERVAL")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Picker("Remind me every", selection: $intervalMinutes) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("45 minutes").tag(45)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                        }
                        .font(AMENFont.regular(15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("A gentle nudge will appear after you've been scrolling for this long.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Take a Break")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.2), value: takeABreakEnabled)
    }
}

// MARK: - Berean AI Settings

struct BereanAISettingsView: View {
    @AppStorage("berean_concise_mode") private var conciseMode: Bool = true
    @AppStorage("berean_sources_required") private var sourcesRequired: Bool = true
    @AppStorage("berean_voice_enabled") private var voiceEnabled: Bool = false
    @AppStorage("berean_personalization") private var personalizationEnabled: Bool = false
    @AppStorage("berean_focus_topics") private var focusTopicsRaw: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("RESPONSE STYLE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $conciseMode) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Concise answers")
                                .font(AMENFont.semiBold(15))
                            Text("Shorter, focused responses by default")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $sourcesRequired) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Require scripture sources")
                                .font(AMENFont.semiBold(15))
                            Text("Berean will always cite a verse — never guess")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("VOICE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $voiceEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Allow voice input")
                                .font(AMENFont.semiBold(15))
                            Text("Use microphone for hands-free questions")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("DATA USAGE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $personalizationEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Personalize using my content")
                                .font(AMENFont.semiBold(15))
                            Text("Use your posts, prayers, and notes to tailor responses (opt-in)")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Your content is never used to train external models. Personalization runs on-device.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Berean AI")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Creator Insights View

struct CreatorInsightsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Coming Soon",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Creator insights and analytics will be available in an upcoming update.")
                )
                .padding(.top, 40)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Insights & Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Drafts Settings

struct DraftsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "No Drafts",
                    systemImage: "doc.text",
                    description: Text("Save posts as drafts when composing to continue later.")
                )
                .padding(.top, 40)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Report a Problem

struct ReportProblemView: View {
    @State private var category = "bug"
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var submitted = false

    private let categories = [
        ("bug", "Bug or crash"),
        ("content", "Harmful content"),
        ("account", "Account issue"),
        ("safety", "Safety concern"),
        ("other", "Other")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("WHAT'S THE ISSUE?")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.0) { id, label in
                            Text(label).tag(id)
                        }
                    }
                    .font(AMENFont.regular(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("DESCRIPTION")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    TextEditor(text: $description)
                        .font(AMENFont.regular(14))
                        .frame(minHeight: 120)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Please describe what happened. Include steps to reproduce if it's a bug.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity, alignment: .center)
                        } else if submitted {
                            Label("Submitted — thank you!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(AMENFont.semiBold(15))
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("Submit Report")
                                .font(AMENFont.semiBold(15))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isSubmitting || submitted || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .navigationTitle("Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        isSubmitting = true
        guard let uid = Auth.auth().currentUser?.uid else { isSubmitting = false; return }
        _ = try? await Firestore.firestore().collection("bugReports").addDocument(data: [
            "userId": uid,
            "category": category,
            "description": description,
            "submittedAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ])
        isSubmitting = false
        submitted = true
    }
}

// MARK: - Legal Doc View (WebView wrapper)

struct LegalDocView: View {
    let title: String
    let urlString: String

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                SafariViewWrapper(url: url)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Not available", systemImage: "doc.text")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SafariViewWrapper: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Accessibility Settings

struct AccessibilitySettingsView: View {
    @AppStorage("reduceMotionOverride") private var reduceMotionOverride: Bool = false
    @AppStorage("highContrastMode") private var highContrastMode: Bool = false
    @AppStorage("hapticFeedback") private var hapticFeedback: Bool = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("MOTION")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    HStack {
                        Text("System Reduce Motion")
                            .font(AMENFont.regular(15))
                        Spacer()
                        Text(systemReduceMotion ? "On" : "Off")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $reduceMotionOverride) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reduce motion (in-app)")
                                .font(AMENFont.semiBold(15))
                            Text("Replaces animations with simpler fades")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("DISPLAY & INPUT")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $highContrastMode) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("High contrast")
                                .font(AMENFont.semiBold(15))
                            Text("Increase text and UI contrast")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $hapticFeedback) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Haptic feedback")
                                .font(AMENFont.semiBold(15))
                            Text("Vibration feedback for buttons and actions")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("TEXT")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    NavigationLink(destination: TextSizeSettingsView()) {
                        HStack {
                            Text("Text Size")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TextSizeSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Label("Text size follows your iOS Dynamic Type setting.", systemImage: "textformat.size")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 24)

                VStack(spacing: 0) {
                    Button("Open iOS Text Size Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(AMENFont.semiBold(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Text Size")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Captions & Alt Text Settings

struct CaptionsAltTextSettingsView: View {
    @AppStorage("autoCaptionsEnabled") private var autoCaptions: Bool = true
    @AppStorage("altTextPromptsEnabled") private var altTextPrompts: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("VIDEO CAPTIONS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $autoCaptions) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto-captions on video")
                                .font(AMENFont.semiBold(15))
                            Text("Automatically show captions when available")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("IMAGES")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $altTextPrompts) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Prompt to add alt text")
                                .font(AMENFont.semiBold(15))
                            Text("Remind me to describe images when posting")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Alt text makes your posts accessible to people using screen readers.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Captions & Alt Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile Visibility

struct ProfileVisibilitySettingsView: View {
    @AppStorage("showProfileInSearch") private var showProfileInSearch: Bool = true
    @AppStorage("showProfileInSuggestions") private var showProfileInSuggestions: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("DISCOVERABILITY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $showProfileInSearch) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Searchable profile")
                                .font(AMENFont.semiBold(15))
                            Text("Allow others to find your profile in search")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showProfileInSuggestions) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Suggested profiles")
                                .font(AMENFont.semiBold(15))
                            Text("Allow your profile to appear in suggestions")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Control how others can discover your profile on AMEN.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Profile Visibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance Settings

struct DestinationAppearanceSettingsView: View {
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"

    private let schemes: [(id: String, label: String, icon: String)] = [
        ("system", "System Default", "iphone"),
        ("light", "Light", "sun.max"),
        ("dark", "Dark", "moon")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("COLOR SCHEME")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(schemes.enumerated()), id: \.element.id) { index, scheme in
                        Button {
                            HapticManager.impact(style: .light)
                            colorSchemePreference = scheme.id
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: scheme.icon)
                                    .font(.systemScaled(18))
                                    .foregroundStyle(colorSchemePreference == scheme.id ? .blue : .secondary)
                                    .frame(width: 28)
                                Text(scheme.label)
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if colorSchemePreference == scheme.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        if index < schemes.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Restart the app after changing the color scheme for it to take effect.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Storage & Data Settings

struct DestinationStorageDataSettingsView: View {
    @AppStorage("autoPlayVideos") private var autoPlayVideos: String = "wifi"
    @AppStorage("imageQuality") private var imageQuality: String = "high"
    @State private var cacheSize: String = "Calculating…"
    @State private var isClearing = false
    @State private var showClearConfirmation = false

    private let autoPlayOptions: [(String, String)] = [
        ("wifi", "Wi-Fi only"),
        ("always", "Always"),
        ("never", "Never")
    ]

    private let qualityOptions: [(String, String)] = [
        ("high", "High"),
        ("medium", "Medium"),
        ("low", "Low (saves data)")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("MEDIA")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker("Auto-play videos", selection: $autoPlayVideos) {
                        ForEach(autoPlayOptions, id: \.0) { id, label in
                            Text(label).tag(id)
                        }
                    }
                    .font(AMENFont.regular(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Picker("Image quality", selection: $imageQuality) {
                        ForEach(qualityOptions, id: \.0) { id, label in
                            Text(label).tag(id)
                        }
                    }
                    .font(AMENFont.regular(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("CACHE")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    HStack {
                        Text("Cached data")
                            .font(AMENFont.regular(15))
                        Spacer()
                        Text(cacheSize)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Button {
                        showClearConfirmation = true
                    } label: {
                        if isClearing {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("Clear Cache")
                                .font(AMENFont.semiBold(15))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .disabled(isClearing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("DATA EXPORT")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    NavigationLink(destination: DownloadDataView()) {
                        HStack {
                            Text("Download Your Data")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Storage & Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { cacheSize = await calculateCacheSize() }
        .confirmationDialog("Clear Cache", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) { Task { await clearCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached images and media will be reloaded on next view.")
        }
    }

    private func calculateCacheSize() async -> String {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let tmpURL = FileManager.default.temporaryDirectory
        var totalBytes: Int64 = 0
        for url in [cacheURL, tmpURL].compactMap({ $0 }) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            while let fileURL = enumerator.nextObject() as? URL {
                totalBytes += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    private func clearCache() async {
        isClearing = true
        if let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: cacheURL)
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
        cacheSize = await calculateCacheSize()
        isClearing = false
        HapticManager.notification(type: .success)
    }
}

// MARK: - Family Safety Settings

struct DestinationFamilySafetySettingsView: View {
    @AppStorage("familySafetyEnabled") private var familySafetyEnabled: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                Text("PARENTAL CONTROLS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $familySafetyEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Family Safety Mode")
                                .font(AMENFont.semiBold(15))
                            Text("Apply stricter content filters for younger users")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .onChange(of: familySafetyEnabled) { _, _ in HapticManager.impact(style: .light) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("CONTENT FILTERS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    NavigationLink(destination: SensitiveContentSettingsView()) {
                        HStack {
                            Text("Sensitive Content")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 16)

                    NavigationLink(destination: HiddenWordsSettingsView()) {
                        HStack {
                            Text("Hidden Words & Filters")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("SCREEN TIME")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    NavigationLink(destination: ScrollBudgetSettingsView()) {
                        HStack {
                            Text("Screen Time & Usage")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                Text("Family Safety Mode enables stricter moderation and links with AMEN's community guardian system.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Family Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}
