//
//  OnboardingFlowView.swift
//  AMENAPP
//
//  8-slide onboarding shown once after account creation.
//  Slide 0 — Welcome            (white bg + AMEN watermark)
//  Slide 1 — Age Verification   (white bg + AMEN watermark)
//  Slide 2 — Terms of Service   (white bg — required consent)
//  Slide 3 — What We Collect    (white bg — required acknowledgment)
//  Slide 4 — Interests          (white bg — expanded 30+ topics + algorithm note)
//  Slide 5 — Faith Journey      (white bg — 8 inclusive options)
//  Slide 6 — Notifications      (white bg — saves preference)
//  Slide 7 — Find Community     (white bg — real users only + subtle ambient glow + AMEN haptics)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

struct OnboardingFlowView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var selectedInterests: Set<String> = []
    @State private var selectedFaithStage: String = ""
    @State private var notificationsOptedIn = false
    @State private var username: String = ""

    // Age verification
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    private var verifiedBirthYear: Int? {
        // Collect birth year for all ages - no minimum requirement
        return Calendar.current.component(.year, from: birthDate)
    }

    private let totalPages = 9  // Added username slide

    @State private var suggestedUsers: [SuggestedUser] = []

    private let canvas = Color.white  // ✅ Changed to white to match AMEN logo background
    private var dotColor: Color { Color.black.opacity(0.82) }
    private var dotDimColor: Color { Color.black.opacity(0.16) }

    var body: some View {
        ZStack {
            canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? dotColor : dotDimColor)
                            .frame(width: index == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8)

                TabView(selection: $currentPage) {
                    OnboardingSlide1(onNext: { advance() })
                        .tag(0)
                    OnboardingAgeSlide(birthDate: $birthDate, onNext: { advance() })
                        .tag(1)
                    OnboardingTermsSlide(onAgree: { advance() })
                        .tag(2)
                    OnboardingPrivacySlide(onAcknowledge: { advance() })
                        .tag(3)
                    OnboardingSlide2(selectedInterests: $selectedInterests, onNext: { advance() })
                        .tag(4)
                    OnboardingSlide3(selectedFaithStage: $selectedFaithStage, onNext: { advance() })
                        .tag(5)
                    OnboardingSlide4(notificationsOptedIn: $notificationsOptedIn, onNext: { advance() }, onSkip: { advance() })
                        .tag(6)
                    OnboardingUsernameSlide(username: $username, onNext: { advance() })
                        .tag(7)
                    OnboardingSlide5(suggestedUsers: $suggestedUsers, onFinish: { finish() })
                        .tag(8)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { loadSuggestedUsers() }
    }

    private func advance() {
        withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private func finish() {
        saveOnboardingData()
        hasCompletedOnboarding = true
        dismiss()
    }

    private func saveOnboardingData() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            "hasCompletedOnboarding": true,  // Primary flag — checked by checkOnboardingStatus()
            "onboardingCompleted": true,      // Legacy field — some older code reads this
            "onboardingComplete": true,       // Third variant present in some paths — set all three
            "onboardingCompletedAt": Timestamp(date: Date()),
            "notificationsOptedIn": notificationsOptedIn,
            "schemaVersion": 1,
        ]
        if !selectedInterests.isEmpty { data["interests"] = Array(selectedInterests) }
        if !selectedFaithStage.isEmpty { data["faithStage"] = selectedFaithStage }
        if !username.isEmpty { data["username"] = username }
        if let year = verifiedBirthYear {
            data["birthYear"] = year
            data["ageVerified"] = true
        }
        Firestore.firestore().document("users/\(uid)").setData(data, merge: true)
    }

    private func loadSuggestedUsers() {
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let snap = try? await Firestore.firestore()
                .collection("users")
                .whereField("isPublic", isEqualTo: true)
                .limit(to: 6)
                .getDocuments()
            let users = (snap?.documents ?? []).compactMap { doc -> SuggestedUser? in
                let d = doc.data()
                guard doc.documentID != uid else { return nil }
                return SuggestedUser(
                    id: doc.documentID,
                    displayName: d["displayName"] as? String ?? "AMEN User",
                    username: d["username"] as? String ?? "",
                    profileImageURL: d["profileImageURL"] as? String
                )
            }
            await MainActor.run { suggestedUsers = users }
        }
    }
}

