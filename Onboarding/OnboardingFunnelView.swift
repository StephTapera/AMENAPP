import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct OnboardingFunnelView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var selectedInterests: Set<UserInterest> = []
    @State private var churchName = ""
    @State private var showCompletionOrbit = false
    @State private var profileCompletionScore: Int?
    @State private var missingProfileItemIds: Set<String> = []
    @Binding var isOnboardingComplete: Bool
    private let functions = Functions.functions()

    var body: some View {
        ZStack {
            if showCompletionOrbit {
                AmenAmbientActionOrbit(
                    profile: completionProfile,
                    actions: completionActions,
                    onContinue: { completeOnboarding(source: "continue", action: nil) },
                    onActionSelected: { action in completeOnboarding(source: "chip", action: action) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressBar
                    TabView(selection: $step) {
                        welcomePage.tag(OnboardingStep.welcome)
                        interestsPage.tag(OnboardingStep.interests)
                        churchPage.tag(OnboardingStep.church)
                        featureTourPage.tag(OnboardingStep.featureTour)
                        invitePage.tag(OnboardingStep.invite)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(response: 0.32, dampingFraction: 0.80), value: step)
                    navigationButtons
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: showCompletionOrbit)
        .task {
            await loadProfileCompletionSnapshot()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases.dropLast(), id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color(red: 0.10, green: 0.60, blue: 0.56) : AmenTheme.Colors.surfaceChip)
                    .frame(height: 4)
                    .animation(.spring(response: 0.32, dampingFraction: 0.80), value: step)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cross.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                .symbolEffect(.pulse)
            Text("Welcome to AMEN")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Faith + action for good. Connect, give, and grow with your faith community.")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var interestsPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("What matters to you?")
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Select all that apply. We'll personalize your experience.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            VStack(spacing: 12) {
                ForEach(UserInterest.allCases, id: \.self) { interest in
                    interestCard(interest: interest)
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    private func interestCard(interest: UserInterest) -> some View {
        let isSelected = selectedInterests.contains(interest)
        let accentColor: Color = {
            switch interest.accentColor {
            case "gold": return Color(red: 0.83, green: 0.69, blue: 0.22)
            case "teal": return Color(red: 0.10, green: 0.60, blue: 0.56)
            case "blue": return Color(red: 0.40, green: 0.70, blue: 0.95)
            default: return Color(red: 0.60, green: 0.50, blue: 0.90)
            }
        }()
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                if isSelected { selectedInterests.remove(interest) } else { selectedInterests.insert(interest) }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: interest.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : accentColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(interest.displayName).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
                    Text(interest.description).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(isSelected ? .white.opacity(0.85) : AmenTheme.Colors.textSecondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? .white : AmenTheme.Colors.textTertiary)
            }
            .padding(14)
            .background(isSelected ? accentColor : AmenTheme.Colors.surfaceCard)
            .cornerRadius(14)
        }
        .accessibilityLabel("\(interest.displayName): \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var churchPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "building.columns.fill").font(.system(size: 48)).foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
            Text("Your Church")
                .font(.custom("OpenSans-Bold", size: 24)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Connect with your church community for local content and events.")
                .font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            TextField("Search for your church...", text: $churchName)
                .font(.custom("OpenSans-Regular", size: 15))
                .padding(12).background(AmenTheme.Colors.surfaceInput).cornerRadius(12).padding(.horizontal, 20)
                .accessibilityLabel("Church name search")
            Spacer()
        }
    }

    private var featureTourPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What's in AMEN")
                    .font(.custom("OpenSans-Bold", size: 24)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.top, 20)
                ForEach(selectedInterests.isEmpty ? UserInterest.allCases : Array(selectedInterests), id: \.self) { interest in
                    featureTourCard(interest: interest)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private func featureTourCard(interest: UserInterest) -> some View {
        let accentColor: Color = {
            switch interest.accentColor {
            case "gold": return Color(red: 0.83, green: 0.69, blue: 0.22)
            case "teal": return Color(red: 0.10, green: 0.60, blue: 0.56)
            case "blue": return Color(red: 0.40, green: 0.70, blue: 0.95)
            default: return Color(red: 0.60, green: 0.50, blue: 0.90)
            }
        }()
        return HStack(spacing: 14) {
            Image(systemName: interest.icon).font(.title2).foregroundStyle(accentColor).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(interest.displayName).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(interest.description).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
        .accessibilityElement(children: .combine)
    }

    private var invitePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.badge.plus.fill").font(.system(size: 56)).foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.90))
            Text("Invite Friends")
                .font(.custom("OpenSans-Bold", size: 24)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Share AMEN with friends from your church and community.")
                .font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button {
                let shareText = "Join me on AMEN — a faith-based community app for giving, wellness, and spiritual growth."
                let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first?.rootViewController?.present(av, animated: true)
            } label: {
                Label("Share AMEN", systemImage: "square.and.arrow.up")
                    .font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(.white)
                    .padding().frame(maxWidth: .infinity)
                    .background(Color(red: 0.60, green: 0.50, blue: 0.90)).cornerRadius(14)
            }
            .padding(.horizontal, 20)
            .accessibilityLabel("Share AMEN app with friends")
            Spacer()
        }
    }

    private var navigationButtons: some View {
        HStack {
            if step.rawValue > 0 {
                Button("Back") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .font(.custom("OpenSans-Regular", size: 16)).foregroundStyle(AmenTheme.Colors.textSecondary).padding()
            }
            Spacer()
            Button(step == .invite ? "Get Started" : "Next") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { advance() }
            }
            .font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(.white)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(Color(red: 0.10, green: 0.60, blue: 0.56)).cornerRadius(14).padding()
            .accessibilityLabel(step == .invite ? "Get Started" : "Next step")
        }
    }

    private var completionProfile: AmenOrbitProfile {
        let user = Auth.auth().currentUser
        let displayName = user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPhoto = hasCompletedProfileItem("photo", fallback: user?.photoURL != nil)
        let hasChurch = hasCompletedProfileItem("location", fallback: !churchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let hasInterests = hasCompletedProfileItem("interests", fallback: selectedInterests.count >= 3)

        let resolvedName: String
        if let displayName, !displayName.isEmpty {
            resolvedName = displayName
        } else {
            resolvedName = "Amen Friend"
        }

        return AmenOrbitProfile(
            displayName: resolvedName,
            username: user?.email?.components(separatedBy: "@").first,
            imageURL: user?.photoURL,
            isComplete: hasPhoto && hasChurch && hasInterests
        )
    }

    private var completionActions: [AmenOrbitAction] {
        AmenOrbitAction.onboardingActions(
            hasPhoto: hasCompletedProfileItem("photo", fallback: Auth.auth().currentUser?.photoURL != nil),
            hasChurch: hasCompletedProfileItem("location", fallback: !churchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            hasInterests: hasCompletedProfileItem("interests", fallback: selectedInterests.count >= 3)
        )
    }

    private func advance() {
        if step == .invite {
            saveOnboarding()
            if AmenOnboardingCompletionRouting.hasSeenOrbit() {
                completeOnboarding(source: "already_seen", action: nil)
            } else {
                AmenOnboardingCompletionRouting.markOrbitSeen()
                AMENAnalyticsService.shared.track(.onboardingCompletionOrbitShown(
                    primaryAction: completionActions.first?.id ?? "none",
                    isProfileComplete: completionProfile.isComplete,
                    completionScore: profileCompletionScore ?? -1
                ))
                showCompletionOrbit = true
            }
        } else {
            step = OnboardingStep(rawValue: step.rawValue + 1) ?? .complete
        }
    }

    private func completeOnboarding(source: String, action: AmenOrbitAction?) {
        let route = AmenOnboardingCompletionRouting.route(for: action?.id)
        if let action {
            AMENAnalyticsService.shared.track(.onboardingCompletionOrbitActionTapped(
                actionId: action.id,
                route: route.rawValue,
                isProfileComplete: completionProfile.isComplete,
                completionScore: profileCompletionScore ?? -1
            ))
        } else {
            AMENAnalyticsService.shared.track(.onboardingCompletionOrbitContinueTapped(
                source: source,
                isProfileComplete: completionProfile.isComplete,
                completionScore: profileCompletionScore ?? -1
            ))
        }
        AmenOnboardingCompletionRouting.request(route)
        isOnboardingComplete = true
    }

    private func hasCompletedProfileItem(_ id: String, fallback: Bool) -> Bool {
        profileCompletionScore == nil ? fallback : !missingProfileItemIds.contains(id)
    }

    private func loadProfileCompletionSnapshot() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snapshot.data() else { return }
            let profileData = UserProfileData(
                name: data["displayName"] as? String ?? Auth.auth().currentUser?.displayName ?? "",
                username: data["username"] as? String ?? "",
                bio: data["bio"] as? String ?? "",
                bioURL: data["bioURL"] as? String,
                initials: "",
                profileImageURL: data["profileImageURL"] as? String ?? Auth.auth().currentUser?.photoURL?.absoluteString,
                interests: data["interests"] as? [String] ?? selectedInterests.map { $0.rawValue },
                socialLinks: [],
                profileTopics: data["profileTopics"] as? [String] ?? []
            )
            let identity = ProfileIdentityService.decode(from: data)
            let items = ProfileCompletionService.shared.items(data: profileData, identity: identity)
            profileCompletionScore = ProfileCompletionService.shared.score(data: profileData, identity: identity)
            missingProfileItemIds = Set(items.filter { !$0.isCompleted }.map(\.id))
        } catch {
            dlog("AmenOnboardingCompletionOrbit: profile completion snapshot failed \(error.localizedDescription)")
        }
    }

    private func saveOnboarding() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        UserDefaults.standard.set(selectedInterests.map { $0.rawValue }, forKey: "userInterests")
        Task {
            _ = try? await functions.httpsCallable("advanceOnboardingStep").call([
                "userId": uid, "nextStep": OnboardingStep.complete.rawValue,
                "data": ["interests": selectedInterests.map { $0.rawValue }, "church": churchName]
            ])
        }
    }
}
