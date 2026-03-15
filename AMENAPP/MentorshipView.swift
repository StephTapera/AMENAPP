// MentorshipView.swift
// AMENAPP
//
// Full mentorship & discipleship matching platform.
// Covers: mentor profiles, mentee onboarding, accountability circles,
// discipleship tracks, goal tracking, check-ins, scripture plans.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Data Models

struct MentorProfile: Identifiable, Codable {
    var id: String = UUID().uuidString
    var uid: String = ""
    var displayName: String = ""
    var photoURL: String = ""
    var bio: String = ""
    var role: String = ""                    // e.g. "Pastor", "Life Coach", "Elder"
    var church: String = ""
    var specialties: [String] = []           // e.g. ["Marriage", "Career", "New Believers"]
    var availabilityNote: String = ""        // e.g. "Available evenings"
    var maxMentees: Int = 3
    var currentMenteeCount: Int = 0
    var isVerified: Bool = false
    var verificationBadge: String = ""       // "Church Elder", "Licensed Counselor", etc.
    var yearsOfFaith: Int = 0
    var denomination: String = ""
    var acceptingMentees: Bool = true
    var rating: Double = 0.0
    var reviewCount: Int = 0
    var createdAt: Date = Date()
}

struct MentorRequest: Identifiable, Codable {
    var id: String = UUID().uuidString
    var fromUID: String = ""
    var toUID: String = ""
    var fromName: String = ""
    var fromPhotoURL: String = ""
    var message: String = ""
    var goal: String = ""                    // What mentee wants from this relationship
    var status: MentorRequestStatus = .pending
    var createdAt: Date = Date()
    var respondedAt: Date?
}

enum MentorRequestStatus: String, Codable {
    case pending  = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

struct AccountabilityCircle: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String = ""
    var description: String = ""
    var createdByUID: String = ""
    var memberUIDs: [String] = []
    var maxMembers: Int = 8
    var focusArea: String = ""              // e.g. "Prayer", "Bible Reading", "Sobriety"
    var checkInFrequency: String = "Weekly" // Daily, Weekly, Biweekly
    var isPrivate: Bool = true
    var inviteCode: String = ""
    var createdAt: Date = Date()
    var lastActivityAt: Date = Date()
}

struct DiscipleshipTrack: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let duration: String
    let weekCount: Int
    let steps: [TrackStep]
}

struct TrackStep: Identifiable {
    let id = UUID()
    let week: Int
    let title: String
    let scripture: String
    let action: String
    let reflection: String
}

struct CircleCheckIn: Identifiable, Codable {
    var id: String = UUID().uuidString
    var circleID: String = ""
    var uid: String = ""
    var displayName: String = ""
    var note: String = ""
    var mood: CircleCheckInMood = .growing
    var prayerRequest: String = ""
    var createdAt: Date = Date()
}

enum CircleCheckInMood: String, Codable, CaseIterable {
    case thriving   = "Thriving"
    case growing    = "Growing"
    case struggling = "Struggling"
    case needPrayer = "Need Prayer"

    var emoji: String {
        switch self {
        case .thriving:   return "🌟"
        case .growing:    return "🌱"
        case .struggling: return "🙏"
        case .needPrayer: return "❤️"
        }
    }

    var color: Color {
        switch self {
        case .thriving:   return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .growing:    return Color(red: 0.15, green: 0.45, blue: 0.82)
        case .struggling: return Color(red: 0.90, green: 0.47, blue: 0.10)
        case .needPrayer: return Color(red: 0.75, green: 0.20, blue: 0.20)
        }
    }
}

// MARK: - Mentorship Store

@MainActor
final class MentorshipStore: ObservableObject {
    static let shared = MentorshipStore()