// MARK: - Slide 0: Welcome  (white bg, AMEN watermark, no tagline)

private struct OnboardingSlide1: View {
    let onNext: () -> Void
    @State private var appeared = false
    @State private var profileImage: UIImage?

    var firstName: String {
        Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first ?? "there"
    }
    
    var profilePhotoURL: String? {
        Auth.auth().currentUser?.photoURL?.absoluteString
    }

    var body: some View {
        ZStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    // AMEN logo mark - flush with background (transparent, no white container)
                    Image("amen-logo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)

                    // Welcome — no tagline
                    Text("Welcome, \(firstName)")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.12), value: appeared)
                }
                .padding(.horizontal, 32)

                Spacer()

                OnboardingNextButton(title: "Get Started", onLight: true, action: onNext)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.22), value: appeared)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
            
            // Subtle profile avatar in top left
            VStack {
                HStack {
                    if let image = profileImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                            .opacity(appeared ? 0.85 : 0)
                            .scaleEffect(appeared ? 1 : 0.8)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: appeared)
                            .padding(.leading, 20)
                            .padding(.top, 60)
                    } else if profilePhotoURL != nil {
                        // Placeholder while loading
                        Circle()
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1.5)
                            )
                            .opacity(appeared ? 0.85 : 0)
                            .scaleEffect(appeared ? 1 : 0.8)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: appeared)
                            .padding(.leading, 20)
                            .padding(.top, 60)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation { appeared = true }
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard let urlString = profilePhotoURL else { return }
        Task {
            let image = await ImageCache.shared.loadImage(url: urlString, size: CGSize(width: 132, height: 132))
            await MainActor.run {
                profileImage = image
            }
        }
    }
}

// MARK: - Slide 1: Age Verification  (white bg, AMEN watermark)

private struct OnboardingAgeSlide: View {
    @Binding var birthDate: Date
    let onNext: () -> Void
    @State private var appeared = false
    @State private var showPicker = false
    @State private var hasSelectedDate = false

