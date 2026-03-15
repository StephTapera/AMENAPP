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

// MARK: - Onboarding Container

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    @State private var step: Int = 0
    @State private var direction: TransitionDirection = .forward

    // Step 3 — account setup
    @State private var selectedProfileImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var username: String = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?

    // DOB
    @State private var birthDate: Date = Calendar.current.date(
        byAdding: .year, value: -18, to: Date()
    ) ?? Date()
    @State private var showDOBPicker = false
    private var birthDateIsValid: Bool {
        // Must be at least 13 (COPPA)
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return age >= 13
    }

    // Step 4 — notifications toggle
    @State private var notificationsEnabled = true
    @State private var privateAccount       = false

    // Step 5 — interests
    @State private var selectedInterests: Set<String> = []

    // Submission
    @State private var isSaving     = false
    @State private var saveError: String?
    @State private var showErrorAlert = false

    enum TransitionDirection { case forward, backward }

    let totalSteps = 4  // steps 0-3 (AppLaunchView is step -1 outside this view)

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
                        .font(.system(size: 16, weight: .medium))
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

            // Skip button (visible on steps 0-2)
            if step < 3 {
                Button {
                    advance(by: 1)
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .medium))
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        direction = delta > 0 ? .forward : .backward
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            step = max(0, min(totalSteps - 1, step + delta))
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
                    Text("Built different.")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(ONB.inkPrimary)

                    Text("AMEN is a social platform designed around your faith, not your attention.")
                        .font(.system(size: 17, weight: .regular))
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

                // CTA
                ONBPrimaryButton(title: "Get Started") { advance(by: 1) }
                    .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 48)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ONB.inkPrimary)
                    Text(body)
                        .font(.system(size: 13, weight: .regular))
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
                    Text("Make it yours.")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(ONB.inkPrimary)

                    Text("Add a photo and choose a username. You can always update these later.")
                        .font(.system(size: 17, weight: .regular))
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
                                            .font(.system(size: 38))
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
                                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ONB.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: selectedProfileImage == nil)

                Spacer().frame(height: 28)

                // Username field
                ONBGlassCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("USERNAME")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ONB.inkTertiary)

                        HStack(spacing: 10) {
                            Text("@")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(ONB.inkTertiary)

                            TextField("yourname", text: $username)
                                .font(.system(size: 18, weight: .medium))
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
                                        .font(.system(size: 18))
                                        .foregroundStyle(avail ? Color.green : Color.red)
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.30), value: usernameAvailable)
                        }

                        if let avail = usernameAvailable {
                            Text(avail ? "Username available" : "Already taken — try another")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(avail ? Color.green : Color.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.2), value: avail)
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 12)

                Text("Your username is how others find and mention you in the community.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 20)

                // Date of birth picker
                ONBGlassCard(padding: .init(top: 16, leading: 18, bottom: 16, trailing: 18)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DATE OF BIRTH")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(ONB.inkTertiary)

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                showDOBPicker.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(ONB.accent)

                                Text(birthDate, style: .date)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(ONB.inkPrimary)

                                Spacer()

                                Image(systemName: showDOBPicker ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ONB.inkTertiary)
                                    .animation(.easeInOut(duration: 0.2), value: showDOBPicker)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDOBPicker {
                            DatePicker(
                                "",
                                selection: $birthDate,
                                in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if !birthDateIsValid {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                Text("You must be at least 13 to join AMEN.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 8)

                Text("Required to verify your age and personalize your experience.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .padding(.horizontal, ONB.pagePadding + 4)

                Spacer().frame(height: 32)

                // CTA
                ONBPrimaryButton(title: "Continue", isEnabled: birthDateIsValid) {
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
                    usernameAvailable = snap.documents.isEmpty
                    isCheckingUsername = false
                }
            } catch {
                await MainActor.run { isCheckingUsername = false }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 2: Privacy & Safety
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var privacySafetyPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your data,\nyour rules.")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(ONB.inkPrimary)
                        .lineSpacing(1)

                    Text("We only collect what makes AMEN better for you. Here's exactly what we use and why.")
                        .font(.system(size: 17, weight: .regular))
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
                            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                            Text(label).font(.system(size: 11, weight: .semibold))
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
                            why: "To create and secure your account, verify your age (13+), and help others find you."
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
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ONB.inkTertiary)
                    Link("Privacy Policy", destination: URL(string: "https://amenapp.com/privacy")!)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ONB.accent)
                    Text("and")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ONB.inkTertiary)
                    Link("Terms of Service", destination: URL(string: "https://amenapp.com/terms")!)
                        .font(.system(size: 12, weight: .medium))
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
                    Text("What matters\nto you?")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(ONB.inkPrimary)
                        .lineSpacing(1)

                    Text("Choose a few interests and we'll personalize your feed. Skip if you prefer to explore first.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
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

                // Completion CTA
                ONBPrimaryButton(
                    title: "Enter AMEN",
                    isLoading: isSaving,
                    isEnabled: true
                ) {
                    Task { await finishOnboarding() }
                }
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 16)

                Text("By joining you agree to our Terms and Privacy Policy.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)

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
            guard let userId = Auth.auth().currentUser?.uid else { return }
            let db = Firestore.firestore()

            let birthYear = Calendar.current.component(.year, from: birthDate)
            var updateData: [String: Any] = [
                "interests":            Array(selectedInterests),
                "isPrivate":            privateAccount,
                "notificationsEnabled": notificationsEnabled,
                "birthYear":            birthYear,
            ]

            // Save username if entered and available
            let trimmedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
            if !trimmedUsername.isEmpty && (usernameAvailable == true || usernameAvailable == nil) {
                updateData["username"] = trimmedUsername
            }

            // Upload profile image if selected
            if let img = selectedProfileImage {
                let userService = UserService()
                if let imageURL = try? await userService.uploadProfileImage(img) {
                    updateData["profileImageURL"] = imageURL
                }
            }

            try await db.collection("users").document(userId).updateData(updateData)
            await MainActor.run {
                isSaving = false
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .white : color)
                Text(label)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
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

// MARK: - Pressable Button Style (preserved for any callers)

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