    @Published var myMentorProfile: MentorProfile?
    @Published var featuredMentors: [MentorProfile] = []
    @Published var myCircles: [AccountabilityCircle] = []
    @Published var pendingRequests: [MentorRequest] = []
    @Published var isLoaded = false

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    func loadAll() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        loadFeaturedMentors()
        loadMyCircles(uid: uid)
        loadMentorProfile(uid: uid)
    }

    private func loadFeaturedMentors() {
        db.collection("mentorProfiles")
            .whereField("acceptingMentees", isEqualTo: true)
            .limit(to: 20)
            .getDocuments { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                self.featuredMentors = docs.compactMap {
                    try? Firestore.Decoder().decode(MentorProfile.self, from: $0.data())
                }
                self.isLoaded = true
            }
    }

    private func loadMyCircles(uid: String) {
        let listener = db.collection("accountabilityCircles")
            .whereField("memberUIDs", arrayContains: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                self.myCircles = docs.compactMap {
                    try? Firestore.Decoder().decode(AccountabilityCircle.self, from: $0.data())
                }
            }
        listeners.append(listener)
    }

    private func loadMentorProfile(uid: String) {
        db.collection("mentorProfiles").document(uid).getDocument { [weak self] snap, _ in
            guard let self, let data = snap?.data() else { return }
            self.myMentorProfile = try? Firestore.Decoder().decode(MentorProfile.self, from: data)
        }
    }

    func sendMentorRequest(_ request: MentorRequest) async throws {
        let encoded = try Firestore.Encoder().encode(request)
        try await db.collection("mentorRequests").document(request.id).setData(encoded)
    }

    func createCircle(_ circle: AccountabilityCircle) async throws {
        let encoded = try Firestore.Encoder().encode(circle)
        try await db.collection("accountabilityCircles").document(circle.id).setData(encoded)
    }

    func postCheckIn(_ checkIn: CircleCheckIn) async throws {
        let encoded = try Firestore.Encoder().encode(checkIn)
        try await db.collection("circleCheckIns").document(checkIn.id).setData(encoded)
        // Update circle last activity
        try await db.collection("accountabilityCircles")
            .document(checkIn.circleID)
            .updateData(["lastActivityAt": Date()])
    }

    func joinCircle(inviteCode: String) async throws -> AccountabilityCircle? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await db.collection("accountabilityCircles")
            .whereField("inviteCode", isEqualTo: inviteCode)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snap.documents.first,
              var circle = try? Firestore.Decoder().decode(AccountabilityCircle.self, from: doc.data()) else {
            return nil
        }
        guard circle.memberUIDs.count < circle.maxMembers, !circle.memberUIDs.contains(uid) else { return nil }
        circle.memberUIDs.append(uid)
        let encoded = try Firestore.Encoder().encode(circle)
        try await db.collection("accountabilityCircles").document(circle.id).setData(encoded)
        return circle
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
    }
}

// MARK: - Static Track Data