    private var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }
    private var isEligible: Bool { hasSelectedDate } // Just ensure they selected a date

    var body: some View {
        ZStack {
            // Subtle AMEN watermark
            Text("AMEN")
                .font(.systemScaled(200, weight: .black))
                .tracking(24)
                .foregroundStyle(Color(.quaternaryLabel))
                .offset(y: 40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 80, height: 80)
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.systemScaled(34, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

                    VStack(spacing: 8) {
                        Text("Quick age check")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text("Select your birth date to personalize your experience.\nWe'll never share this information.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: appeared)

                    // Date picker card
                    VStack(spacing: 0) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75))) {
                                showPicker.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(hasSelectedDate ? birthDate.formatted(date: .long, time: .omitted) : "Select your birth date")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(hasSelectedDate ? Color.black.opacity(0.85) : Color.black.opacity(0.45))
                                Spacer()
                                Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .animation(.easeInOut(duration: 0.2), value: showPicker)
                            }
                            .padding(16)
                        }
                        .buttonStyle(.plain)

                        if showPicker {
                            Divider().padding(.horizontal, 16)
                            DatePicker(
                                "",
                                selection: $birthDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .onChange(of: birthDate) { _, _ in
                                hasSelectedDate = true
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                }

                Spacer()

                OnboardingNextButton(
                    title: "Confirm & Continue",
                    onLight: true,
                    isEnabled: isEligible,
                    action: onNext
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.22), value: appeared)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 2: Terms of Service  (white, liquid glass, required)

private struct OnboardingTermsSlide: View {
    let onAgree: () -> Void
    @State private var agreed = false
    @State private var appeared = false
    @State private var cardScale: CGFloat = 0.94
    @State private var glassShimmer: CGFloat = 0

    private let terms: [(icon: String, title: String, detail: String)] = [
        ("person.crop.circle.badge.checkmark", "Be yourself, authentically",
         "Real names and genuine content keep our community trustworthy. Impersonation is not permitted."),
        ("hand.raised.fill", "Respect every person",
         "No harassment, hate speech, or content that demeans others based on identity, beliefs, or background."),
        ("shield.fill", "Protect the vulnerable",
         "Content that exploits or endangers minors is strictly prohibited and reported to authorities."),
        ("heart.fill", "Honour the community covenant",
         "AMEN is a faith-centred space. We uphold Christian values while welcoming all who seek them."),
        ("exclamationmark.triangle.fill", "No misinformation",
         "Deliberately false health, safety, or doctrinal claims that could harm others are not allowed."),
        ("arrow.counterclockwise", "Your content, your responsibility",
         "You own what you post. AMEN may remove content that violates these terms without notice."),
    ]

    var body: some View {
        ZStack {
            // Watermark
            Text("AMEN")
                .font(.systemScaled(200, weight: .black))
                .tracking(24)
                .foregroundStyle(Color(.quaternaryLabel))
                .offset(y: 40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 64, height: 64)
                        Image(systemName: "doc.text.fill")
                            .font(.systemScaled(28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
                    .padding(.top, 20)

                    Text("Community Standards")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: appeared)

                    Text("Please read and agree to continue")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: appeared)
                }
                .padding(.bottom, 16)

                // Scrollable terms cards
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Array(terms.enumerated()), id: \.element.title) { idx, term in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.07))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: term.icon)
                                        .font(.systemScaled(17, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(term.title)
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(term.detail)
                                        .font(.systemScaled(12, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(2)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.85),
                                                Color.white.opacity(0.65),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.black.opacity(0.07), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 3)
                            )
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15 + Double(idx) * 0.05), value: appeared)
                        }

                        // Full terms link
                        HStack(spacing: 4) {
                            Text("Read the full")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Link("Terms of Service", destination: URL(string: "https://amenapp.com/terms")!)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Link("Privacy Policy", destination: URL(string: "https://amenapp.com/privacy")!)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                // Agreement toggle + button
                VStack(spacing: 14) {
                    // Liquid glass toggle row
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
                            agreed.toggle()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(agreed ? Color.black : Color.black.opacity(0.08))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.black.opacity(agreed ? 0 : 0.25), lineWidth: 1.5)
                                    )
                                if agreed {
                                    Image(systemName: "checkmark")
                                        .font(.systemScaled(13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            Text("I agree to the Community Standards & Terms of Service")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(agreed ? Color.black.opacity(0.05) : Color.black.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(agreed ? Color.black.opacity(0.2) : Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)

                    OnboardingNextButton(
                        title: "Agree & Continue",
                        onLight: true,
                        isEnabled: agreed,
                        action: onAgree
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45), value: appeared)
                }
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 3: What We Collect  (white, liquid glass, required)

private struct OnboardingPrivacySlide: View {
    let onAcknowledge: () -> Void
    @State private var appeared = false
    @State private var acknowledged = false

    private let dataPoints: [(icon: String, category: String, what: String, why: String, color: Color)] = [
        ("person.fill",
         "Your Profile",
         "Name · email · username · date of birth",
         "To create your account, let others find you, and verify your age.",
         Color(red: 0.35, green: 0.50, blue: 0.95)),

        ("doc.text.fill",
         "Your Content",
         "Posts · prayers · notes · messages",
         "To show in your feed and communities. Messages stay between you and recipients.",
         Color(red: 0.55, green: 0.30, blue: 0.90)),

        ("bell.fill",
         "Notification Token",
         "Device push token only",
         "To send prayer reminders and community alerts. You control every notification type.",
         Color(red: 0.20, green: 0.62, blue: 0.45)),

        ("chart.bar.fill",
         "App Usage",
         "Feature usage · crash reports",
         "To improve stability. Never shared with advertisers or third parties.",
         Color(red: 0.85, green: 0.48, blue: 0.18)),

        ("eye.slash.fill",
         "What We Do NOT Collect",
         "Location · contacts · browsing history",
         "We will never request or sell data we don't need to serve you.",
         Color(red: 0.80, green: 0.20, blue: 0.30)),
    ]

    var body: some View {
        ZStack {
            // Watermark
            Text("AMEN")
                .font(.systemScaled(200, weight: .black))
                .tracking(24)
                .foregroundStyle(Color(.quaternaryLabel))
                .offset(y: 40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 64, height: 64)
                        Image(systemName: "lock.shield.fill")
                            .font(.systemScaled(28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
                    .padding(.top, 20)

                    Text("What We Collect")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: appeared)

                    // Trust badges
                    HStack(spacing: 8) {
                        ForEach([("lock.fill", "Encrypted"), ("eye.slash.fill", "Not sold"), ("hand.raised.fill", "Minimal")], id: \.1) { icon, label in
                            HStack(spacing: 4) {
                                Image(systemName: icon).font(.systemScaled(9, weight: .semibold))
                                Text(label).font(.systemScaled(10, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.07)))
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: appeared)
                }
                .padding(.bottom, 12)

                // Scrollable data cards
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 9) {
                        ForEach(Array(dataPoints.enumerated()), id: \.element.category) { idx, point in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(point.color.opacity(0.10))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: point.icon)
                                        .font(.systemScaled(17, weight: .medium))
                                        .foregroundStyle(point.color)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.category)
                                        .font(.systemScaled(13, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text(point.what)
                                        .font(.systemScaled(11, weight: .medium))
                                        .foregroundStyle(point.color.opacity(0.8))
                                    Text(point.why)
                                        .font(.systemScaled(11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(2)
                                }
                            }
                            .padding(13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.9),
                                                point.color.opacity(0.04),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(point.color.opacity(0.12), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)
                            )
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15 + Double(idx) * 0.06), value: appeared)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }

                // Acknowledge + button
                VStack(spacing: 14) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.7))) {
                            acknowledged.toggle()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(acknowledged ? Color.black : Color.black.opacity(0.08))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.black.opacity(acknowledged ? 0 : 0.25), lineWidth: 1.5)
                                    )
                                if acknowledged {
                                    Image(systemName: "checkmark")
                                        .font(.systemScaled(13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            Text("I understand how AMEN uses my data")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(acknowledged ? Color.black.opacity(0.05) : Color.black.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(acknowledged ? Color.black.opacity(0.2) : Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)

                    OnboardingNextButton(
                        title: "I Understand — Continue",
                        onLight: true,
                        isEnabled: acknowledged,
                        action: onAcknowledge
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.55), value: appeared)
                }
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 4: Interests  (white, expanded, algorithm note)

private struct OnboardingSlide2: View {
    @Binding var selectedInterests: Set<String>
    let onNext: () -> Void
    @State private var appeared = false

    private let maxSelections = 8

    private let sections: [(title: String, items: [(icon: String, label: String)])] = [
        ("Faith & Spirituality", [
            ("hands.sparkles.fill", "Prayer"),
            ("book.closed.fill", "Bible Study"),
            ("music.note", "Worship"),
            ("lightbulb.fill", "Theology"),
            ("arrow.right.circle.fill", "Discipleship"),
            ("globe", "Missions"),
            ("shield.fill", "Apologetics"),
            ("sparkles", "Berean AI"),
        ]),
        ("Life & Growth", [
            ("heart.text.square.fill", "Mental Health"),
            ("house.fill", "Marriage & Family"),
            ("person.2.fill", "Parenting"),
            ("arrow.up.circle.fill", "Leadership"),
            ("arrow.triangle.2.circlepath", "Recovery"),
            ("person.crop.circle.fill", "Mentorship"),
        ]),
        ("Community", [
            ("building.columns.fill", "Church Life"),
            ("person.3.fill", "Small Groups"),
            ("star.fill", "Testimonies"),
            ("heart.fill", "Women's Ministry"),
            ("figure.wave", "Men's Ministry"),
            ("graduationcap.fill", "Youth"),
        ]),
        ("Culture & Society", [
            ("cpu", "Tech & Innovation"),
            ("briefcase.fill", "Business"),
            ("paintbrush.fill", "Arts & Creativity"),
            ("music.mic", "Music"),
            ("hand.raised.fill", "Social Justice"),
            ("globe.americas.fill", "Evangelism"),
        ]),
        ("Learning", [
            ("books.vertical.fill", "Books & Reading"),
            ("clock.fill", "Church History"),
            ("atom", "Science & Faith"),
            ("text.bubble.fill", "Philosophy"),
        ]),
    ]

    var body: some View {
        ZStack {
            OnboardingWatermarkBackground()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("What do you care about?")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)

                    Text("We use this to personalize your feed, not to sell you things.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    if !selectedInterests.isEmpty {
                        Text("\(selectedInterests.count) of \(maxSelections) selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(sections.enumerated()), id: \.element.title) { sIdx, section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title.uppercased())
                                    .font(.systemScaled(10, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 4)

                                FlexibleInterestGrid(
                                    items: section.items,
                                    selected: $selectedInterests,
                                    maxSelections: maxSelections
                                )
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(sIdx) * 0.06), value: appeared)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                OnboardingNextButton(
                    title: selectedInterests.isEmpty ? "Skip" : "Continue (\(selectedInterests.count) selected)",
                    onLight: true,
                    action: onNext
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 3: Faith Journey  (white, 8 inclusive options)

private struct OnboardingSlide3: View {
    @Binding var selectedFaithStage: String
    let onNext: () -> Void
    @State private var appeared = false

    private let stages: [(icon: String, label: String, sublabel: String, value: String)] = [
        ("magnifyingglass",           "Just curious",                    "Open to learning more",              "curious"),
        ("leaf",                      "Open & exploring",                "No commitment, just looking",        "exploring"),
        ("flame",                     "Starting my faith journey",       "Taking my first real steps",         "beginning"),
        ("arrow.up.circle.fill",      "Growing in faith",                "Learning, praying, connecting",      "growing"),
        ("book.fill",                 "Going deeper",                    "Serious about Scripture & doctrine", "deepening"),
        ("building.columns.fill",     "Active church member",            "Engaged in my local community",      "active"),
        ("person.2.fill",             "Discipling / mentoring others",   "Helping others grow in faith",       "leading"),
        ("questionmark.circle.fill",  "Questioning / deconstructing",    "Working through doubts honestly",    "questioning"),
    ]

    var body: some View {
        ZStack {
            OnboardingWatermarkBackground()

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Where are you in your\nfaith journey?")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    Text("All backgrounds welcome. Pick what fits best.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Array(stages.enumerated()), id: \.element.value) { index, stage in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                    selectedFaithStage = stage.value
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: stage.icon)
                                        .font(.systemScaled(20, weight: .medium))
                                        .foregroundStyle(selectedFaithStage == stage.value ? Color.white : Color.black.opacity(0.56))
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stage.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(selectedFaithStage == stage.value ? Color.white : Color.black.opacity(0.84))
                                        Text(stage.sublabel)
                                            .font(.caption)
                                            .foregroundStyle(selectedFaithStage == stage.value ? Color.white.opacity(0.72) : Color.black.opacity(0.48))
                                    }

                                    Spacer()

                                    if selectedFaithStage == stage.value {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.white)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selectedFaithStage == stage.value ? Color.black : Color.white.opacity(0.86))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(selectedFaithStage == stage.value ? Color.black.opacity(0.85) : Color.black.opacity(0.08), lineWidth: 1)
                                        )
                                )
                                .shadow(color: .black.opacity(selectedFaithStage == stage.value ? 0.12 : 0.04), radius: selectedFaithStage == stage.value ? 14 : 8, x: 0, y: selectedFaithStage == stage.value ? 6 : 3)
                            }
                            .buttonStyle(.plain)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: appeared)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                OnboardingNextButton(
                    title: selectedFaithStage.isEmpty ? "Skip" : "Continue",
                    onLight: true,
                    action: onNext
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 4: Notifications  (saves preference)

private struct OnboardingSlide4: View {
    @Binding var notificationsOptedIn: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var appeared = false
    @State private var bellWiggle: Double = 0

    var body: some View {
        ZStack {
            OnboardingWatermarkBackground()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: 132, height: 132)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.92), lineWidth: 1.2)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 10)

                        Image(systemName: "bell.fill")
                            .font(.systemScaled(52, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.82))
                            .rotationEffect(.degrees(bellWiggle))
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)

                    VStack(spacing: 8) {
                        Text("Never miss a prayer answered")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text("AMEN will notify you when someone prays for you or responds to your posts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)
                }

                Spacer()

                VStack(spacing: 12) {
                    OnboardingNextButton(title: "Enable Notifications", onLight: true) {
                        Task {
                            let granted = await PushNotificationManager.shared.requestNotificationPermissions()
                            await MainActor.run { notificationsOptedIn = granted }
                            if granted {
                                await MainActor.run { PushNotificationManager.shared.setupFCMToken() }
                            }
                            onNext()
                        }
                    }
                    .padding(.horizontal, 24)

                    Button("Maybe Later") {
                        notificationsOptedIn = false
                        onSkip()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: appeared)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.4))) { bellWiggle = 8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.default) { bellWiggle = 0 }
                }
            }
        }
    }
}

