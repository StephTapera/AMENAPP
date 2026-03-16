// ChurchToolsView.swift
// AMENAPP
//
// Church tools — digital bulletin, announcements, small groups,
// serving signup, newcomer welcome flow, ministry teams, weekly schedule.
// Designed for church members AND leaders.

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Data Models

struct ChurchBulletin: Identifiable, Codable {
    var id: String = UUID().uuidString
    var churchID: String = ""
    var churchName: String = ""
    var weekOf: Date = Date()
    var sermonTitle: String = ""
    var sermonSeries: String = ""
    var pastoralNote: String = ""
    var announcements: [BulletinAnnouncement] = []
    var upcomingEvents: [String] = []          // Event titles
    var scriptureOfWeek: String = ""
    var givingInfo: GivingInfo = GivingInfo()
    var serviceSchedule: [ServiceTime] = []
    var createdAt: Date = Date()
    var isPublic: Bool = true
}

struct BulletinAnnouncement: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var body: String = ""
    var category: String = ""             // e.g. "Volunteer", "Youth", "Giving"
    var actionLabel: String = ""          // e.g. "Sign Up", "Learn More"
    var actionURL: String = ""
    var isPinned: Bool = false
    var isUrgent: Bool = false
    var expiresAt: Date?
}

struct GivingInfo: Codable {
    var percentage: Double = 0           // % of giving goal reached (0–1)
    var goalLabel: String = ""           // e.g. "Building Fund: $45k of $60k"
    var givingURL: String = ""
    var venmoHandle: String = ""
    var cashAppHandle: String = ""
    var zelleInfo: String = ""
}

struct ServiceTime: Identifiable, Codable {
    var id: String = UUID().uuidString
    var day: String = ""                 // e.g. "Sunday"
    var time: String = ""               // e.g. "9:00 AM"
    var description: String = ""        // e.g. "Main Service", "Youth Service"
    var location: String = ""
}

struct SmallGroup: Identifiable, Codable {
    var id: String = UUID().uuidString
    var churchID: String = ""
    var name: String = ""
    var description: String = ""
    var leaderName: String = ""
    var leaderUID: String = ""
    var meetingDay: String = ""
    var meetingTime: String = ""
    var location: String = ""
    var isOnline: Bool = false
    var category: String = ""           // e.g. "Bible Study", "Recovery", "Young Adults"
    var currentMembers: Int = 0
    var maxMembers: Int = 20
    var isAcceptingMembers: Bool = true
    var ageRange: String = ""           // e.g. "18-30", "All Ages"
    var createdAt: Date = Date()
}

struct ServingRole: Identifiable, Codable {
    var id: String = UUID().uuidString
    var churchID: String = ""
    var title: String = ""
    var description: String = ""
    var ministry: String = ""           // e.g. "Worship", "Children's", "Tech", "Hospitality"
    var commitment: String = ""         // e.g. "Weekly", "Monthly", "As needed"
    var openSpots: Int = 0
    var requirements: [String] = []     // e.g. "Background check", "16+ years old"
    var contactUID: String = ""
    var contactName: String = ""
    var isUrgent: Bool = false
}

// MARK: - Church Tools Store

@MainActor
final class ChurchToolsStore: ObservableObject {
    static let shared = ChurchToolsStore()

    @Published var currentBulletin: ChurchBulletin?
    @Published var smallGroups: [SmallGroup] = []
    @Published var servingRoles: [ServingRole] = []
    @Published var joinedGroupIDs: [String] = []
    @Published var signedUpRoleIDs: [String] = []
    @Published var isLoaded = false

    private let db = Firestore.firestore()
    private init() {}

    func loadTools(churchID: String = "default") {
        loadBulletin(churchID: churchID)
        loadSmallGroups(churchID: churchID)
        loadServingRoles(churchID: churchID)
    }