private let discipleshipTracks: [DiscipleshipTrack] = [
    DiscipleshipTrack(
        title: "Foundations of Faith",
        description: "A 4-week journey through the core beliefs that anchor a life of faith.",
        icon: "book.closed.fill",
        color: Color(red: 0.15, green: 0.45, blue: 0.82),
        duration: "4 Weeks",
        weekCount: 4,
        steps: [
            TrackStep(week: 1, title: "Who Is God?", scripture: "John 1:1-14", action: "Read John 1 and journal 3 things God revealed about Himself.", reflection: "How does knowing God as Creator change how you see your day?"),
            TrackStep(week: 2, title: "Grace & Salvation", scripture: "Ephesians 2:1-10", action: "Memorize Ephesians 2:8-9 this week.", reflection: "What does grace mean to you personally?"),
            TrackStep(week: 3, title: "Prayer & Listening", scripture: "Matthew 6:5-15", action: "Pray the Lord's Prayer aloud each morning this week.", reflection: "What do you find most difficult about prayer?"),
            TrackStep(week: 4, title: "Living It Out", scripture: "James 1:22-25", action: "Find one practical way to serve someone this week.", reflection: "How has your faith changed your actions this month?")
        ]
    ),
    DiscipleshipTrack(
        title: "Prayer Discipline",
        description: "Build a consistent, life-giving prayer practice in 6 weeks.",
        icon: "hands.sparkles.fill",
        color: Color(red: 0.42, green: 0.24, blue: 0.82),
        duration: "6 Weeks",
        weekCount: 6,
        steps: [
            TrackStep(week: 1, title: "Why Prayer Works", scripture: "Philippians 4:6-7", action: "Set a 7am prayer alarm. Pray for 5 minutes each morning.", reflection: "What anxieties are you bringing to God this week?"),
            TrackStep(week: 2, title: "Adoration & Praise", scripture: "Psalm 100", action: "Begin each prayer with 2 minutes of praise before any requests.", reflection: "What are you most grateful for right now?"),
            TrackStep(week: 3, title: "Intercession", scripture: "1 Timothy 2:1-4", action: "Write a prayer list of 5 people to pray for this week.", reflection: "How has praying for others changed your heart toward them?"),
            TrackStep(week: 4, title: "Listening Prayer", scripture: "1 Samuel 3:1-10", action: "Spend 5 minutes in silence after prayer, journaling what comes to mind.", reflection: "What do you sense God saying to you in the quiet?"),
            TrackStep(week: 5, title: "Fasting & Prayer", scripture: "Matthew 6:16-18", action: "Try a 24-hour fast (from social media if food is not appropriate).", reflection: "What distracted you from God this week that you want less of?"),
            TrackStep(week: 6, title: "Building a Rhythm", scripture: "Daniel 6:10", action: "Design your personal prayer rhythm for life beyond this track.", reflection: "What does a sustainable prayer life look like for you?")
        ]
    ),
    DiscipleshipTrack(
        title: "Scripture & Wisdom",
        description: "Learn to study the Bible deeply and apply it to real life in 5 weeks.",
        icon: "text.book.closed.fill",
        color: Color(red: 0.18, green: 0.55, blue: 0.45),
        duration: "5 Weeks",
        weekCount: 5,
        steps: [
            TrackStep(week: 1, title: "How to Read Scripture", scripture: "2 Timothy 3:16-17", action: "Read one chapter of Proverbs per day this week (start at 1).", reflection: "What kind of wisdom are you most hungry for right now?"),
            TrackStep(week: 2, title: "Context & Meaning", scripture: "Nehemiah 8:8", action: "Look up one verse in its historical context using a commentary or Bible app.", reflection: "How did the original context change what the verse means to you?"),
            TrackStep(week: 3, title: "Memorization", scripture: "Psalm 119:11", action: "Memorize one full verse this week — choose one that speaks to you.", reflection: "Why is hiding scripture in your heart a form of spiritual protection?"),
            TrackStep(week: 4, title: "Application", scripture: "Luke 6:46-49", action: "Identify one life situation where a scripture principle needs to change your behavior.", reflection: "Where is the gap between what you believe and how you live?"),
            TrackStep(week: 5, title: "Teaching Others", scripture: "Deuteronomy 6:6-9", action: "Share one thing you learned from the Bible this week with someone.", reflection: "How does teaching what you know deepen your own understanding?")
        ]
    ),
    DiscipleshipTrack(
        title: "Identity in Christ",
        description: "A 3-week deep dive into who God says you are.",
        icon: "person.fill.checkmark",
        color: Color(red: 0.85, green: 0.47, blue: 0.10),
        duration: "3 Weeks",
        weekCount: 3,
        steps: [
            TrackStep(week: 1, title: "Made in God's Image", scripture: "Genesis 1:26-27", action: "Write down 5 lies you believe about yourself. Then find a scripture that speaks truth over each one.", reflection: "Where do you most struggle to believe God loves you unconditionally?"),
            TrackStep(week: 2, title: "Redeemed & Forgiven", scripture: "Romans 8:1-2", action: "Confess one area of shame to a trusted person or mentor this week.", reflection: "What would change if you fully believed there is no condemnation for you?"),
            TrackStep(week: 3, title: "Called & Sent", scripture: "Ephesians 2:10", action: "Write your personal mission statement: 'I am created to ___.'", reflection: "What gifts and experiences has God given you that only you can bring to the world?")
        ]
    )
]