// MARK: - Slide 5: Username Selection

private struct OnboardingUsernameSlide: View {
    @Binding var username: String
    let onNext: () -> Void
    @State private var appeared = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var usernameError: String?
    @State private var checkTask: Task<Void, Never>?
    
    private var isValid: Bool {
        guard !username.isEmpty else { return false }
        guard username.count >= 3 else { return false }
        guard username.count <= 30 else { return false }
        // Must be alphanumeric, underscores, or periods only
        let pattern = "^[a-zA-Z0-9_.]+$"
        return username.range(of: pattern, options: .regularExpression) != nil
    }
    
    private var canProceed: Bool {
        isValid && usernameAvailable == true
    }
    
    var body: some View {
        ZStack {
            // Subtle AMEN watermark
            Text("AMEN")
                .font(.systemScaled(200, weight: .black))
                .tracking(24)
                .foregroundStyle(Color(.quaternaryLabel))
                .offset(y: 40)
                .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 80, height: 80)
                        Image(systemName: "at.circle.fill")
                            .font(.systemScaled(34, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
                    
                    VStack(spacing: 8) {
                        Text("Choose your username")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("Pick a unique username. You can always change it later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: appeared)
                    
                    // Username input
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Text("@")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.tertiary)
                            
                            TextField("username", text: $username)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: username) { _, newValue in
                                    checkUsernameAvailability(newValue)
                                }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )
                        
                        // Status indicator
                        HStack(spacing: 6) {
                            if isCheckingUsername {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Checking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let error = usernameError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if usernameAvailable == true {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.green)
                                Text("Username available")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !username.isEmpty && usernameAvailable == false {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.red)
                                Text("Username taken")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(height: 20)
                    }
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
                }
                
                Spacer()
                
                OnboardingNextButton(
                    title: "Continue",
                    onLight: true,
                    isEnabled: canProceed,
                    action: onNext
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.22), value: appeared)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear { withAnimation { appeared = true } }
        .onDisappear {
            checkTask?.cancel()
        }
    }
    
