import SwiftUI
import CoreLocation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct OnboardingFunnelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    @State private var selectedInterests: Set<UserInterest> = []
    @State private var churchName = ""
    @State private var churchSuggestions: [SmartChurchSummary] = []
    @State private var selectedChurchId: String = ""
    @State private var isSearchingChurch = false
    @State private var churchSearchTask: Task<Void, Never>?
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
                    .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.80), value: step)
                    navigationButtons
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.86), value: showCompletionOrbit)
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
                    .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.80), value: step)
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
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) {
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 28)

                AmenOnboardingHeroIcon(systemName: "building.columns.fill", accent: ONB.accentGold)
                    .padding(.leading, ONB.pagePadding)

                Spacer().frame(height: 20)

                ONBHeroText(
                    headline: "Find your church community.",
                    subheadline: "We'll show you people from your church first."
                )
                .padding(.horizontal, ONB.pagePadding)

                Spacer().frame(height: 28)

                ONBGlassCard(padding: .init(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ONB.inkTertiary)
                            .padding(.leading, 16)
                        TextField("Search your church name…", text: $churchName)
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundStyle(ONB.inkPrimary)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onChange(of: churchName) { _, newVal in
                                selectedChurchId = ""
                                scheduleChurchSearch(query: newVal)
                            }
                            .accessibilityLabel("Church name search")
                        if !churchName.isEmpty {
                            Button {
                                churchName = ""
                                churchSuggestions = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.systemScaled(15))
                                    .foregroundStyle(ONB.inkTertiary)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                    .frame(height: 52)
                }
                .padding(.horizontal, ONB.pagePadding)

                if !churchSuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(churchSuggestions.prefix(5)) { church in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                churchName = church.name
                                selectedChurchId = church.id
                                churchSuggestions = []
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(ONB.accentGold.opacity(0.12))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "building.columns.fill")
                                            .font(.systemScaled(13, weight: .medium))
                                            .foregroundStyle(ONB.accentGold)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(church.name)
                                            .font(.systemScaled(14, weight: .semibold))
                                            .foregroundStyle(ONB.inkPrimary)
                                        if !church.shortLocation.isEmpty {
                                            Text(church.shortLocation)
                                                .font(.systemScaled(12, weight: .regular))
                                                .foregroundStyle(ONB.inkTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedChurchId == church.id {
                                        Image(systemName: "checkmark")
                                            .font(.systemScaled(12, weight: .semibold))
                                            .foregroundStyle(ONB.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if church.id != churchSuggestions.prefix(5).last?.id {
                                Divider().padding(.leading, 62)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: ONB.cardRadius, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: ONB.cardRadius).fill(ONB.glassFill))
                            .overlay(RoundedRectangle(cornerRadius: ONB.cardRadius).strokeBorder(ONB.glassBorder, lineWidth: 1))
                    )
                    .shadow(color: ONB.glassShadow, radius: 10, y: 3)
                    .padding(.horizontal, ONB.pagePadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if isSearchingChurch {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Searching…")
                            .font(.systemScaled(13))
                            .foregroundStyle(ONB.inkTertiary)
                    }
                    .padding(.horizontal, ONB.pagePadding)
                    .padding(.top, 10)
                }

                Spacer().frame(height: 40)
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
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
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .font(.custom("OpenSans-Regular", size: 16)).foregroundStyle(AmenTheme.Colors.textSecondary).padding()
            }
            Spacer()
            Button(step == .invite ? "Get Started" : "Next") {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80)) { advance() }
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
            // Write church to Firestore user profile for cross-device sync
            if !selectedChurchId.isEmpty {
                let update: [String: Any] = [
                    "churchId": selectedChurchId,
                    "churchName": churchName
                ]
                try? await Firestore.firestore().collection("users").document(uid).setData(update, merge: true)
            }
            _ = try? await functions.httpsCallable("advanceOnboardingStep").call([
                "userId": uid, "nextStep": OnboardingStep.complete.rawValue,
                "data": [
                    "interests": selectedInterests.map { $0.rawValue },
                    "church": churchName,
                    "churchId": selectedChurchId
                ]
            ])
        }
    }

    private func scheduleChurchSearch(query: String) {
        churchSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            churchSuggestions = []
            return
        }
        churchSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearchingChurch = true }
            do {
                let items = try await SmartChurchSearchService.shared.keywordSearch(query: trimmed)
                await MainActor.run {
                    churchSuggestions = items.map(\.church)
                    isSearchingChurch = false
                }
            } catch {
                await MainActor.run { isSearchingChurch = false }
            }
        }
    }
}
