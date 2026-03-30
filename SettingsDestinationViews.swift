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
        List {
            Section {
                ForEach(types, id: \.id) { type in
                    Button {
                        HapticManager.impact(style: .light)
                        accountType = type.id
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: type.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(accountType == type.id ? .blue : .secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(type.label)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                Text(type.description)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if accountType == type.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Account Type")
            } footer: {
                Text("Changing account type affects what features and analytics are available to you.")
            }
        }
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
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else if mutedUsers.isEmpty {
                ContentUnavailableView(
                    "No Muted Accounts",
                    systemImage: "speaker.slash",
                    description: Text("Accounts you mute won't appear in your feed.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(mutedUsers) { user in
                        HStack(spacing: 12) {
                            // Avatar
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(user.displayName.prefix(1)).uppercased())
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("@\(user.username)")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Unmute") {
                                unmute(userId: user.id)
                            }
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("\(mutedUsers.count) muted account\(mutedUsers.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Muted Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMutedUsers() }
    }

    private func loadMutedUsers() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        let db = Firestore.firestore()
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
        } catch {}
        isLoading = false
    }

    private func unmute(userId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        mutedUsers.removeAll { $0.id == userId }
        let db = Firestore.firestore()
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
        List {
            Section {
                Toggle("Filter from posts", isOn: $filterPosts)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
                Toggle("Filter from comments", isOn: $filterComments)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
            } header: {
                Text("Apply filters to")
            }

            Section {
                if hiddenWords.isEmpty {
                    Text("No words added yet")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hiddenWords, id: \.self) { word in
                        Text(word)
                            .font(.custom("OpenSans-Regular", size: 15))
                    }
                    .onDelete(perform: deleteWord)
                }

                Button {
                    showAddWord = true
                } label: {
                    Label("Add keyword or phrase", systemImage: "plus.circle.fill")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("Hidden words")
            } footer: {
                Text("Posts and comments containing these words will be hidden from your feed and comments.")
            }
        }
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
        let db = Firestore.firestore()
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
        List {
            Section {
                ForEach(options, id: \.0) { (id, label, description) in
                    Button {
                        HapticManager.impact(style: .light)
                        dmPermission = id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                Text(description)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if dmPermission == id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Who can message you") }

            Section {
                Toggle("Message requests", isOn: $messageRequestsEnabled)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
            } header: { Text("Message requests") } footer: {
                Text("People you don't follow will appear in Requests instead of your main inbox.")
            }
        }
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
        List {
            Section {
                Toggle(isOn: $showOnlineStatus) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show activity status")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Let others see when you were last active")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $showReadReceipts) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Read receipts")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Show when you've read messages")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $showTypingIndicator) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Typing indicator")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Show \"typing…\" in conversations")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Visibility") } footer: {
                Text("Turning off activity status also hides other people's status from you.")
            }
        }
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
        List {
            Section {
                ForEach(levels, id: \.id) { level in
                    Button {
                        HapticManager.impact(style: .light)
                        sensitiveContentLevel = level.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(level.label)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                Text(level.description)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sensitiveContentLevel == level.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Content level") } footer: {
                Text("AMEN is a faith-centered community. All content is held to our Community Guidelines regardless of this setting.")
            }
        }
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
        List {
            Section {
                Toggle("Quiet mode", isOn: $quietModeEnabled)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
            } header: { Text("Schedule") } footer: {
                if quietModeEnabled {
                    Text("Notifications will be silenced from \(formatted(quietModeStartHour)) to \(formatted(endHour)).")
                }
            }

            if quietModeEnabled {
                Section {
                    Stepper("Start: \(formatted(quietModeStartHour))", value: $quietModeStartHour, in: 0...23)
                        .font(.custom("OpenSans-Regular", size: 15))
                    Stepper("Duration: \(quietModeDuration) hr\(quietModeDuration == 1 ? "" : "s")", value: $quietModeDuration, in: 1...12)
                        .font(.custom("OpenSans-Regular", size: 15))
                } header: { Text("Window") }
            }
        }
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
    @State private var isRequesting = false
    @State private var requested = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your data export will include:")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    ForEach(["Posts and testimonies", "Comments and replies", "Messages (yours)", "Prayer entries", "Church notes", "Profile information", "Followed/following lists"], id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("What's included") }

            Section {
                Button {
                    guard !isRequesting else { return }
                    isRequesting = true
                    if let uid = Auth.auth().currentUser?.uid {
                        Firestore.firestore().collection("dataExportRequests").document(uid).setData([
                            "userId": uid,
                            "requestedAt": FieldValue.serverTimestamp(),
                            "status": "pending"
                        ], merge: true) { _ in
                            isRequesting = false
                            requested = true
                        }
                    }
                } label: {
                    if isRequesting {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    } else if requested {
                        Label("Request submitted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("Request Data Export")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(isRequesting || requested)
            } footer: {
                Text("You'll receive a secure download link by email within 72 hours.")
            }
        }
        .navigationTitle("Download Your Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Default Post Settings

struct DefaultPostSettingsView: View {
    @AppStorage("defaultReplyAudience") private var defaultReplyAudience: String = "everyone"
    @AppStorage("defaultAllowRepost") private var defaultAllowRepost: Bool = true
    @AppStorage("defaultCommentFilter") private var defaultCommentFilter: String = "standard"
    @AppStorage("holdCommentsForReview") private var holdCommentsForReview: Bool = false
    @AppStorage("slowModeSeconds") private var slowModeSeconds: Int = 0

    // Keyword blocklist — loaded from Firestore
    @State private var blockedKeywords: [String] = []
    @State private var showAddKeyword = false
    @State private var newKeyword = ""
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                Picker("Who can reply", selection: $defaultReplyAudience) {
                    Text("Everyone").tag("everyone")
                    Text("Followers").tag("followers")
                    Text("People I follow").tag("following")
                    Text("No one").tag("none")
                }
                .font(.custom("OpenSans-Regular", size: 15))
            } header: { Text("Default reply audience") }

            Section {
                Toggle("Allow reposts/shares", isOn: $defaultAllowRepost)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
            } header: { Text("Sharing") }

            // Comment safety controls
            Section {
                Picker("Comment filter level", selection: $defaultCommentFilter) {
                    Text("Off").tag("off")
                    Text("Standard").tag("standard")
                    Text("Strict").tag("strict")
                }
                .font(.custom("OpenSans-Regular", size: 15))

                Toggle(isOn: $holdCommentsForReview) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hold Comments for Review")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("New comments must be approved before they appear publicly")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
                .onChange(of: holdCommentsForReview) { _, enabled in
                    Task { await syncCommentApprovalSetting(enabled) }
                }
            } header: { Text("Comment safety") } footer: {
                Text("Standard filters obvious spam and harassment. Strict applies additional AI moderation.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            // Slow mode
            Section {
                Picker("Slow mode interval", selection: $slowModeSeconds) {
                    Text("Off").tag(0)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .onChange(of: slowModeSeconds) { _, val in
                    Task { await syncSlowMode(val) }
                }
            } header: { Text("Slow mode") } footer: {
                Text("Limits how often a single user can comment. Helps prevent spam in active discussions.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            // Keyword blocklist
            Section {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(blockedKeywords, id: \.self) { kw in
                        HStack {
                            Text(kw)
                                .font(.custom("OpenSans-Regular", size: 15))
                            Spacer()
                            Button {
                                removeKeyword(kw)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if blockedKeywords.isEmpty {
                        Text("No blocked keywords added yet")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showAddKeyword = true
                    } label: {
                        Label("Add keyword", systemImage: "plus.circle.fill")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.blue)
                    }
                }
            } header: { Text("Blocked comment keywords") } footer: {
                Text("Comments containing these words are automatically held for your review, regardless of the filter level above.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
        }
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

    // MARK: - Load / Save

    private func loadSettings() async {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        let db = Firestore.firestore()
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
        List {
            Section {
                // Use setEnabled() so the change persists to Firestore and syncs across devices
                Toggle(isOn: Binding(
                    get: { focusManager.isEnabled },
                    set: { focusManager.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shabbat Mode (Sundays)")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Restricts social features all day Sunday to encourage church focus. Church Notes and Find a Church remain available.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Feature") }

            Section {
                HStack {
                    Text("Active on")
                        .font(.custom("OpenSans-Regular", size: 15))
                    Spacer()
                    Text("Every Sunday")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Allowed features")
                        .font(.custom("OpenSans-Regular", size: 15))
                    Spacer()
                    Text("Church Notes, Find a Church")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                if focusManager.isInChurchFocusWindow && focusManager.isEnabled {
                    Label("Currently active", systemImage: "building.columns.fill")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.orange)
                }
            } header: { Text("Schedule") } footer: {
                Text("Shabbat Mode is ON by default. You can turn it off at any time. Changes sync across your devices.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
        }
        .navigationTitle("Shabbat Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Take a Break Reminders

struct TakeABreakSettingsView: View {
    @AppStorage("takeABreakEnabled") private var takeABreakEnabled: Bool = false
    @AppStorage("takeABreakInterval") private var intervalMinutes: Int = 30

    var body: some View {
        List {
            Section {
                Toggle("Take a break reminders", isOn: $takeABreakEnabled)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .tint(.blue)
            } header: { Text("Reminders") }

            if takeABreakEnabled {
                Section {
                    Picker("Remind me every", selection: $intervalMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .font(.custom("OpenSans-Regular", size: 15))
                } header: { Text("Interval") } footer: {
                    Text("A gentle nudge will appear after you've been scrolling for this long.")
                }
            }
        }
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
        List {
            Section {
                Toggle(isOn: $conciseMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Concise answers")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Shorter, focused responses by default")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $sourcesRequired) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Require scripture sources")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Berean will always cite a verse — never guess")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Response style") }

            Section {
                Toggle(isOn: $voiceEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allow voice input")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Use microphone for hands-free questions")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Voice") }

            Section {
                Toggle(isOn: $personalizationEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Personalize using my content")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Use your posts, prayers, and notes to tailor responses (opt-in)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Data usage") } footer: {
                Text("Your content is never used to train external models. Personalization runs on-device.")
            }
        }
        .navigationTitle("Berean AI")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Creator Insights View

struct CreatorInsightsView: View {
    var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Coming Soon",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Creator insights and analytics will be available in an upcoming update.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Insights & Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Drafts Settings

struct DraftsSettingsView: View {
    var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    "No Drafts",
                    systemImage: "doc.text",
                    description: Text("Save posts as drafts when composing to continue later.")
                )
                .listRowBackground(Color.clear)
            }
        }
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
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.0) { id, label in
                        Text(label).tag(id)
                    }
                }
                .font(.custom("OpenSans-Regular", size: 15))
            } header: { Text("What's the issue?") }

            Section {
                TextEditor(text: $description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .frame(minHeight: 120)
            } header: { Text("Description") } footer: {
                Text("Please describe what happened. Include steps to reproduce if it's a bug.")
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    } else if submitted {
                        Label("Submitted — thank you!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("Submit Report")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(isSubmitting || submitted || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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
        List {
            Section {
                HStack {
                    Text("System Reduce Motion")
                        .font(.custom("OpenSans-Regular", size: 15))
                    Spacer()
                    Text(systemReduceMotion ? "On" : "Off")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $reduceMotionOverride) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reduce motion (in-app)")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Replaces animations with simpler fades")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Motion") }

            Section {
                Toggle(isOn: $highContrastMode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("High contrast")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Increase text and UI contrast")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $hapticFeedback) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Haptic feedback")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Vibration feedback for buttons and actions")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Display & Input") }

            Section {
                NavigationLink("Text Size") {
                    TextSizeSettingsView()
                }
                .font(.custom("OpenSans-Regular", size: 15))
            } header: { Text("Text") }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TextSizeSettingsView: View {
    var body: some View {
        List {
            Section {
                Label("Text size follows your iOS Dynamic Type setting.", systemImage: "textformat.size")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open iOS Text Size Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.custom("OpenSans-SemiBold", size: 15))
            }
        }
        .navigationTitle("Text Size")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Captions & Alt Text Settings

struct CaptionsAltTextSettingsView: View {
    @AppStorage("autoCaptionsEnabled") private var autoCaptions: Bool = true
    @AppStorage("altTextPromptsEnabled") private var altTextPrompts: Bool = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $autoCaptions) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auto-captions on video")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Automatically show captions when available")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Video captions") }

            Section {
                Toggle(isOn: $altTextPrompts) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Prompt to add alt text")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Remind me to describe images when posting")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Images") } footer: {
                Text("Alt text makes your posts accessible to people using screen readers.")
            }
        }
        .navigationTitle("Captions & Alt Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Profile Visibility

struct ProfileVisibilitySettingsView: View {
    @AppStorage("showProfileInSearch") private var showProfileInSearch: Bool = true
    @AppStorage("showProfileInSuggestions") private var showProfileInSuggestions: Bool = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $showProfileInSearch) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Searchable profile")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Allow others to find your profile in search")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $showProfileInSuggestions) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Suggested profiles")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Allow your profile to appear in suggestions")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)
            } header: { Text("Discoverability") } footer: {
                Text("Control how others can discover your profile on AMEN.")
            }
        }
        .navigationTitle("Profile Visibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}