    private func checkUsernameAvailability(_ newUsername: String) {
        // Cancel previous check
        checkTask?.cancel()
        
        // Reset state
        usernameAvailable = nil
        usernameError = nil
        
        // Validate format first
        guard !newUsername.isEmpty else { return }
        
        if newUsername.count < 3 {
            usernameError = "Minimum 3 characters"
            return
        }
        
        if newUsername.count > 30 {
            usernameError = "Maximum 30 characters"
            return
        }
        
        let pattern = "^[a-zA-Z0-9_.]+$"
        guard newUsername.range(of: pattern, options: .regularExpression) != nil else {
            usernameError = "Letters, numbers, _ and . only"
            return
        }
        
        // Check availability in Firestore
        isCheckingUsername = true
        
        checkTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                guard !Task.isCancelled else { return }
                
                lazy var db = Firestore.firestore()
                let snapshot = try await db.collection("users")
                    .whereField("username", isEqualTo: newUsername.lowercased())
                    .limit(to: 1)
                    .getDocuments()
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isCheckingUsername = false
                    usernameAvailable = snapshot.documents.isEmpty
                }
            } catch {
                await MainActor.run {
                    isCheckingUsername = false
                    usernameError = "Check failed"
                }
            }
        }
    }
}

// MARK: - Slide 6: Find Community  (real users only, screen glow, AMEN haptics)