// MARK: - Main View

struct MentorshipView: View {
    @StateObject private var store = MentorshipStore.shared
    @State private var selectedTab: MentorshipTab = .find
    @State private var showRequestSheet = false
    @State private var showCreateCircle = false
    @State private var showJoinCircle = false
    @State private var showCheckIn = false
    @State private var showTrackDetail = false
    @State private var selectedMentor: MentorProfile?
    @State private var selectedCircle: AccountabilityCircle?
    @State private var selectedTrack: DiscipleshipTrack?
    @State private var appeared = false

    private let navy  = Color(red: 0.08, green: 0.10, blue: 0.22)
    private let green = Color(red: 0.18, green: 0.62, blue: 0.36)

    enum MentorshipTab: String, CaseIterable {
        case find    = "Find Mentor"
        case circles = "My Circles"
        case tracks  = "Grow"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroHeader
                    tabPills
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                    Divider().opacity(0.3).padding(.horizontal, 20)

                    switch selectedTab {
                    case .find:    findMentorView
                    case .circles: circlesView
                    case .tracks:  tracksView
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showRequestSheet) {
            if let mentor = selectedMentor {
                MentorRequestSheet(mentor: mentor)
            }
        }
        .sheet(isPresented: $showCreateCircle) {
            CreateCircleSheet()
        }
        .sheet(isPresented: $showJoinCircle) {
            JoinCircleSheet()
        }
        .sheet(isPresented: $showCheckIn) {
            if let circle = selectedCircle {
                CircleCheckInSheet(circle: circle)
            }
        }
        .sheet(isPresented: $showTrackDetail) {
            if let track = selectedTrack {
                TrackDetailSheet(track: track)
            }
        }
        .onAppear {
            store.loadAll()
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [navy, Color(red: 0.12, green: 0.22, blue: 0.50)],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            .frame(minHeight: 180)

            // Decorative circles
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 120, height: 120)
                .offset(x: -20, y: 30)
            Circle()
                .fill(green.opacity(0.18))
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 30)
                .offset(y: -20)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Text("Mentor")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                    Text("ship")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(
                            LinearGradient(colors: [green, Color(red: 0.55, green: 0.95, blue: 0.65)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Circle().fill(green).frame(width: 7, height: 7).offset(x: 3, y: 4)
                }
                Text("Grow together · Be accountable · Disciple one another")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .scaleEffect(appeared ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Tab Pills

    private var tabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MentorshipTab.allCases, id: \.self) { tab in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.custom(selectedTab == tab ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                            .foregroundStyle(selectedTab == tab ? .white : Color(.label).opacity(0.65))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(selectedTab == tab ? navy : Color(.secondarySystemBackground))
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Find Mentor Tab

    private var findMentorView: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available Mentors")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    Text("Faith-verified leaders ready to walk with you")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if store.featuredMentors.isEmpty && store.isLoaded {
                emptyMentorsView
            } else if store.featuredMentors.isEmpty {
                loadingMentorsView
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.featuredMentors) { mentor in
                        MentorCard(mentor: mentor) {
                            selectedMentor = mentor
                            showRequestSheet = true
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 4)
            }

            // Static demo mentor cards if no Firestore data yet
            if store.featuredMentors.isEmpty && store.isLoaded {
                LazyVStack(spacing: 12) {
                    ForEach(demoMentors) { mentor in
                        MentorCard(mentor: mentor) {
                            selectedMentor = mentor
                            showRequestSheet = true
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var emptyMentorsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("Mentors coming soon")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            Text("Be among the first to offer mentorship to others in this community.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var loadingMentorsView: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 120)
                    .padding(.horizontal, 20)
            }
        }
        .redacted(reason: .placeholder)
        .padding(.top, 8)
    }

    // MARK: Circles Tab

    private var circlesView: some View {
        VStack(spacing: 0) {
            // Action buttons row
            HStack(spacing: 12) {
                Button {
                    showCreateCircle = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Create Circle")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(navy))
                }
                .buttonStyle(ResourceCardPressStyle())

                Button {
                    showJoinCircle = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Join Circle")
                            .font(.custom("OpenSans-Bold", size: 14))
                    }
                    .foregroundStyle(navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(navy.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(navy.opacity(0.25), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(ResourceCardPressStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if store.myCircles.isEmpty {
                emptyCirclesView
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.myCircles) { circle in
                        CircleCard(circle: circle) {
                            selectedCircle = circle
                            showCheckIn = true
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 4)
            }

            // What is a circle? info banner
            infoCard(
                icon: "person.3.sequence.fill",
                title: "What is an Accountability Circle?",
                body: "A small group of 2–8 people who meet regularly (weekly or bi-weekly) to share how they're growing, pray together, and hold each other accountable to their spiritual goals.",
                accentColor: Color(red: 0.42, green: 0.24, blue: 0.82)
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }

    private var emptyCirclesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No circles yet")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            Text("Create your own accountability circle or join one with an invite code.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Tracks Tab

    private var tracksView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discipleship Tracks")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    Text("Guided plans for every stage of faith")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            LazyVStack(spacing: 14) {
                ForEach(discipleshipTracks) { track in
                    Button {
                        selectedTrack = track
                        showTrackDetail = true
                    } label: {
                        TrackCard(track: track)
                    }
                    .buttonStyle(ResourceCardPressStyle())
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: Info Card

    private func infoCard(icon: String, title: String, body: String, accentColor: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Mentor Card

struct MentorCard: View {
    let mentor: MentorProfile
    let onTap: () -> Void
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 54, height: 54)
                        if mentor.photoURL.isEmpty {
                            Text(String(mentor.displayName.prefix(1)))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            AsyncImage(url: URL(string: mentor.photoURL)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                        }
                        // Verified badge
                        if mentor.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.82))
                                .background(Circle().fill(Color(.systemBackground)).padding(-2))
                                .offset(x: 18, y: 18)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(mentor.displayName.isEmpty ? "Community Mentor" : mentor.displayName)
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.primary)
                            if !mentor.isVerified {
                                EmptyView()
                            }
                        }
                        if !mentor.role.isEmpty {
                            Text(mentor.role + (mentor.church.isEmpty ? "" : " · \(mentor.church)"))
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !mentor.bio.isEmpty {
                            Text(mentor.bio)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    // Availability indicator
                    VStack(alignment: .trailing, spacing: 4) {
                        Circle()
                            .fill(mentor.acceptingMentees ? Color(red: 0.18, green: 0.62, blue: 0.36) : Color(.secondaryLabel))
                            .frame(width: 8, height: 8)
                        Text(mentor.acceptingMentees ? "Open" : "Full")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Specialties
                if !mentor.specialties.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(mentor.specialties.prefix(4), id: \.self) { specialty in
                                Text(specialty)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.82))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.15, green: 0.45, blue: 0.82).opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                // CTA row
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Request Mentorship")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.22))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.10, blue: 0.22).opacity(0.08))
                    )
                }
                .padding(.top, 12)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double.random(in: 0...0.15))) {
                appeared = true
            }
        }
    }
}

// MARK: - Circle Card

struct CircleCard: View {
    let circle: AccountabilityCircle
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.name.isEmpty ? "My Circle" : circle.name)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    Text("\(circle.memberUIDs.count)/\(circle.maxMembers) members · \(circle.checkInFrequency) check-ins")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !circle.focusArea.isEmpty {
                Text("Focus: \(circle.focusArea)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }

            Button(action: onCheckIn) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Check In Now")
                        .font(.custom("OpenSans-Bold", size: 14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.42, green: 0.24, blue: 0.82))
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Track Card

struct TrackCard: View {
    let track: DiscipleshipTrack

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(track.color.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: track.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(track.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(track.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(track.duration)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                Text(track.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(track.color.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Mentor Request Sheet

struct MentorRequestSheet: View {
    let mentor: MentorProfile
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var goal = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    private let maxChars = 300

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Mentor mini-card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color(.secondarySystemBackground)).frame(width: 52, height: 52)
                            Text(String(mentor.displayName.prefix(1)))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mentor.displayName.isEmpty ? "Community Mentor" : mentor.displayName)
                                .font(.custom("OpenSans-Bold", size: 16))
                            Text(mentor.role.isEmpty ? "Mentor" : mentor.role)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                    // Goal field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you hope to gain from mentorship?")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.primary)
                        TextEditor(text: $goal)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .frame(height: 80)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }

                    // Message field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Personal message to \(mentor.displayName.isEmpty ? "mentor" : mentor.displayName.components(separatedBy: " ").first ?? "mentor")")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(message.count)/\(maxChars)")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: Binding(
                            get: { message },
                            set: { message = String($0.prefix(maxChars)) }
                        ))
                        .font(.custom("OpenSans-Regular", size: 15))
                        .frame(height: 110)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }

                    // Privacy note
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Your request is private. Only the mentor will see your message.")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))

                    // Submit
                    Button {
                        submitRequest()
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Send Request")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(message.count > 10 && !goal.isEmpty
                                      ? Color(red: 0.08, green: 0.10, blue: 0.22)
                                      : Color(.tertiaryLabel))
                        )
                    }
                    .disabled(message.count <= 10 || goal.isEmpty || isSubmitting)
                    .buttonStyle(ResourceCardPressStyle())
                }
                .padding(20)
            }
            .navigationTitle("Request Mentorship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Request Sent!", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your mentorship request has been sent. You'll be notified when \(mentor.displayName.isEmpty ? "the mentor" : mentor.displayName.components(separatedBy: " ").first ?? "the mentor") responds.")
        }
    }

    private func submitRequest() {
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser else { return }
        isSubmitting = true
        var req = MentorRequest()
        req.fromUID = uid
        req.toUID = mentor.uid
        req.fromName = user.displayName ?? "A fellow believer"
        req.fromPhotoURL = user.photoURL?.absoluteString ?? ""
        req.message = message
        req.goal = goal
        Task {
            try? await MentorshipStore.shared.sendMentorRequest(req)
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
            }
        }
    }
}

// MARK: - Create Circle Sheet

struct CreateCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var focusArea = ""
    @State private var frequency = "Weekly"
    @State private var maxMembers = 6
    @State private var isPrivate = true
    @State private var isCreating = false
    @State private var showSuccess = false

    private let frequencies = ["Daily", "Weekly", "Biweekly", "Monthly"]
    private let focusAreas = ["Prayer", "Bible Reading", "Sobriety & Recovery", "Marriage", "Career & Work",
                               "Grief & Loss", "New Believers", "Faith & Doubt", "General Accountability"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Circle Details") {
                    TextField("Circle Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3)
                }

                Section("Focus Area") {
                    Picker("Focus", selection: $focusArea) {
                        Text("Select...").tag("")
                        ForEach(focusAreas, id: \.self) { area in
                            Text(area).tag(area)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Settings") {
                    Picker("Check-in Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }
                    Stepper("Max Members: \(maxMembers)", value: $maxMembers, in: 2...12)
                    Toggle("Private Circle", isOn: $isPrivate)
                }

                Section {
                    Button {
                        createCircle()
                    } label: {
                        HStack {
                            Spacer()
                            Group {
                                if isCreating {
                                    ProgressView()
                                } else {
                                    Text("Create Circle")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                }
                            }
                            .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(name.count >= 3 ? Color(red: 0.42, green: 0.24, blue: 0.82) : Color(.tertiaryLabel))
                        )
                    }
                    .disabled(name.count < 3 || focusArea.isEmpty || isCreating)
                }
            }
            .navigationTitle("Create Accountability Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Circle Created!", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Share your invite code with members to grow your circle.")
        }
    }

    private func createCircle() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isCreating = true
        var circle = AccountabilityCircle()
        circle.name = name
        circle.description = description
        circle.focusArea = focusArea
        circle.checkInFrequency = frequency
        circle.maxMembers = maxMembers
        circle.isPrivate = isPrivate
        circle.createdByUID = uid
        circle.memberUIDs = [uid]
        circle.inviteCode = String(circle.id.prefix(6).uppercased())
        Task {
            try? await MentorshipStore.shared.createCircle(circle)
            await MainActor.run {
                isCreating = false
                showSuccess = true
            }
        }
    }
}

// MARK: - Join Circle Sheet

struct JoinCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var isJoining = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                    .padding(.top, 20)

                Text("Join a Circle")
                    .font(.custom("OpenSans-Bold", size: 22))
                Text("Enter the invite code shared by your circle leader.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                TextField("Invite Code (e.g. ABC123)", text: $inviteCode)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 40)
                    .onChange(of: inviteCode) { _, v in
                        inviteCode = String(v.uppercased().prefix(6))
                    }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.red)
                }

