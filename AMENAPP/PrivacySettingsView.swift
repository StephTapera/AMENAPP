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
    @State private var sensitiveContentLevel: String = "standard"
    @State private var analyticsOptOut = AMENAnalyticsService.shared.isUserOptedOut

    // C-08: Prayer AI consent — controls whether prayer journal is processed by Anthropic AI
    @State private var consentPrayerAI = false

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

    private var db: Firestore { Firestore.firestore() }

    var body: some View {
        privacyScrollView
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

    // MARK: - Scroll View

    @ViewBuilder
    private var privacyScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: ACCOUNT PRIVACY
                Text("ACCOUNT PRIVACY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $isProfilePrivate) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Account")
                                .font(AMENFont.semiBold(15))
                            Text("Only approved followers can see your posts")
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

                // MARK: INTERACTIONS
                Text("INTERACTIONS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    audiencePicker(
                        label: "Who Can Comment",
                        subtitle: "Control who can comment on your posts",
                        selection: $whoCanComment
                    )
                    Divider().padding(.leading, 16)
                    audiencePicker(
                        label: "Who Can Mention You",
                        subtitle: "Control who can tag or mention you",
                        selection: $whoCanMention
                    )
                    Divider().padding(.leading, 16)
                    audiencePicker(
                        label: "Who Can Message You",
                        subtitle: "Control who can send you direct messages",
                        selection: $whoCanDM
                    )
                    Divider().padding(.leading, 16)
                    Toggle(isOn: $autoFilterSpamDMs) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Filter Spam Requests")
                                .font(AMENFont.semiBold(15))
                            Text("Move likely spam message requests to a separate folder")
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

                Text("Changing these settings takes effect immediately for new interactions")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: FOLLOWERS & FOLLOWING
                Text("FOLLOWERS & FOLLOWING")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $showFollowerCount) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Follower Count")
                                .font(AMENFont.semiBold(15))
                            Text("Others can see how many followers you have")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showFollowingCount) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Following Count")
                                .font(AMENFont.semiBold(15))
                            Text("Others can see how many people you follow")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showFollowersList) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Followers List")
                                .font(AMENFont.semiBold(15))
                            Text("Others can see who follows you")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showFollowingList) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Following List")
                                .font(AMENFont.semiBold(15))
                            Text("Others can see who you follow")
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

                Text("These settings control what others see on your profile. You can always see your own followers and following.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: ACTIVITY
                Text("ACTIVITY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $showOnlineStatus) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Online Status")
                                .font(AMENFont.semiBold(15))
                            Text("Let others see when you're active")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showActivityStatus) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show Activity Status")
                                .font(AMENFont.semiBold(15))
                            Text("Share what you're currently doing")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $showReadReceipts) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Read Receipts")
                                .font(AMENFont.semiBold(15))
                            Text("Let others know when you've read messages")
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

                Text("Changes to activity settings may take a few moments to apply")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: HIDDEN WORDS
                Text("HIDDEN WORDS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(hiddenWords, id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(AMENFont.regular(15))
                            Spacer()
                            Button(action: { removeWord(word) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)
                    }

                    Button(action: { showAddWordSheet = true }) {
                        Label("Add Word", systemImage: "plus.circle.fill")
                            .font(AMENFont.semiBold(15))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $hideFromUnfollowedOnly) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Only hide from people I don't follow")
                                .font(AMENFont.semiBold(15))
                            Text("Show content from people you follow even if it contains hidden words")
                                .font(AMENFont.regular(12))
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

                Text("Posts and comments containing these words will be filtered from your feed")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: CONTENT FILTERS
                Text("CONTENT FILTERS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Picker(selection: $sensitiveContentLevel) {
                        Text("Standard").tag("standard")
                        Text("Strict").tag("strict")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sensitive Content Filter")
                                .font(AMENFont.semiBold(15))
                            Text(sensitiveContentLevel == "strict"
                                 ? "Stricter filtering of sensitive or mature content"
                                 : "Default filtering of sensitive content")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
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

                Text("Affects what content appears in your feed and search results")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: DISCOVERY & FINDABILITY
                Text("DISCOVERY & FINDABILITY")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $showInDiscovery) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Show in People Discovery")
                                .font(AMENFont.semiBold(15))
                            Text("Allow others to find your profile in People Discovery")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: $findByPhoneOrEmail) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Find by Phone or Email")
                                .font(AMENFont.semiBold(15))
                            Text("Allow others to find you using your phone number or email address")
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

                Text("Turn these off to make your account harder to find by new users")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: CONTENT RECOMMENDATIONS
                Text("CONTENT RECOMMENDATIONS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: $personalizedRecommendations) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Personalized Recommendations")
                                .font(AMENFont.semiBold(15))
                            Text("Show posts and people based on your interests and activity")
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

                Text("When off, your feed shows posts in chronological order without personalization")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: ANALYTICS OPT-OUT
                Text("DATA & ANALYTICS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { analyticsOptOut },
                        set: { newValue in
                            analyticsOptOut = newValue
                            AMENAnalyticsService.shared.setAnalyticsOptOut(newValue)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opt Out of Analytics")
                                .font(AMENFont.semiBold(15))
                            Text("Disable usage analytics collection for your account")
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

                Text("You can opt out of analytics collection at any time. This does not affect your experience.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: PRAYER INSIGHTS AI — C-08
                Text("PRAYER INSIGHTS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { consentPrayerAI },
                        set: { newValue in
                            consentPrayerAI = newValue
                            Task { await savePrayerAIConsent(newValue) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prayer Insights AI")
                                .font(.body)
                            Text("Allow AI to analyze your prayer journal for weekly recaps. Content is processed by Anthropic AI.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "consentCreatorAI") },
                        set: { UserDefaults.standard.set($0, forKey: "consentCreatorAI") }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Creator AI Drafts")
                                .font(.body)
                            Text("Let Berean help draft posts and content for you")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().padding(.leading, 16)

                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "consentAIIndexingPersonalContent") },
                        set: { UserDefaults.standard.set($0, forKey: "consentAIIndexingPersonalContent") }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personal Content Indexing")
                                .font(.body)
                            Text("Allow AI to search your church notes and saved verses")
                                .font(.caption)
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

                Text("When enabled, your prayer journal entries are sent to Anthropic's AI to generate personalized weekly recaps. Disable at any time to stop AI processing.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // MARK: BLOCKED ACCOUNTS
                Text("BLOCKED ACCOUNTS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    NavigationLink(destination: BlockedUsersView()) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.red)
                            Text("Blocked Users")
                                .font(AMENFont.semiBold(15))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 52)

                    NavigationLink(destination: TrustLedgerSettingsView()) {
                        HStack {
                            Image(systemName: "shield.badge.clock")
                                .foregroundStyle(.blue)
                            Text("Your Safety History")
                                .font(AMENFont.semiBold(15))
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
                    .font(AMENFont.semiBold(15))
                Text(subtitle)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            }
        }
        .pickerStyle(.navigationLink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                    // C-08: Load prayer AI consent — defaults to false (opt-in, not opt-out)
                    consentPrayerAI             = data["consentPrayerAI"] as? Bool ?? false

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
            dlog("✅ Privacy settings saved successfully")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save privacy settings: \(error.localizedDescription)"
                isSaving = false
            }
            dlog("❌ Error saving privacy settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Prayer AI Consent (C-08)
    // Stored as a top-level field on the user document so Cloud Functions can read
    // it server-side before sending prayer text to Anthropic AI.
    private func savePrayerAIConsent(_ consent: Bool) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(userId).updateData([
                "consentPrayerAI":   consent,
                "privacyUpdatedAt":  FieldValue.serverTimestamp()
            ])
            dlog("✅ Prayer AI consent updated: \(consent)")
        } catch {
            dlog("❌ Error saving prayer AI consent: \(error.localizedDescription)")
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
                        .font(.systemScaled(50))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)

                    Text("Add Hidden Word")
                        .font(AMENFont.bold(24))

                    Text("Posts and comments containing this word will be filtered")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Word or Phrase")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.secondary)

                    TextField("Enter word or phrase", text: $newWord)
                        .font(AMENFont.regular(15))
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
                        .font(AMENFont.bold(16))
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
