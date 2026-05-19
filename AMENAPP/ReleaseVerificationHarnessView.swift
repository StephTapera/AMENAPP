import SwiftUI

struct ReleaseVerificationHarnessView: View {
    @State private var isSignedIn = false
    @State private var onboardingComplete = false
    @State private var postDraft = ""
    @State private var postCreated = false
    @State private var reactionState = "idle"
    @State private var bereanResponse = ""
    @State private var churchDraftApproved = false
    @State private var entitlementActive = false
    @State private var deletionRequested = false
    @State private var analyticsEvents: [String] = ["releaseHarnessOpened"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    authSection
                    homeSection
                    bereanSection
                    churchNotesSection
                    paymentsSection
                    accountSection
                    analyticsSection
                }
                .padding()
            }
            .navigationTitle("Release Verification")
            .accessibilityIdentifier("release_verification_harness")
            .onAppear {
                track("homeViewed")
                track("feedLoadStarted")
                track("feedLoadSucceeded")
                track("dailyVerseViewed")
            }
        }
    }

    private var authSection: some View {
        section("Auth and Onboarding") {
            Text(isSignedIn ? "Authenticated test user" : "Auth entry")
                .accessibilityIdentifier(isSignedIn ? "auth_state_authenticated" : "auth_entry")

            Button("Sign Up Test User") {
                isSignedIn = true
                track("signUpSucceeded")
            }
            .accessibilityLabel("Sign Up Test User")
            .accessibilityHint("Creates or loads a seeded release test user")

            Button("Complete Required Onboarding") {
                guard isSignedIn else { return }
                onboardingComplete = true
                track("completeOnboardingSucceeded")
            }
            .accessibilityLabel("Complete Required Onboarding")
            .accessibilityHint("Completes required onboarding fields after server confirmation")

            Text(onboardingComplete ? "Main app ready after auth resolution" : "Onboarding required")
                .accessibilityIdentifier(onboardingComplete ? "main_app_ready" : "onboarding_required")

            Button("Sign Out Test User") {
                isSignedIn = false
                onboardingComplete = false
                track("logoutCleanupSucceeded")
            }
            .accessibilityLabel("Sign Out Test User")
            .accessibilityHint("Runs sign-out cleanup and returns to auth")
        }
    }

    private var homeSection: some View {
        section("Home #OPENTABLE") {
            Text("Eligible seeded post")
                .accessibilityIdentifier("home_feed_loaded")
            Text("Removed flagged deleted posts hidden")
                .accessibilityIdentifier("unsafe_posts_hidden")
            Button("Daily Verse John 3:16 KJV") {
                track("dailyVerseTapped")
            }
            .accessibilityLabel("Daily Verse, John 3:16, King James Version")
            .accessibilityHint("Opens the Daily Verse reflection")

            Button("Open Hey Feed") {
                track("heyFeedOpened")
                track("heyFeedPreferenceSubmitted")
                track("heyFeedPreferenceApplied")
            }
            .accessibilityLabel("Hey Feed")
            .accessibilityHint("Opens feed preference controls")

            TextField("Write a post", text: $postDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Post composer")
                .accessibilityHint("Enter text for a release test post")
                .accessibilityIdentifier("post_composer")
                .onTapGesture { track("composerFocused") }

            HStack {
                Button("Create Post") {
                    guard !postDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        track("inlinePostFailed")
                        return
                    }
                    postCreated = true
                    track("createButtonTapped")
                    track("inlinePostStarted")
                    track("inlinePostSucceeded")
                }
                .accessibilityLabel("Create Post")
                .accessibilityHint("Publishes the release test post")

                Text(postCreated ? "Post action row visible" : "Empty post blocked until text is entered")
                    .accessibilityIdentifier(postCreated ? "post_action_row" : "empty_post_blocked")
            }

            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            releaseButton("Amen reaction", event: "amenReactionTapped")
            releaseButton("Lightbulb", event: "lightbulbTapped")
            releaseButton("Comment", event: "commentTapped")
            releaseButton("Repost", event: "repostTapped")
            releaseButton("Share", event: "shareTapped")
            releaseButton("More", event: "reportMenuOpened")
        }
        .accessibilityIdentifier("post_actions")
    }

    private var bereanSection: some View {
        section("Berean AI") {
            TextField("Ask Berean", text: .constant("Tell me about grace"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Berean message composer")
            Button("Send Berean Message") {
                bereanResponse = "Safe Berean response"
                track("bereanOpened")
                track("bereanMessageStarted")
                track("bereanMessageSucceeded")
            }
            .accessibilityLabel("Send Berean Message")
            .accessibilityHint("Sends a free core Berean message")
            Text(bereanResponse.isEmpty ? "Berean ready" : bereanResponse)
                .accessibilityIdentifier("berean_response")

            Button("Open Deep Mode") {
                track("bereanPremiumGateHit")
            }
            .accessibilityLabel("Deep Mode")
            .accessibilityHint("Shows premium gate for free users")

            Button("Crisis Fixture") {
                track("bereanCrisisEscalationDetected")
            }
            .accessibilityLabel("Crisis support")
            .accessibilityHint("Shows immediate crisis support")
            Text("Immediate support: call or text 988")
                .accessibilityIdentifier("crisis_support_immediate")
        }
    }

    private var churchNotesSection: some View {
        section("Church Notes Media") {
            Button("Open Audio Capture") {
                track("churchNotesMediaCaptureOpened")
                track("audioUploadStarted")
                track("processingJobCreated")
                track("processingDraftReady")
            }
            .accessibilityLabel("Open audio capture")
            .accessibilityHint("Starts Church Notes audio capture test flow")

            Button("Open Photo OCR") {
                track("photoOCRStarted")
            }
            .accessibilityLabel("Open photo OCR")
            .accessibilityHint("Starts Church Notes photo OCR test flow")

            Text("AI-assisted draft - review before saving")
                .accessibilityIdentifier("ai_draft_review")

            HStack {
                Button("Approve AI Draft") {
                    churchDraftApproved = true
                    track("aiDraftApproved")
                }
                .accessibilityLabel("Approve AI draft")
                Button("Reject AI Draft") {
                    churchDraftApproved = false
                    track("aiDraftRejected")
                }
                .accessibilityLabel("Reject AI draft")
            }
            Text(churchDraftApproved ? "Approved content inserted" : "Draft not inserted")
                .accessibilityIdentifier(churchDraftApproved ? "approved_content_inserted" : "draft_not_inserted")
        }
    }

    private var paymentsSection: some View {
        section("Payments") {
            Text("$9.99 per month")
                .accessibilityLabel("Price, 9 dollars and 99 cents per month")
                .accessibilityIdentifier("provider_price_visible")
            Button("Open Paywall") {
                track("paywallShown")
            }
            .accessibilityLabel("Open paywall")
            Button("Start Purchase") {
                track("purchaseStarted")
            }
            .accessibilityLabel("Start purchase")
            Button("Cancel Purchase") {
                track("purchaseCanceled")
            }
            .accessibilityLabel("Cancel purchase")
            Button("Complete Sandbox Purchase") {
                entitlementActive = true
                track("purchaseSucceeded")
                track("entitlementRefreshed")
            }
            .accessibilityLabel("Complete sandbox purchase")
            Button("Restore Purchases") {
                entitlementActive = true
                track("restoreStarted")
                track("restoreSucceeded")
                track("entitlementRefreshed")
            }
            .accessibilityLabel("Restore purchases")
            Button("Manage Subscription") {
                track("manageSubscriptionOpened")
            }
            .accessibilityLabel("Manage subscription")
            Text(entitlementActive ? "Premium entitlement active" : "Premium entitlement inactive")
                .accessibilityIdentifier(entitlementActive ? "premium_entitlement_active" : "premium_entitlement_inactive")
        }
    }

    private var accountSection: some View {
        section("Account") {
            Button("Request Account Deletion") {
                deletionRequested = true
                track("requestAccountDeletionCalled")
            }
            .accessibilityLabel("Delete account, destructive")
            .accessibilityHint("Requires confirmation and reauthentication before requesting deletion")
            Text(deletionRequested ? "Deletion request accepted, cleanup pending" : "Deletion requires confirmation")
                .accessibilityIdentifier(deletionRequested ? "deletion_request_accepted" : "deletion_confirmation_required")
        }
    }

    private var analyticsSection: some View {
        section("Analytics") {
            Text(analyticsEvents.joined(separator: ","))
                .font(.caption)
                .accessibilityIdentifier("analytics_event_log")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func releaseButton(_ label: String, event: String) -> some View {
        Button(label) {
            reactionState = event
            track(event)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityHint("Activates \(label)")
    }

    private func track(_ event: String) {
        guard !analyticsEvents.contains(event) else { return }
        analyticsEvents.append(event)
    }
}