    private func loadBulletin(churchID: String) {
        db.collection("churchBulletins")
            .whereField("churchID", isEqualTo: churchID)
            .order(by: "weekOf", descending: true)
            .limit(to: 1)
            .getDocuments { [weak self] snap, _ in
                let bulletin = snap?.documents.first.flatMap {
                    try? Firestore.Decoder().decode(ChurchBulletin.self, from: $0.data())
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentBulletin = bulletin ?? Self.demoBulletin
                    self.isLoaded = true
                }
            }
    }

    private func loadSmallGroups(churchID: String) {
        db.collection("smallGroups")
            .order(by: "createdAt", descending: false)
            .limit(to: 30)
            .getDocuments { [weak self] snap, _ in
                let loaded = snap?.documents.compactMap {
                    try? Firestore.Decoder().decode(SmallGroup.self, from: $0.data())
                } ?? []
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.smallGroups = loaded.isEmpty ? Self.demoGroups : loaded
                }
            }
    }

    private func loadServingRoles(churchID: String) {
        db.collection("servingRoles")
            .order(by: "isUrgent", descending: true)
            .limit(to: 20)
            .getDocuments { [weak self] snap, _ in
                let loaded = snap?.documents.compactMap {
                    try? Firestore.Decoder().decode(ServingRole.self, from: $0.data())
                } ?? []
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.servingRoles = loaded.isEmpty ? Self.demoRoles : loaded
                }
            }
    }

    func joinGroup(_ groupID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await db.collection("smallGroups").document(groupID).updateData([
            "currentMembers": FieldValue.increment(Int64(1))
        ])
        try await db.collection("groupMemberships").document("\(uid)_\(groupID)").setData([
            "uid": uid, "groupID": groupID, "joinedAt": Date()
        ])
        joinedGroupIDs.append(groupID)
    }

    func signUpToServe(_ roleID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser else { return }
        try await db.collection("servingSignups").document("\(uid)_\(roleID)").setData([
            "uid": uid,
            "roleID": roleID,
            "displayName": user.displayName ?? "",
            "signedUpAt": Date()
        ])
        signedUpRoleIDs.append(roleID)
    }

    // MARK: Demo Data

    static let demoBulletin: ChurchBulletin = {
        var b = ChurchBulletin()
        b.churchName = "Grace Community Church"
        b.weekOf = Date()
        b.sermonTitle = "Walking in the Light"
        b.sermonSeries = "Letters of John — Week 3"
        b.pastoralNote = "Dear family, this week we continue our study of 1 John, exploring what it means to walk authentically in love and truth. We hope to see you Sunday!"
        b.scriptureOfWeek = "1 John 1:7 — \"But if we walk in the light, as he is in the light, we have fellowship with one another, and the blood of Jesus his Son cleanses us from all sin.\""
        b.serviceSchedule = [
            ServiceTime(id: "s1", day: "Sunday", time: "8:30 AM", description: "Early Service", location: "Sanctuary"),
            ServiceTime(id: "s2", day: "Sunday", time: "10:30 AM", description: "Main Service", location: "Sanctuary"),
            ServiceTime(id: "s3", day: "Sunday", time: "12:30 PM", description: "Spanish Service", location: "Chapel"),
            ServiceTime(id: "s4", day: "Wednesday", time: "7:00 PM", description: "Midweek Prayer", location: "Fellowship Hall")
        ]
        b.announcements = [
            BulletinAnnouncement(id: "a1", title: "Baptism Sunday — April 13", body: "We'll be celebrating water baptism next Sunday! If you'd like to be baptized or know someone who would, speak with Pastor James after service.", category: "Milestone", actionLabel: "Sign Up", isPinned: true),
            BulletinAnnouncement(id: "a2", title: "Community Serve Day — April 19", body: "Join us as we serve our city! We'll be partnering with the food bank and local shelter. Sign up at the info table.", category: "Serve", actionLabel: "Sign Up"),
            BulletinAnnouncement(id: "a3", title: "Women's Bible Study — New Series", body: "Starting this Thursday, women's Bible study begins a new 6-week series on identity in Christ. All women welcome.", category: "Bible Study"),
            BulletinAnnouncement(id: "a4", title: "Tech Team Volunteers Needed", body: "We need help in our audio/visual and live stream team. No experience necessary — we'll train you!", category: "Volunteer", isUrgent: true)
        ]
        b.givingInfo = GivingInfo(
            percentage: 0.72,
            goalLabel: "Building Fund: 72% of $60,000 goal",
            givingURL: "https://gracecommunity.church/give",
            venmoHandle: "@GraceCommunityChurch",
            cashAppHandle: "$GraceCommunityCC"
        )
        return b
    }()

    static let demoGroups: [SmallGroup] = [
        SmallGroup(id: "g1", churchID: "default", name: "Young Adults (20s–30s)", description: "A community for young adults navigating faith, career, and life. We meet weekly for Bible study, worship, and real conversation.", leaderName: "Alex & Jordan Kim", meetingDay: "Thursday", meetingTime: "7:00 PM", location: "123 Oak Street", category: "Young Adults", currentMembers: 12, maxMembers: 20, isAcceptingMembers: true, ageRange: "18-35"),
        SmallGroup(id: "g2", churchID: "default", name: "Men's Accountability", description: "Iron sharpens iron. Men supporting men through prayer, scripture, and honesty.", leaderName: "Pastor Marcus", meetingDay: "Saturday", meetingTime: "7:00 AM", location: "Church Cafe", category: "Men's Ministry", currentMembers: 8, maxMembers: 12, isAcceptingMembers: true, ageRange: "21+"),
        SmallGroup(id: "g3", churchID: "default", name: "Grief Support Group", description: "A safe, compassionate space for those processing loss. Led by certified grief counselor Rachel James.", leaderName: "Rachel James", meetingDay: "Tuesday", meetingTime: "6:30 PM", location: "Room 204", category: "Support", currentMembers: 7, maxMembers: 10, isAcceptingMembers: true, ageRange: "All Ages"),
        SmallGroup(id: "g4", churchID: "default", name: "Married Couples Growth", description: "Strengthen your marriage through faith-based principles, honest conversation, and shared study.", leaderName: "David & Lisa Chen", meetingDay: "Friday", meetingTime: "7:00 PM", location: "Fellowship Hall", category: "Marriage", currentMembers: 10, maxMembers: 16, isAcceptingMembers: true, ageRange: "All Ages"),
        SmallGroup(id: "g5", churchID: "default", name: "Online Evening Study", description: "Can't make it in person? Join our online mid-week study via video call. All time zones welcome.", leaderName: "Deacon Thomas", meetingDay: "Wednesday", meetingTime: "8:00 PM", location: "Online (Zoom)", isOnline: true, category: "Bible Study", currentMembers: 22, maxMembers: 50, isAcceptingMembers: true, ageRange: "All Ages")
    ]

    static let demoRoles: [ServingRole] = [
        ServingRole(id: "r1", churchID: "default", title: "Sunday Greeter", description: "Welcome guests and members as they arrive. Creates the first impression of our church community.", ministry: "Hospitality", commitment: "1–2 Sundays/month", openSpots: 5, requirements: [], contactName: "Sandra Lee", isUrgent: false),
        ServingRole(id: "r2", churchID: "default", title: "Kids Church Teacher", description: "Lead age-appropriate Bible lessons for children ages 3–10. Materials provided.", ministry: "Children's Ministry", commitment: "Weekly", openSpots: 3, requirements: ["Background check required"], contactName: "Kim Osei", isUrgent: true),
        ServingRole(id: "r3", churchID: "default", title: "Worship Team Vocalist", description: "Sing on Sunday worship team. Rehearsal on Thursday nights.", ministry: "Worship", commitment: "Weekly", openSpots: 2, requirements: ["Audition required"], contactName: "Music Director Jamie"),
        ServingRole(id: "r4", churchID: "default", title: "A/V & Live Stream Tech", description: "Run cameras, sound board, or live stream setup. Training provided.", ministry: "Media & Tech", commitment: "1–2 Sundays/month", openSpots: 4, requirements: [], contactName: "Tech Coordinator", isUrgent: true),
        ServingRole(id: "r5", churchID: "default", title: "Food Pantry Volunteer", description: "Help distribute food to families in need every Saturday morning.", ministry: "Outreach", commitment: "1 Saturday/month", openSpots: 10, requirements: [], contactName: "Outreach Team")
    ]
}