private struct OnboardingSlide5: View {
    @Binding var suggestedUsers: [SuggestedUser]
    let onFinish: () -> Void
    @State private var appeared = false
    @State private var followingIds: Set<String> = []
    @State private var glowAngle: Double = 0
    @State private var glowOpacity: Double = 0.16

    var body: some View {
        ZStack {
            OnboardingWatermarkBackground()

            Circle()
                .fill(Color(red: 0.96, green: 0.93, blue: 0.88).opacity(0.95))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -110, y: -220)
                .allowsHitTesting(false)

            Circle()
                .fill(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 130, y: 280)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.black.opacity(glowOpacity * 0.7),
                            Color(red: 0.79, green: 0.66, blue: 0.30).opacity(glowOpacity),
                            Color.clear,
                            Color.black.opacity(glowOpacity * 0.55),
                            Color.clear,
                            Color(red: 0.79, green: 0.66, blue: 0.30).opacity(glowOpacity),
                        ],
                        center: .center,
                        startAngle: .degrees(glowAngle),
                        endAngle: .degrees(glowAngle + 360)
                    ),
                    lineWidth: 2.5
                )
                .blur(radius: 10)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Find Your Community")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .padding(.top, 24)
                    Text("Follow people who inspire your faith")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                if suggestedUsers.isEmpty {
                    // Real empty state — no fake accounts
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.systemScaled(44))
                            .foregroundStyle(.tertiary)
                        Text("Your community is on its way")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("You'll discover people to follow once you're in the feed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(Array(suggestedUsers.enumerated()), id: \.element.id) { index, user in
                                OnboardingSuggestedUserRow(
                                    user: user,
                                    isFollowing: followingIds.contains(user.id)
                                ) { toggleFollow(user) }
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 16)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                OnboardingNextButton(title: "Go to Feed", onLight: true) {
                    amenHapticSignature()
                    onFinish()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)
            }
        }
        .onAppear {
            withAnimation { appeared = true }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                glowAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowOpacity = 0.26
            }
        }
    }

    private func toggleFollow(_ user: SuggestedUser) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            if followingIds.contains(user.id) {
                followingIds.remove(user.id)
                Task { try? await FollowService.shared.unfollowUser(userId: user.id) }
            } else {
                followingIds.insert(user.id)
                Task { try? await FollowService.shared.followUser(userId: user.id) }
            }
        }
    }

    /// AMEN haptic signature — rising sequence, warm finish
    private func amenHapticSignature() {
        let light  = UIImpactFeedbackGenerator(style: .light)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let success = UINotificationFeedbackGenerator()
        light.prepare(); medium.prepare(); success.prepare()

        light.impactOccurred(intensity: 0.45)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            light.impactOccurred(intensity: 0.7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            medium.impactOccurred(intensity: 0.9)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            success.notificationOccurred(.success)
        }
    }
}

