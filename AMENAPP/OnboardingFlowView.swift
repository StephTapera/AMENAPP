//
//  OnboardingFlowView.swift
//  AMENAPP
//
//  5-slide onboarding shown once after account creation.
//  Gated by @AppStorage("hasCompletedOnboarding").
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
    @Namespace private var progressNS

    private let totalPages = 5

    // Suggested users for slide 5 — pulled from PeopleDiscovery logic
    @State private var suggestedUsers: [SuggestedUser] = []

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0A").ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.25))
                            .frame(width: index == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Slides
                TabView(selection: $currentPage) {
                    OnboardingSlide1(onNext: { advance() })
                        .tag(0)
                    OnboardingSlide2(selectedInterests: $selectedInterests, onNext: { advance() })
                        .tag(1)
                    OnboardingSlide3(selectedFaithStage: $selectedFaithStage, onNext: { advance() })
                        .tag(2)
                    OnboardingSlide4(onNext: { advance() }, onSkip: { advance() })
                        .tag(3)
                    OnboardingSlide5(suggestedUsers: $suggestedUsers, onFinish: { finish() })
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { loadSuggestedUsers() }
    }

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
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
            "onboardingCompleted": true,
            "onboardingCompletedAt": Timestamp(date: Date())
        ]
        if !selectedInterests.isEmpty {
            data["interests"] = Array(selectedInterests)
        }
        if !selectedFaithStage.isEmpty {
            data["faithStage"] = selectedFaithStage
        }
        Firestore.firestore().document("users/\(uid)").setData(data, merge: true)
    }

    private func loadSuggestedUsers() {
        // Load a few suggested users from Firestore
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let snap = try? await Firestore.firestore()
                .collection("users")
                .whereField("isPublic", isEqualTo: true)
                .limit(to: 5)
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
            await MainActor.run {
                suggestedUsers = users
            }
        }
    }
}

// MARK: - Slide 1: Welcome

private struct OnboardingSlide1: View {
    let onNext: () -> Void
    @State private var appeared = false

    var firstName: String {
        Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first ?? "there"
    }

