//
//  OnboardingView.swift
//  AMENAPP
//
//  Redesigned 5-screen onboarding experience.
//
//  Screen 1 — AppLaunchView (separate file)  →  Welcome / brand / CTAs
//  Screen 2 — ValuePropositionPage           →  Why AMEN is different
//  Screen 3 — AccountSetupPage               →  Profile photo + username
//  Screen 4 — PrivacySafetyPage              →  What we collect, why, permissions
//  Screen 5 — PersonalizationPage            →  Interests + completion
//
//  Visual language:  bold editorial type · liquid-glass cards · premium whitespace
//  Animation:        ONBStepTransition — used ONLY for onboarding step progression
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import UIKit
import Contacts

// Fix (secondary): centralized URLs so they're updated in one place
private enum AMENLinks {
    static let privacy = URL(string: "https://amenapp.com/privacy")!
    static let terms   = URL(string: "https://amenapp.com/terms")!
}

// MARK: - Onboarding Container

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @ObservedObject private var discoveryService = DiscoveryService.shared

    // P1 FIX: Persist onboarding step so force-quit resumes correctly
    @AppStorage("onboardingStep") private var step: Int = 0
    @State private var direction: TransitionDirection = .forward

    // Step 1 — account setup
    @State private var selectedProfileImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var usernameSuggestions: [String] = []

    // DOB
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var showDOBPicker = false

    // Step 2 — notifications toggle
    @State private var notificationsEnabled = true
    @State private var privateAccount       = false

    // Step 3 — interests
    @State private var selectedInterests: Set<String> = []

    // Step 3 — terms agreement (P0: explicit acceptance required)
    @State private var hasAgreedToTerms = false

    // Step 4 — contacts
    @State private var contactsAuthStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @State private var isLoadingContacts = false

    // Step 0 — social proof member count
    @State private var memberCount: Int? = nil

    // First post prompt (shown after onboarding completes)
    @State private var showFirstPostPrompt = false
    // Church sheet (from step 5)
    @State private var showFindChurch = false

    // Submission
    @State private var isSaving      = false
    @State private var saveError: String?
    @State private var showErrorAlert = false
    // Fix E: guard rapid double-taps from skipping multiple steps
    @State private var isAdvancing   = false

    enum TransitionDirection { case forward, backward }

    let totalSteps = 6  // steps 0-5 (AppLaunchView is step -1 outside this view)

    var body: some View {
        ZStack {
            ONB.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Progress bar ──────────────────────────────────────
                progressBar
                    .padding(.horizontal, ONB.pagePadding)
                    .padding(.top, 16)

                // ── Page content ──────────────────────────────────────
                ZStack {
                    switch step {
                    case 0:
                        ONBStepTransition(step: 0) { valuePropositionPage }
                    case 1:
                        ONBStepTransition(step: 1) { accountSetupPage }
                    case 2:
                        ONBStepTransition(step: 2) { privacySafetyPage }
                    case 3:
                        ONBStepTransition(step: 3) { personalizationPage }
                    case 4:
                        ONBStepTransition(step: 4) { followSuggestionsPage }
                    case 5:
                        ONBStepTransition(step: 5) { communityDiscoveryPage }
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { selectedProfileImage = img }
                }
            }
        }
        .onDisappear {
            // Cancel any in-flight username availability check so it doesn't
            // update @State after the view is torn down.
            usernameCheckTask?.cancel()
            usernameCheckTask = nil
        }
        .sheet(isPresented: $showFindChurch) {
            FindChurchView()
        }
        .sheet(isPresented: $showFirstPostPrompt) {
            ONBFirstPostSheet(isPresented: $showFirstPostPrompt)
        }
        .alert("Something went wrong", isPresented: $showErrorAlert) {
            Button("Try Again") { Task { await finishOnboarding() } }
            Button("Skip", role: .cancel) { authViewModel.completeOnboarding() }
        } message: {
            Text(saveError ?? "Please check your connection and try again.")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 0) {
            // Back button
            if step > 0 {
                Button {
                    advance(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(ONB.inkSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Spacer().frame(width: 36, height: 36)
            }

            Spacer()

            ONBPageDots(total: totalSteps, current: step)

            Spacer()

            // Skip button — visible on all optional steps; hidden only on the final step
            if step < totalSteps - 1 {
                Button {
                    advance(by: 1)
                } label: {
                    Text("Skip")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(ONB.inkTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 36)
                .transition(.opacity)
            } else {
                Spacer().frame(width: 36)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .frame(height: 44)
    }

    // MARK: - Step Advance

    private func advance(by delta: Int) {
        // Fix E: ignore rapid taps until current step animation settles (~0.5s)
        guard !isAdvancing else { return }
        isAdvancing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        direction = delta > 0 ? .forward : .backward
        withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.82))) {
            step = max(0, min(totalSteps - 1, step + delta))
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            isAdvancing = false
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 0: Value Proposition
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var valuePropositionPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                // Hero headline
                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "Built different.")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("AMEN is a social platform designed around your faith, not your attention.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 32)

                // Feature cards
                VStack(spacing: ONB.cardSpacing) {
                    valueCard(
                        icon: "hands.sparkles.fill",
                        color: Color(red: 0.35, green: 0.50, blue: 0.95),
                        title: "Prayer & Scripture",
                        body: "Share requests, pray for others, attach verses directly to posts. The Word is always central."
                    )
                    valueCard(
                        icon: "sparkles",
                        color: Color(red: 0.55, green: 0.30, blue: 0.90),
                        title: "Berean AI",
                        body: "Your scripture-grounded AI guide. Ask questions. Get answers rooted in the Bible, not the internet."
                    )
                    valueCard(
                        icon: "shield.checkered",
                        color: Color(red: 0.20, green: 0.62, blue: 0.45),
                        title: "Safer by Design",
                        body: "Content moderation, mutual-follow messaging, and community standards that protect your peace."
                    )
                    valueCard(
                        icon: "person.2.fill",
                        color: Color(red: 0.85, green: 0.48, blue: 0.18),
                        title: "Real Community",
                        body: "Connect with churches, find mentors, share testimonies — with people who share your values."
                    )
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 32)

                // Social proof (P1-4)
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(ONB.accent)
                    if let count = memberCount {
                        Text("\(count.formatted()) believers already here")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(ONB.inkSecondary)
                    } else {
                        Text("Thousands of believers already here")
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(ONB.inkSecondary)
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 24)

                // CTA
                ONBPrimaryButton(title: "Get Started") { advance(by: 1) }
                    .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            Task {
                let snap = try? await Firestore.firestore()
                    .collection("stats").document("global").getDocument()
                if let count = snap?.data()?["userCount"] as? Int {
                    await MainActor.run { memberCount = count }
                }
            }
        }
    }

    @ViewBuilder
    private func valueCard(icon: String, color: Color, title: String, body: String) -> some View {
        ONBGlassCard {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(ONB.inkPrimary)
                    Text(body)
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 1: Account Setup (Profile photo + username)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var accountSetupPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "Make it yours.")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("Add a photo and choose a username. You can always update these later.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 32)

                // Profile photo picker
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack {
                            // Avatar
                            Group {
                                if let img = selectedProfileImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    ZStack {
                                        ONB.accentSoft
                                        Image(systemName: "person.fill")
                                            .font(.systemScaled(38))
                                            .foregroundStyle(ONB.accent.opacity(0.5))
                                    }
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(ONB.glassBorder, lineWidth: 2))

                            // Camera badge
                            ZStack {
                                Circle().fill(ONB.inkPrimary).frame(width: 32, height: 32)
                                Image(systemName: "camera.fill")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 34, y: 34)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.bottom, 8)

                Text(selectedProfileImage == nil ? "Add a profile photo" : "Looking good!")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(ONB.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: selectedProfileImage == nil)

                Spacer().frame(height: 28)

                // Display name field (P1-5)
                ONBGlassCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DISPLAY NAME")
                            .font(.systemScaled(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ONB.inkTertiary)
                        TextField("Your name", text: $displayName)
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundStyle(ONB.inkPrimary)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 8)

                Text("This is what people see first — your @username is for mentions.")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 16)

                // Username field
                ONBGlassCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USERNAME")
                            .font(.systemScaled(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ONB.inkTertiary)

                        HStack(spacing: 10) {
                            Text("@")
                                .font(.systemScaled(18, weight: .medium))
                                .foregroundStyle(ONB.inkTertiary)

                            TextField("yourname", text: $username)
                                .font(.systemScaled(18, weight: .medium))
                                .foregroundStyle(ONB.inkPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: username) { _, v in scheduleUsernameCheck(v) }

                            Spacer()

                            // Availability indicator
                            Group {
                                if isCheckingUsername {
                                    AMENLoadingIndicator(color: ONB.inkTertiary, dotSize: 5, bounceHeight: 4)
                                } else if let avail = usernameAvailable {
                                    Image(systemName: avail ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.systemScaled(18))
                                        .foregroundStyle(avail ? Color.green : Color.red)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.30), value: usernameAvailable)
                        }

                        if let avail = usernameAvailable {
                            Text(avail ? "Username available" : "Already taken — try another")
                                .font(.systemScaled(12, weight: .regular))
                                .foregroundStyle(avail ? Color.green : Color.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: avail)
                        }

                        // Username suggestions (P1-3)
                        if usernameAvailable == false && !usernameSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Try one of these:")
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundStyle(ONB.inkTertiary)
                                HStack(spacing: 8) {
                                    ForEach(usernameSuggestions, id: \.self) { suggestion in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            username = suggestion
                                            scheduleUsernameCheck(suggestion)
                                        } label: {
                                            Text("@\(suggestion)")
                                                .font(.systemScaled(12, weight: .medium))
                                                .foregroundStyle(ONB.accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(ONB.accentSoft))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.22), value: usernameSuggestions.count)
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 12)

                Text("Your username is how others find and mention you in the community.")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 20)

                // Date of birth
                ONBGlassCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DATE OF BIRTH")
                            .font(.systemScaled(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ONB.inkTertiary)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
                                showDOBPicker.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.systemScaled(16, weight: .medium))
                                    .foregroundStyle(ONB.accent)

                                Text(birthDate, style: .date)
                                    .font(.systemScaled(17, weight: .medium))
                                    .foregroundStyle(ONB.inkPrimary)

                                Spacer()

                                Image(systemName: showDOBPicker ? "chevron.up" : "chevron.down")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(ONB.inkTertiary)
                                    .animation(.easeInOut(duration: 0.2), value: showDOBPicker)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDOBPicker {
                            DatePicker(
                                "",
                                selection: $birthDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 8)

                Text("Used to personalise your experience.")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 16)

                ONBPrimaryButton(title: "Continue", isEnabled: true) {
                    advance(by: 1)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func scheduleUsernameCheck(_ value: String) {
        usernameCheckTask?.cancel()
        let trimmed = value.lowercased().trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            usernameAvailable = nil
            isCheckingUsername = false
            usernameSuggestions = []
            return
        }
        isCheckingUsername = true
        usernameAvailable = nil
        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms debounce
            guard !Task.isCancelled else { return }
            do {
                let snap = try await Firestore.firestore()
                    .collection("users")
                    .whereField("username", isEqualTo: trimmed)
                    .limit(to: 1)
                    .getDocuments()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let available = snap.documents.isEmpty
                    usernameAvailable = available
                    isCheckingUsername = false
                    // P1-3: Generate suggestions when taken
                    if !available {
                        usernameSuggestions = Self.generateUsernameSuggestions(for: trimmed)
                    } else {
                        usernameSuggestions = []
                    }
                    let announcement = available
                        ? "@\(trimmed) is available"
                        : "@\(trimmed) is already taken"
                    UIAccessibility.post(notification: .announcement, argument: announcement)
                }
            } catch {
                await MainActor.run { isCheckingUsername = false }
            }
        }
    }

    private static func generateUsernameSuggestions(for base: String) -> [String] {
        let suffix = Int.random(in: 10...99)
        let candidates = [
            "\(base)_amen",
            "\(base)\(suffix)",
            "\(base).faith",
        ]
        // Return up to 3 distinct options, truncated to fit username limits
        return candidates.map { $0.prefix(30).lowercased().replacingOccurrences(of: ".", with: "_") }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 2: Privacy & Safety
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var privacySafetyPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "Your data,\nyour rules.")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("We only collect what makes AMEN better for you. Here's exactly what we use and why.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 24)

                // Safety promise strip
                HStack(spacing: 8) {
                    ForEach([
                        ("lock.fill",        "Encrypted"),
                        ("eye.slash.fill",   "No selling"),
                        ("hand.raised.fill", "Moderated"),
                    ], id: \.1) { icon, label in
                        HStack(spacing: 5) {
                            Image(systemName: icon).font(.systemScaled(10, weight: .semibold))
                            Text(label).font(.systemScaled(11, weight: .semibold))
                        }
                        .foregroundStyle(ONB.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(ONB.accentSoft))
                        .fixedSize()
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 20)

                // Data collection cards
                ONBGlassCard {
                    VStack(spacing: 0) {
                        privacyDividerRow(
                            icon: "person.fill",
                            category: "Account Information",
                            detail: "Name, email, username, date of birth",
                            why: "To create and secure your account, verify your age, and help others find you."
                        )
                        Divider().padding(.horizontal, 4)
                        privacyDividerRow(
                            icon: "doc.text.fill",
                            category: "Your Content",
                            detail: "Posts, prayers, notes, messages",
                            why: "To display in your feed and communities. Messages are end-to-end between you and recipients."
                        )
                        Divider().padding(.horizontal, 4)
                        privacyDividerRow(
                            icon: "bell.fill",
                            category: "Notification Token",
                            detail: "Device push token",
                            why: "To send prayer reminders, message alerts, and community notifications. You control what notifications you receive."
                        )
                        Divider().padding(.horizontal, 4)
                        privacyDividerRow(
                            icon: "chart.bar.fill",
                            category: "Usage Patterns",
                            detail: "Feature usage, crash reports",
                            why: "To improve app stability and understand which features serve your community best. Never shared with third parties."
                        )
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 16)

                // Account privacy toggle
                ONBGlassCard {
                    VStack(spacing: 14) {
                        ONBToggleRow(
                            icon: "lock.fill",
                            title: "Private Account",
                            description: "Only approved followers see your posts",
                            isOn: $privateAccount
                        )
                        Divider()
                        ONBToggleRow(
                            icon: "bell.badge.fill",
                            title: "Prayer & Community Alerts",
                            description: "Get notified when someone prays for you",
                            isOn: $notificationsEnabled
                        )
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 12)

                // Policy link
                HStack(spacing: 4) {
                    Text("Read our full")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(ONB.inkTertiary)
                    Link("Privacy Policy", destination: AMENLinks.privacy)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(ONB.accent)
                    Text("and")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(ONB.inkTertiary)
                    Link("Terms of Service", destination: AMENLinks.terms)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(ONB.accent)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 32)

                ONBPrimaryButton(title: "I Understand — Continue") {
                    advance(by: 1)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func privacyDividerRow(icon: String, category: String, detail: String, why: String) -> some View {
        ONBPrivacyRow(icon: icon, category: category, detail: detail, why: why)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 3: Personalization + Completion
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var personalizationPage: some View {
        let interests: [(String, String, Color)] = [
            ("hands.sparkles", "Prayer",          Color(red: 0.35, green: 0.50, blue: 0.95)),
            ("book.closed",    "Bible Study",     Color(red: 0.55, green: 0.30, blue: 0.90)),
            ("sparkles",       "Berean AI",       Color(red: 0.70, green: 0.25, blue: 0.88)),
            ("music.note",     "Worship",         Color(red: 0.90, green: 0.40, blue: 0.25)),
            ("building.columns","Church Life",    Color(red: 0.20, green: 0.55, blue: 0.80)),
            ("person.2",       "Community",       Color(red: 0.20, green: 0.62, blue: 0.45)),
            ("star.fill",      "Testimonies",     Color(red: 0.85, green: 0.65, blue: 0.18)),
            ("globe",          "Evangelism",      Color(red: 0.45, green: 0.62, blue: 0.30)),
            ("heart.text.square","Mental Health", Color(red: 0.75, green: 0.30, blue: 0.50)),
            ("lightbulb.fill", "Theology",        Color(red: 0.60, green: 0.35, blue: 0.20)),
        ]

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "What matters\nto you?")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("Choose a few interests and we'll personalize your feed. Skip if you prefer to explore first.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // P1-7: Algo training signal
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(ONB.accent)
                        Text("Your picks shape your For You feed — adjust anytime in Discover.")
                            .font(.systemScaled(12, weight: .regular))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 28)

                // Interest chips grid
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(interests, id: \.1) { (icon, label, color) in
                        ONBInterestChip(
                            icon: icon,
                            label: label,
                            color: color,
                            selected: selectedInterests.contains(label)
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selectedInterests.contains(label) {
                                selectedInterests.remove(label)
                            } else {
                                selectedInterests.insert(label)
                            }
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 32)

                // Terms agreement checkbox (P0: explicit acceptance required)
                ONBGlassCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.72))) {
                            hasAgreedToTerms.toggle()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(hasAgreedToTerms ? ONB.accent : Color.clear)
                                    .frame(width: 22, height: 22)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        hasAgreedToTerms ? ONB.accent : ONB.inkRule,
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 22, height: 22)
                                if hasAgreedToTerms {
                                    Image(systemName: "checkmark")
                                        .font(.systemScaled(12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hasAgreedToTerms)

                            Group {
                                Text("I agree to AMEN's ") +
                                Text("Terms of Service").underline() +
                                Text(" and ") +
                                Text("Privacy Policy").underline() +
                                Text(".")
                            }
                            .font(.systemScaled(13, weight: .regular))
                            .foregroundStyle(ONB.inkSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 16)

                // Step 3 advances to follow suggestions; finishOnboarding runs at end of step 5
                ONBPrimaryButton(
                    title: "Continue",
                    isEnabled: hasAgreedToTerms
                ) {
                    advance(by: 1)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 4: Follow Suggestions (P1-1)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var followSuggestionsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "Find your\npeople.")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("Follow a few believers to seed your feed. You can always change who you follow later.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 24)

                // ── Contacts section ──────────────────────────────────
                contactsSection
                    .padding(.horizontal, ONB.pagePadding)

                if !discoveryService.contactSuggestions.isEmpty {
                    Spacer().frame(height: 8)
                }

                // ── Interest-based / quality suggestions ──────────────
                VStack(alignment: .leading, spacing: 10) {
                    if !selectedInterests.isEmpty {
                        Text("Based on your interests")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(ONB.inkTertiary)
                            .padding(.horizontal, ONB.pagePadding)
                            .padding(.top, discoveryService.contactSuggestions.isEmpty ? 0 : 16)
                    }

                    if discoveryService.isFollowSuggestionsLoading {
                        VStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { _ in ONBFollowSkeleton() }
                        }
                        .padding(.horizontal, ONB.pagePadding)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(discoveryService.followSuggestions.prefix(8)) { suggestion in
                                DiscoveryFollowCard(suggestion: suggestion) {
                                    Task {
                                        if suggestion.isFollowing {
                                            await discoveryService.unfollowUser(userId: suggestion.id)
                                        } else {
                                            await discoveryService.followUser(userId: suggestion.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, ONB.pagePadding)
                    }
                }

                Spacer().frame(height: 32)

                ONBPrimaryButton(title: "Continue") { advance(by: 1) }
                    .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Always reload with current interests when this step is shown
            Task { await discoveryService.loadOnboardingSuggestions(interests: Array(selectedInterests)) }
            // If contacts already authorized, load contact suggestions
            contactsAuthStatus = CNContactStore.authorizationStatus(for: .contacts)
            if contactsAuthStatus == .authorized {
                Task { await fetchAndLoadContacts() }
            }
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        switch contactsAuthStatus {
        case .notDetermined:
            // Invite banner to import contacts
            Button {
                Task { await requestContactsAccess() }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.50, blue: 0.95).opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundStyle(Color(red: 0.35, green: 0.50, blue: 0.95))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find friends from your contacts")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(ONB.inkPrimary)
                        Text("See who's already on AMEN")
                            .font(.systemScaled(12))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(ONB.inkTertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)

        case .authorized:
            if discoveryService.isContactSuggestionsLoading {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8)
                    Text("Finding friends…")
                        .font(.systemScaled(13))
                        .foregroundStyle(ONB.inkTertiary)
                }
                .padding(.vertical, 8)
            } else if !discoveryService.contactSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("From your contacts")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(ONB.inkTertiary)

                    ForEach(discoveryService.contactSuggestions.prefix(5)) { suggestion in
                        DiscoveryFollowCard(suggestion: suggestion) {
                            Task {
                                if suggestion.isFollowing {
                                    await discoveryService.unfollowUser(userId: suggestion.id)
                                } else {
                                    await discoveryService.followUser(userId: suggestion.id)
                                }
                            }
                        }
                    }
                }
            }
            // contacts authorized but no matches — show nothing (suggestions section fills space)

        default:
            // denied / restricted — no contacts UI shown
            EmptyView()
        }
    }

    // MARK: - Contacts Access

    private func requestContactsAccess() async {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            await MainActor.run {
                contactsAuthStatus = granted ? .authorized : .denied
            }
            if granted {
                await fetchAndLoadContacts()
            }
        } catch {
            await MainActor.run { contactsAuthStatus = .denied }
        }
    }

    private func fetchAndLoadContacts() async {
        let store = CNContactStore()
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var phoneNumbers: [String] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for phone in contact.phoneNumbers {
                    phoneNumbers.append(phone.value.stringValue)
                }
            }
        } catch {
            return
        }

        await discoveryService.loadContactSuggestions(phoneNumbers: phoneNumbers)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 5: Church/Community Discovery (P1-6)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var communityDiscoveryPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    ONBAnimatedHeadline(text: "Find your\nchurch.")
                        .foregroundStyle(ONB.inkPrimary)

                    Text("Connect with your church community on AMEN. You can skip this and find them later in Discover.")
                        .font(.systemScaled(17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 28)

                // Church CTA card
                Button { showFindChurch = true } label: {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [Color(red: 0.06, green: 0.14, blue: 0.28), Color(red: 0.10, green: 0.20, blue: 0.38)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "building.columns.fill")
                                .font(.systemScaled(32))
                                .foregroundStyle(.white.opacity(0.85))

                            Text("Find a Church")
                                .font(.systemScaled(20, weight: .bold))
                                .foregroundStyle(.white)

                            Text("Search churches by name, denomination, or zip code. Follow your church to see their posts, events and announcements.")
                                .font(.systemScaled(13, weight: .regular))
                                .foregroundStyle(.white.opacity(0.70))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                Text("Browse churches")
                                    .font(.systemScaled(13, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.white.opacity(0.18)))
                        }
                        .padding(20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 7)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 16)

                Text("Don't see your church yet? Invite them to join AMEN.")
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 40)

                // Final completion CTA
                ONBPrimaryButton(
                    title: "Enter AMEN",
                    isLoading: isSaving,
                    isEnabled: true
                ) {
                    Task { await finishOnboarding() }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Finish Onboarding

    private func finishOnboarding() async {
        guard !isSaving else { return }
        isSaving = true

        do {
            guard let userId = Auth.auth().currentUser?.uid else {
                isSaving = false
                return
            }
            lazy var db = Firestore.firestore()

            let birthYear = Calendar.current.component(.year, from: birthDate)
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            var updateData: [String: Any] = [
                "interests":            Array(selectedInterests),
                "isPrivate":            privateAccount,
                "notificationsEnabled": notificationsEnabled,
                "birthYear":            birthYear,
            ]
            if !trimmedDisplayName.isEmpty {
                updateData["displayName"] = trimmedDisplayName
                // Also update Firebase Auth display name
                let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                changeRequest?.displayName = trimmedDisplayName
                try? await changeRequest?.commitChanges()
            }

            // Fix B: re-query username availability at submit — never rely on stale local state.
            // The debounced check could be minutes old; another user may have taken the name since.
            let trimmedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
            if !trimmedUsername.isEmpty {
                let snap = try await db.collection("users")
                    .whereField("username", isEqualTo: trimmedUsername)
                    .limit(to: 1)
                    .getDocuments()
                guard snap.documents.isEmpty else {
                    await MainActor.run {
                        isSaving = false
                        saveError = "@\(trimmedUsername) was just taken. Please choose a different username."
                        showErrorAlert = true
                    }
                    return
                }
                updateData["username"] = trimmedUsername
            }

            // Fix D: treat image upload as a first-class failure — never silently omit the photo.
            if let img = selectedProfileImage {
                let userService = UserService()
                do {
                    let imageURL = try await userService.uploadProfileImage(img)
                    updateData["profileImageURL"] = imageURL
                } catch {
                    await MainActor.run {
                        isSaving = false
                        saveError = "Your profile photo couldn't be uploaded. Tap Try Again to retry, or Skip to continue without a photo."
                        showErrorAlert = true
                    }
                    return
                }
            }

            // setData(merge:true) handles both new and existing documents safely.
            // updateData() would throw if the document doesn't exist (e.g. social sign-in users).
            try await db.collection("users").document(userId).setData(updateData, merge: true)
            await MainActor.run {
                isSaving = false
                // Persist first-post prompt intent so ContentView can show it after
                // the onboarding transition completes. Setting showFirstPostPrompt here
                // is too early — completeOnboarding() immediately tears down this view.
                UserDefaults.standard.set(true, forKey: "showFirstPostPromptPending")
                // step reset is handled by completeOnboarding() via UserDefaults.removeObject
                authViewModel.completeOnboarding()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                saveError = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - First Post Welcome Sheet (P1-2)

struct ONBFirstPostSheet: View {
    @Binding var isPresented: Bool
    @State private var showComposer = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.35, green: 0.50, blue: 0.95), Color(red: 0.55, green: 0.30, blue: 0.90)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 72, height: 72)
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(appeared ? 1.0 : 0.5)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.70).delay(0.1), value: appeared)

                    Spacer().frame(height: 20)

                    Text("You're in. 🎉")
                        .font(.systemScaled(28, weight: .bold))
                        .foregroundStyle(.primary)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.spring(response: 0.45, dampingFraction: 0.78).delay(0.2), value: appeared)

                    Spacer().frame(height: 10)

                    Text("Your first post is a moment worth marking.\nWhat's on your heart today?")
                        .font(.systemScaled(16, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                    Spacer().frame(height: 36)

                    // Primary CTA
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showComposer = true
                    } label: {
                        Text("Share to AMEN")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 28)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.4), value: appeared)

                    Spacer().frame(height: 14)

                    // Dismiss
                    Button {
                        isPresented = false
                    } label: {
                        Text("Maybe later")
                            .font(.systemScaled(15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.45), value: appeared)

                    Spacer().frame(height: 48)
                }
            }
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.hidden)
        .onAppear { appeared = true }
        .fullScreenCover(isPresented: $showComposer) {
            CreatePostView()
        }
    }
}

// MARK: - Interest Chip

private struct ONBInterestChip: View {
    let icon: String
    let label: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(selected ? .white : color)
                Text(label)
                    .font(.systemScaled(14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : ONB.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? color : Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? color : ONB.inkRule,
                                lineWidth: selected ? 0 : 1
                            )
                    )
                    .shadow(color: selected ? color.opacity(0.25) : ONB.glassShadow,
                            radius: selected ? 8 : 4,
                            y: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: selected)
    }
}

// MARK: - Follow Row Skeleton (onboarding list style)

private struct ONBFollowSkeleton: View {
    @State private var opacity: Double = 0.4
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 80, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 72, height: 32)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground)))
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                opacity = 0.9
            }
        }
    }
}

// MARK: - Pressable Button Style (preserved for any callers)

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