// MARK: - Supporting Types

struct SuggestedUser: Identifiable {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
}

// MARK: - Reusable Onboarding Components

private struct OnboardingWatermarkBackground: View {
    var body: some View {
        ZStack {
            Text("AMEN")
                .font(.systemScaled(200, weight: .black))
                .tracking(24)
                .foregroundStyle(Color(.quaternaryLabel))
                .offset(y: 40)

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -120, y: -220)

            Circle()
                .fill(Color(red: 0.79, green: 0.66, blue: 0.30).opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 120, y: 280)
        }
        .allowsHitTesting(false)
    }
}

private struct OnboardingNextButton: View {
    let title: String
    var onLight: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var isPressed = false

    private var bgColor: Color { onLight ? .black : .black }
    private var textColor: Color { .white }

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .font(.headline)
                .foregroundColor(textColor)
                .background(isEnabled ? bgColor : bgColor.opacity(0.35))
                .cornerRadius(50)
                .shadow(color: .black.opacity(onLight ? 0.12 : 0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct FlexibleInterestGrid: View {
    let items: [(icon: String, label: String)]
    @Binding var selected: Set<String>
    let maxSelections: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.label) { item in
                OnboardingInterestChip(
                    icon: item.icon,
                    text: item.label,
                    isSelected: selected.contains(item.label),
                    isDisabled: !selected.contains(item.label) && selected.count >= maxSelections
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        if selected.contains(item.label) {
                            selected.remove(item.label)
                        } else if selected.count < maxSelections {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selected.insert(item.label)
                        }
                    }
                }
            }
        }
    }
}