    var body: some View {
        ZStack {
            // Glowing orbs
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -80, y: -200)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 120, y: 100)
                .allowsHitTesting(false)

            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 16) {
                    Text("AMEN")
                        .font(.system(size: 56, weight: .black))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)

                    VStack(spacing: 8) {
                        Text("Welcome, \(firstName)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)

                        Text("Where faith meets real life.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.18), value: appeared)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                OnboardingNextButton(title: "Get Started", action: onNext)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.25), value: appeared)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 2: Interests

private struct OnboardingSlide2: View {
    @Binding var selectedInterests: Set<String>
    let onNext: () -> Void
    @State private var appeared = false

    private let interests = [
        "Theology", "Bible Study", "Prayer", "Worship",
        "Marriage", "Parenting", "Mental Health",
        "Discipleship", "Youth", "Leadership", "Missions", "Apologetics"
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("What do you care about?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                Text("Choose up to 5 topics")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

            // Interest chip grid
            ScrollView {
                FlexibleInterestGrid(
                    items: interests,
                    selected: $selectedInterests,
                    maxSelections: 5
                )
                .padding(.horizontal, 20)
            }

            Spacer()

            OnboardingNextButton(
                title: selectedInterests.isEmpty ? "Skip" : "Continue (\(selectedInterests.count) selected)",
                action: onNext
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 3: Faith Stage

private struct OnboardingSlide3: View {
    @Binding var selectedFaithStage: String
    let onNext: () -> Void
    @State private var appeared = false

    private let stages: [(icon: String, label: String, value: String)] = [
        ("flame",        "Just starting",     "exploring"),
        ("book",         "Growing in faith",  "growing"),
        ("heart",        "Going deeper",      "deepening"),
        ("person.2",     "Discipling others", "leading")
    ]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Where are you in your faith journey?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                Text("We'll personalise your experience")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

            VStack(spacing: 12) {
                ForEach(Array(stages.enumerated()), id: \.element.value) { index, stage in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFaithStage = stage.value
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: stage.icon)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selectedFaithStage == stage.value ? .white : Color.white.opacity(0.7))
                                .frame(width: 32)
                            Text(stage.label)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            if selectedFaithStage == stage.value {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedFaithStage == stage.value
                                        ? Color.white.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            OnboardingNextButton(
                title: selectedFaithStage.isEmpty ? "Skip" : "Continue",
                action: onNext
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Slide 4: Notifications

private struct OnboardingSlide4: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var appeared = false
    @State private var permissionGranted = false
    @State private var bellWiggle: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)
                    .rotationEffect(.degrees(bellWiggle))

                VStack(spacing: 8) {
                    Text("Never miss a prayer answered")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("AMEN will notify you when someone prays for you or responds to your posts.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: appeared)
            }

            Spacer()

            VStack(spacing: 12) {
                OnboardingNextButton(title: "Enable Notifications") {
                    Task {
                        let granted = try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .badge, .sound])
                        await MainActor.run {
                            permissionGranted = granted ?? false
                        }
                        onNext()
                    }
                }
                .padding(.horizontal, 24)

                Button("Maybe Later", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: appeared)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation { appeared = true }
            // Bell shake animation — repeating every 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(
                    .spring(response: 0.3, dampingFraction: 0.4)
                    .repeatForever(autoreverses: true)
                ) {
                    bellWiggle = 8
                }
                // Stop wiggle after first burst, restart every 3s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.default) { bellWiggle = 0 }
                }
            }
        }
    }
}

// MARK: - Slide 5: Follow People

private struct OnboardingSlide5: View {
    @Binding var suggestedUsers: [SuggestedUser]
    let onFinish: () -> Void
    @State private var appeared = false
    @State private var followingIds: Set<String> = []

    // Static mock users shown while real data loads
    private let mockUsers: [(name: String, handle: String, initials: String)] = [
        ("Jordan M.", "@jordan", "JM"),
        ("Priya K.", "@priya", "PK"),
        ("Marcus T.", "@marcus", "MT")
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Find Your Community")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 24)
                Text("Follow people who inspire your faith")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

            ScrollView {
                VStack(spacing: 12) {
                    // Show real users if available, otherwise show mock cards
                    if !suggestedUsers.isEmpty {
                        ForEach(Array(suggestedUsers.enumerated()), id: \.element.id) { index, user in
                            SuggestedUserRow(
                                user: user,
                                isFollowing: followingIds.contains(user.id)
                            ) {
                                toggleFollow(user)
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07), value: appeared)
                        }
                    } else {
                        ForEach(Array(mockUsers.enumerated()), id: \.element.handle) { index, mock in
                            GlassMockUserCard(name: mock.name, handle: mock.handle, initials: mock.initials)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 16)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.09), value: appeared)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            OnboardingNextButton(title: "Go to Feed", action: onFinish)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
        .onAppear { withAnimation { appeared = true } }
    }

    private func toggleFollow(_ user: SuggestedUser) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if followingIds.contains(user.id) {
                followingIds.remove(user.id)
                Task { try? await FollowService.shared.unfollowUser(userId: user.id) }
            } else {
                followingIds.insert(user.id)
                Task { try? await FollowService.shared.followUser(userId: user.id) }
            }
        }
    }
}

// MARK: - Glassmorphic Mock User Card

private struct GlassMockUserCard: View {
    let name: String
    let handle: String
    let initials: String
    @State private var isFollowing = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer()

            // Glassmorphic mini pill follow button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing.toggle()
                }
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color.white.opacity(0.5) : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        isFollowing
                        ? AnyView(Capsule().fill(Color.white.opacity(0.1)))
                        : AnyView(Capsule().fill(Color.black))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
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

private struct OnboardingNextButton: View {
    let title: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .font(.headline)
                .foregroundColor(.white)
                .background(Color.black)
                .cornerRadius(50)
                .overlay(
                    RoundedRectangle(cornerRadius: 50)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct FlexibleInterestGrid: View {
    let items: [String]
    @Binding var selected: Set<String>
    let maxSelections: Int

    var body: some View {
        // Simple wrapping layout using LazyVGrid
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.self) { item in
                OnboardingInterestChip(
                    text: item,
                    isSelected: selected.contains(item),
                    isDisabled: !selected.contains(item) && selected.count >= maxSelections
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if selected.contains(item) {
                            selected.remove(item)
                        } else if selected.count < maxSelections {
                            selected.insert(item)
                        }
                    }
                }
            }
        }
    }
}

private struct OnboardingInterestChip: View {
    let text: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { scale = 0.9 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.1)) { scale = 1.0 }
            action()
        } label: {
            Text(text)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .black : Color.white.opacity(isDisabled ? 0.3 : 0.85))
                .background(
                    isSelected
                    ? AnyView(Capsule().fill(Color.white))
                    : AnyView(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .disabled(isDisabled && !isSelected)
    }
}

private struct SuggestedUserRow: View {
    let user: SuggestedUser
    let isFollowing: Bool
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.profileImageURL.flatMap(URL.init)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.15))
                        .overlay(
                            Text(String(user.displayName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !user.username.isEmpty {
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            Spacer()

            Button(isFollowing ? "Following" : "Follow") {
                onFollow()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .foregroundStyle(isFollowing ? Color.white.opacity(0.5) : .white)
            .background(
                isFollowing
                ? AnyView(Capsule().fill(Color.white.opacity(0.1)))
                : AnyView(Capsule().fill(Color.black))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