                Button {
                    joinCircle()
                } label: {
                    Group {
                        if isJoining {
                            ProgressView().tint(.white)
                        } else {
                            Text("Join Circle")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(inviteCode.count == 6
                                  ? Color(red: 0.42, green: 0.24, blue: 0.82)
                                  : Color(.tertiaryLabel))
                    )
                }
                .padding(.horizontal, 40)
                .disabled(inviteCode.count < 6 || isJoining)
                .buttonStyle(ResourceCardPressStyle())

                Spacer()
            }
            .navigationTitle("Join Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .alert("Joined!", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("You've joined the accountability circle. Check in soon!")
        }
    }

    private func joinCircle() {
        isJoining = true
        errorMessage = ""
        Task {
            let circle = try? await MentorshipStore.shared.joinCircle(inviteCode: inviteCode)
            await MainActor.run {
                isJoining = false
                if circle != nil {
                    showSuccess = true
                } else {
                    errorMessage = "Invite code not found or circle is full. Check the code and try again."
                }
            }
        }
    }
}

// MARK: - Circle Check-In Sheet

struct CircleCheckInSheet: View {
    let circle: AccountabilityCircle
    @Environment(\.dismiss) private var dismiss
    @State private var mood: CircleCheckInMood = .growing
    @State private var note = ""
    @State private var prayerRequest = ""
    @State private var isPosting = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Circle name
                    VStack(spacing: 4) {
                        Text("Checking in to")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                        Text(circle.name.isEmpty ? "My Circle" : circle.name)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.primary)
                    }
                    .padding(.top, 8)

                    // Mood selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How are you doing?")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        HStack(spacing: 10) {
                            ForEach(CircleCheckInMood.allCases, id: \.self) { m in
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { mood = m }
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(m.emoji).font(.system(size: 24))
                                        Text(m.rawValue)
                                            .font(.custom("OpenSans-Regular", size: 10))
                                            .foregroundStyle(mood == m ? .white : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(mood == m ? m.color : Color(.secondarySystemBackground))
                                    )
                                }
                            }
                        }
                    }

                    // Note
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share a brief update")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        TextEditor(text: $note)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .frame(height: 90)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }

                    // Prayer request
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prayer request (optional)")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        TextEditor(text: $prayerRequest)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .frame(height: 80)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    }

                    Button {
                        postCheckIn()
                    } label: {
                        Group {
                            if isPosting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Post Check-In")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(!note.isEmpty ? Color(red: 0.42, green: 0.24, blue: 0.82) : Color(.tertiaryLabel))
                        )
                    }
                    .disabled(note.isEmpty || isPosting)
                    .buttonStyle(ResourceCardPressStyle())
                }
                .padding(20)
            }
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Check-in Shared", isPresented: $showSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your circle members will be notified.")
        }
    }

    private func postCheckIn() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isPosting = true
        var checkIn = CircleCheckIn()
        checkIn.circleID = circle.id
        checkIn.uid = uid
        checkIn.displayName = Auth.auth().currentUser?.displayName ?? ""
        checkIn.mood = mood
        checkIn.note = note
        checkIn.prayerRequest = prayerRequest
        Task {
            try? await MentorshipStore.shared.postCheckIn(checkIn)
            await MainActor.run {
                isPosting = false
                showSuccess = true
            }
        }
    }
}