private struct OnboardingInterestChip: View {
    let icon: String
    let text: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.5))) { scale = 0.88 }
            withAnimation(Motion.adaptive(.spring(response: 0.32, dampingFraction: 0.6)).delay(0.1)) { scale = 1.0 }
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.black.opacity(isDisabled ? 0.22 : 0.70))
                Text(text)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.black.opacity(isDisabled ? 0.28 : 0.84))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                ? AnyView(Capsule().fill(Color.black))
                : AnyView(
                    Capsule()
                        .fill(Color.white.opacity(0.82))
                        .overlay(Capsule().stroke(Color.black.opacity(isDisabled ? 0.05 : 0.10), lineWidth: 1))
                )
            )
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 10 : 6, x: 0, y: isSelected ? 5 : 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .disabled(isDisabled && !isSelected)
    }
}

private struct OnboardingSuggestedUserRow: View {
    let user: SuggestedUser
    let isFollowing: Bool
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.profileImageURL.flatMap(URL.init)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Circle().fill(Color.black.opacity(0.06))
                        .overlay(
                            Text(String(user.displayName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !user.username.isEmpty {
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(isFollowing ? "Following" : "Follow") { onFollow() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .foregroundStyle(isFollowing ? Color.black.opacity(0.58) : Color.white)
                .background(
                    isFollowing
                    ? AnyView(Capsule().fill(Color.white.opacity(0.9)))
                    : AnyView(Capsule().fill(Color.black))
                )
                .overlay(Capsule().stroke(Color.black.opacity(isFollowing ? 0.10 : 0.0), lineWidth: 1))
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 6)
    }
}