// MARK: - Main View

struct ChurchToolsView: View {
    @StateObject private var store = ChurchToolsStore.shared
    @State private var selectedTab: ChurchTab = .bulletin
    @State private var appeared = false

    enum ChurchTab: String, CaseIterable {
        case bulletin  = "Bulletin"
        case groups    = "Groups"
        case serve     = "Serve"
        case schedule  = "Schedule"
    }

    private let blue = Color(red: 0.15, green: 0.32, blue: 0.72)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroHeader
                    tabPills.padding(.top, 16).padding(.bottom, 4)
                    Divider().opacity(0.3).padding(.horizontal, 20)

                    switch selectedTab {
                    case .bulletin:  bulletinTab
                    case .groups:    groupsTab
                    case .serve:     serveTab
                    case .schedule:  scheduleTab
                    }

                    Color.clear.frame(height: 100)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
        .onAppear {
            store.loadTools()
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.14, blue: 0.40), blue],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            .frame(minHeight: 175)

            Circle().fill(Color.white.opacity(0.05)).frame(width: 100).offset(x: -10, y: 25)
            Circle().fill(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.12)).frame(width: 60)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 25).offset(y: -20)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    Text("Church")
                        .font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                    Text(" Tools")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.65, green: 0.82, blue: 1.0), .white],
                                                        startPoint: .leading, endPoint: .trailing))
                    Circle().fill(Color(red: 0.45, green: 0.65, blue: 1.0)).frame(width: 7, height: 7)
                        .offset(x: 3, y: 4)
                }
                Text("Your digital church home — bulletin, groups, serving, and more")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }
            .padding(.horizontal, 20).padding(.bottom, 24).padding(.top, 52)
        }
        .scaleEffect(appeared ? 1 : 0.97).opacity(appeared ? 1 : 0)
    }

    // MARK: Tab Pills

    private var tabPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChurchTab.allCases, id: \.self) { tab in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.custom(selectedTab == tab ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                            .foregroundStyle(selectedTab == tab ? .white : Color(.label).opacity(0.65))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(selectedTab == tab ? blue : Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Bulletin Tab

    private var bulletinTab: some View {
        VStack(spacing: 0) {
            if let bulletin = store.currentBulletin {
                // Week header
                VStack(spacing: 4) {
                    Text(bulletin.churchName)
                        .font(.custom("OpenSans-Bold", size: 18)).foregroundStyle(.primary)
                    Text("Week of \(shortDate(bulletin.weekOf))")
                        .font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                Divider().padding(.horizontal, 20)

                // Sermon card
                if !bulletin.sermonTitle.isEmpty {
                    sermonCard(bulletin: bulletin)
                }

                // Scripture of the week
                if !bulletin.scriptureOfWeek.isEmpty {
                    scriptureCard(text: bulletin.scriptureOfWeek)
                }

                // Pastor's note
                if !bulletin.pastoralNote.isEmpty {
                    pastoralNoteCard(text: bulletin.pastoralNote)
                }

                // Announcements
                if !bulletin.announcements.isEmpty {
                    announcementsSection(bulletin.announcements)
                }

                // Giving info
                if !bulletin.givingInfo.goalLabel.isEmpty {
                    givingCard(info: bulletin.givingInfo)
                }

            } else {
                ProgressView().padding(.top, 40)
            }
        }
    }

    private func sermonCard(bulletin: ChurchBulletin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(blue.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Week's Message").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.secondary)
                    Text(bulletin.sermonTitle).font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(.primary)
                    if !bulletin.sermonSeries.isEmpty {
                        Text(bulletin.sermonSeries).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(blue.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 20).padding(.top, 16)
    }

    private func scriptureCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\"")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(blue.opacity(0.3))
                .offset(y: -8)
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary.opacity(0.85))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(blue.opacity(0.06)))
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private func pastoralNoteCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 13)).foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.10))
                Text("A Note from Your Pastor")
                    .font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(.primary)
            }
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 1.0, green: 0.96, blue: 0.88)))
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private func announcementsSection(_ announcements: [BulletinAnnouncement]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Announcements")
                .font(.custom("OpenSans-Bold", size: 18)).foregroundStyle(.primary)
                .padding(.horizontal, 20)

            ForEach(announcements) { announcement in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if announcement.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11)).foregroundStyle(blue)
                        }
                        Text(announcement.title)
                            .font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(.primary)
                        Spacer()
                        if !announcement.category.isEmpty {
                            Text(announcement.category)
                                .font(.custom("OpenSans-Regular", size: 10))
                                .foregroundStyle(blue)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(blue.opacity(0.1)))
                        }
                    }
                    Text(announcement.body)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !announcement.actionLabel.isEmpty {
                        Text(announcement.actionLabel)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(blue)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 20)
    }

    private func givingCard(info: GivingInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(Color(red: 0.15, green: 0.62, blue: 0.36))
                Text("Give").font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(.primary)
            }
            if !info.goalLabel.isEmpty {
                Text(info.goalLabel).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemBackground)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.15, green: 0.62, blue: 0.36))
                            .frame(width: geo.size.width * min(max(info.percentage, 0), 1), height: 6)
                    }
                }
                .frame(height: 6)
            }
            if !info.venmoHandle.isEmpty || !info.cashAppHandle.isEmpty {
                HStack(spacing: 10) {
                    if !info.venmoHandle.isEmpty {
                        givingMethod(icon: "v.circle.fill", label: info.venmoHandle, color: Color(red: 0.20, green: 0.40, blue: 0.85))
                    }
                    if !info.cashAppHandle.isEmpty {
                        givingMethod(icon: "dollarsign.circle.fill", label: info.cashAppHandle, color: Color(red: 0.15, green: 0.62, blue: 0.36))
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private func givingMethod(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
            Text(label).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
    }

    // MARK: Groups Tab

    private var groupsTab: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Small Groups")
                        .font(.custom("OpenSans-Bold", size: 20)).foregroundStyle(.primary)
                    Text("Find your community within the church")
                        .font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            LazyVStack(spacing: 12) {
                ForEach(store.smallGroups) { group in
                    SmallGroupCard(
                        group: group,
                        isJoined: store.joinedGroupIDs.contains(group.id)
                    ) {
                        Task { try? await store.joinGroup(group.id) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: Serve Tab

    private var serveTab: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Serving Opportunities")
                        .font(.custom("OpenSans-Bold", size: 20)).foregroundStyle(.primary)
                    Text("Use your gifts for God's kingdom")
                        .font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            LazyVStack(spacing: 12) {
                ForEach(store.servingRoles) { role in
                    ServingRoleCard(
                        role: role,
                        isSignedUp: store.signedUpRoleIDs.contains(role.id)
                    ) {
                        Task { try? await store.signUpToServe(role.id) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: Schedule Tab

    private var scheduleTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Service Schedule")
                    .font(.custom("OpenSans-Bold", size: 20)).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            let schedule = store.currentBulletin?.serviceSchedule ?? ChurchToolsStore.demoBulletin.serviceSchedule
            LazyVStack(spacing: 10) {
                ForEach(schedule) { service in
                    HStack(spacing: 14) {
                        VStack(spacing: 2) {
                            Text(service.day)
                                .font(.custom("OpenSans-Bold", size: 13))
                                .foregroundStyle(blue)
                            Text(service.time)
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 80)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(blue.opacity(0.08)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.description)
                                .font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.primary)
                            if !service.location.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin").font(.system(size: 11))
                                    Text(service.location)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2))
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - Small Group Card

struct SmallGroupCard: View {
    let group: SmallGroup
    let isJoined: Bool
    let onJoin: () -> Void
    @State private var appeared = false

    private let colors: [String: Color] = [
        "Young Adults": Color(red: 0.42, green: 0.24, blue: 0.82),
        "Men's Ministry": Color(red: 0.15, green: 0.45, blue: 0.82),
        "Women's Ministry": Color(red: 0.75, green: 0.25, blue: 0.55),
        "Marriage": Color(red: 0.90, green: 0.47, blue: 0.10),
        "Support": Color(red: 0.85, green: 0.32, blue: 0.32),
        "Bible Study": Color(red: 0.18, green: 0.55, blue: 0.45)
    ]

    private var accentColor: Color {
        colors[group.category] ?? Color(red: 0.15, green: 0.32, blue: 0.72)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accentColor.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "person.3.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.primary)
                    Text("\(group.meetingDay)s at \(group.meetingTime) · \(group.isOnline ? "Online" : group.location)")
                        .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(group.currentMembers)/\(group.maxMembers)")
                        .font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(.secondary)
                    Circle().fill(group.isAcceptingMembers ? Color(red: 0.18, green: 0.62, blue: 0.36) : Color(.secondaryLabel)).frame(width: 8, height: 8)
                }
            }

            if !group.description.isEmpty {
                Text(group.description)
                    .font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if !group.ageRange.isEmpty {
                    Label(group.ageRange, systemImage: "person.fill")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(accentColor.opacity(0.1)))
                }
                if !group.category.isEmpty {
                    Text(group.category)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                Spacer()
                if group.isAcceptingMembers && !isJoined {
                    Button(action: onJoin) {
                        Text("Join Group")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(accentColor))
                    }
                    .buttonStyle(ResourceCardPressStyle())
                } else if isJoined {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(accentColor)
                        Text("Joined").font(.custom("OpenSans-SemiBold", size: 12)).foregroundStyle(accentColor)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.12), lineWidth: 1))
        .scaleEffect(appeared ? 1 : 0.95).opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double.random(in: 0...0.12))) {
                appeared = true
            }
        }
    }
}

// MARK: - Serving Role Card

struct ServingRoleCard: View {
    let role: ServingRole
    let isSignedUp: Bool
    let onSignUp: () -> Void

    private let ministryColors: [String: Color] = [
        "Worship": Color(red: 0.42, green: 0.24, blue: 0.82),
        "Children's Ministry": Color(red: 0.90, green: 0.47, blue: 0.10),
        "Media & Tech": Color(red: 0.15, green: 0.45, blue: 0.82),
        "Hospitality": Color(red: 0.18, green: 0.62, blue: 0.36),
        "Outreach": Color(red: 0.85, green: 0.32, blue: 0.32)
    ]

    private var accentColor: Color {
        ministryColors[role.ministry] ?? Color(red: 0.15, green: 0.32, blue: 0.72)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if role.isUrgent {
                            Text("URGENT")
                                .font(.system(size: 9, weight: .bold)).kerning(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color(red: 0.85, green: 0.20, blue: 0.20)))
                        }
                        Text(role.ministry)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(accentColor.opacity(0.1)))
                    }
                    Text(role.title).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.primary)
                }
                Spacer()
                if role.openSpots > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(role.openSpots)").font(.system(size: 18, weight: .black)).foregroundStyle(accentColor)
                        Text("open").font(.custom("OpenSans-Regular", size: 10)).foregroundStyle(.secondary)
                    }
                }
            }

            Text(role.description)
                .font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                if !role.commitment.isEmpty {
                    Label(role.commitment, systemImage: "clock")
                        .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.secondary)
                }
                if !role.requirements.isEmpty {
                    Label(role.requirements.first ?? "", systemImage: "checkmark.shield")
                        .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !isSignedUp {
                Button(action: onSignUp) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .semibold))
                        Text("I Want to Serve").font(.custom("OpenSans-Bold", size: 14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(accentColor))
                }
                .buttonStyle(ResourceCardPressStyle())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accentColor)
                    Text("Signed Up to Serve").font(.custom("OpenSans-SemiBold", size: 14)).foregroundStyle(accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(accentColor.opacity(0.1)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            role.isUrgent ? Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.25) : accentColor.opacity(0.12),
            lineWidth: 1
        ))
    }
}

// MARK: - Helper

private func shortDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f.string(from: date)
}