// MARK: - Track Detail Sheet

struct TrackDetailSheet: View {
    let track: DiscipleshipTrack
    @Environment(\.dismiss) private var dismiss
    @State private var currentWeek = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Track hero
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [track.color.opacity(0.8), track.color],
                            startPoint: .topTrailing, endPoint: .bottomLeading
                        )
                        .frame(height: 160)

                        Image(systemName: track.icon)
                            .font(.system(size: 100, weight: .ultraLight))
                            .foregroundStyle(Color.white.opacity(0.06))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 20).padding(.trailing, 20)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(.white)
                            Text(track.description)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }

                    // Week picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(1...track.weekCount, id: \.self) { week in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        currentWeek = week
                                    }
                                } label: {
                                    Text("Week \(week)")
                                        .font(.custom(currentWeek == week ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                                        .foregroundStyle(currentWeek == week ? .white : Color(.label).opacity(0.65))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(currentWeek == week ? track.color : Color(.secondarySystemBackground)))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }

                    // Week content
                    if let step = track.steps.first(where: { $0.week == currentWeek }) {
                        VStack(spacing: 16) {
                            stepCard(icon: "book.closed.fill", title: "This Week: \(step.title)", color: track.color) {
                                Text(step.scripture)
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(track.color)
                            }
                            stepCard(icon: "sparkles", title: "Your Action", color: Color(red: 0.18, green: 0.62, blue: 0.36)) {
                                Text(step.action)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                            stepCard(icon: "bubble.left.fill", title: "Reflection Question", color: Color(red: 0.90, green: 0.47, blue: 0.10)) {
                                Text(step.reflection)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .italic()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Track") { dismiss() }
                        .font(.custom("OpenSans-Bold", size: 15))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func stepCard<Content: View>(icon: String, title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Demo Mentor Data (shown when Firestore is empty)

private let demoMentors: [MentorProfile] = [
    MentorProfile(
        id: "demo1", uid: "demo1",
        displayName: "Marcus Thompson", photoURL: "",
        bio: "Marriage counselor and elder at Cornerstone Church. Walking with men through career transitions, relationship challenges, and growing in faith.",
        role: "Church Elder", church: "Cornerstone Church",
        specialties: ["Marriage", "Career", "New Believers"],
        availabilityNote: "Available weekday evenings",
        maxMentees: 3, currentMenteeCount: 1,
        isVerified: true, verificationBadge: "Church Elder",
        yearsOfFaith: 22, denomination: "Baptist",
        acceptingMentees: true, rating: 4.9, reviewCount: 28
    ),
    MentorProfile(
        id: "demo2", uid: "demo2",
        displayName: "Priya Anand", photoURL: "",
        bio: "Worship leader and licensed counselor. Passionate about helping women navigate faith, identity, and emotional health.",
        role: "Worship Leader & Counselor", church: "Grace Vineyard",
        specialties: ["Identity in Christ", "Emotional Health", "Worship"],
        availabilityNote: "Saturday mornings",
        maxMentees: 4, currentMenteeCount: 2,
        isVerified: true, verificationBadge: "Licensed Counselor",
        yearsOfFaith: 15, denomination: "Vineyard",
        acceptingMentees: true, rating: 4.8, reviewCount: 19
    ),
    MentorProfile(
        id: "demo3", uid: "demo3",
        displayName: "David Okonkwo", photoURL: "",
        bio: "Pastor and entrepreneur. Helping young professionals align their work with their faith and build Kingdom-centered businesses.",
        role: "Pastor & Entrepreneur", church: "Impact City Church",
        specialties: ["Business", "Leadership", "Faith & Work"],
        availabilityNote: "Mornings & lunch hours",
        maxMentees: 5, currentMenteeCount: 3,
        isVerified: true, verificationBadge: "Ordained Pastor",
        yearsOfFaith: 18, denomination: "Non-Denominational",
        acceptingMentees: true, rating: 4.95, reviewCount: 42
    )
]
