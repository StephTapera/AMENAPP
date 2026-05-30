//
//  PrayerTestimonyFeatures.swift
//  AMENAPP
//
//  10 interconnected prayer/testimony features.
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseDatabase
import FirebaseAuth
import UserNotifications

// MARK: - Feature 1: Scripture Anchor

@MainActor
class ScriptureAnchorService: ObservableObject {
    static let shared = ScriptureAnchorService()
    @Published var suggestions: [ScriptureAnchorSuggestion] = []
    @Published var isAnalyzing = false

    struct ScriptureAnchorSuggestion: Identifiable {
        let id = UUID()
        let reference: String
        let text: String
        let theme: String
    }

    private let keywordMap: [String: [(reference: String, text: String, theme: String)]] = [
        "heal": [("James 5:15", "The prayer offered in faith will make the sick person well", "Healing")],
        "forgiv": [("Ephesians 4:32", "Be kind and compassionate to one another, forgiving each other", "Forgiveness")],
        "anxi": [("Philippians 4:6", "Do not be anxious about anything, but in every situation, by prayer and petition", "Anxiety")],
        "fear": [("Isaiah 41:10", "Do not fear, for I am with you; do not be dismayed, for I am your God", "Fear")],
        "strength": [("Philippians 4:13", "I can do all this through him who gives me strength", "Strength")],
        "peace": [("John 14:27", "Peace I leave with you; my peace I give you", "Peace")],
        "provis": [("Philippians 4:19", "My God will meet all your needs according to the riches of his glory", "Provision")],
        "hope": [("Romans 15:13", "May the God of hope fill you with all joy and peace as you trust in him", "Hope")],
        "loss": [("Psalm 34:18", "The Lord is close to the brokenhearted and saves those who are crushed in spirit", "Grief")],
        "grief": [("Psalm 34:18", "The Lord is close to the brokenhearted and saves those who are crushed in spirit", "Grief")],
        "family": [("Joshua 24:15", "As for me and my household, we will serve the Lord", "Family")],
        "marriage": [("Ecclesiastes 4:9", "Two are better than one, because they have a good return for their labor", "Marriage")],
        "job": [("Proverbs 16:3", "Commit to the Lord whatever you do, and he will establish your plans", "Work")],
        "faith": [("Hebrews 11:1", "Now faith is confidence in what we hope for and assurance about what we do not see", "Faith")],
        "wisdom": [("James 1:5", "If any of you lacks wisdom, you should ask God, who gives generously to all", "Wisdom")],
        "protect": [("Psalm 91:11", "For he will command his angels concerning you to guard you in all your ways", "Protection")],
        "depress": [("Psalm 43:5", "Why, my soul, are you downcast? Put your hope in God", "Depression")],
        "relat": [("1 Corinthians 13:4", "Love is patient, love is kind. It does not envy, it does not boast", "Relationships")]
    ]

    func analyze(_ text: String) {
        guard text.count > 10 else { suggestions = []; return }
        isAnalyzing = true
        let lower = text.lowercased()
        var found: [ScriptureAnchorSuggestion] = []
        for (keyword, verses) in keywordMap {
            if lower.contains(keyword), let verse = verses.first {
                found.append(ScriptureAnchorSuggestion(reference: verse.reference, text: verse.text, theme: verse.theme))
                if found.count >= 3 { break }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.suggestions = found
            self?.isAnalyzing = false
        }
    }
}

struct ScriptureAnchorCard: View {
    @ObservedObject var service = ScriptureAnchorService.shared
    var onSelect: (String, String) -> Void  // reference, text

    var body: some View {
        if !service.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scripture Anchor", systemImage: "sparkles")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.orange)

                ForEach(service.suggestions) { s in
                    Button { onSelect(s.reference, s.text) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.reference)
                                    .font(.systemScaled(13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(s.text)
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.06))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Feature 2: Prayer Echo

class PrayerEchoService {
    static let shared = PrayerEchoService()

    // ── RTDB reference for prayer echo state ─────────────────────────────────
    // Replaces in-document `intercessorUids` array which was unbounded and
    // caused hotspot writes + 1MB document limit risk on popular prayers.
    // New path: prayerActivity/{postId}/prayingUsers/{uid} = true|null
    private lazy var rtdb: DatabaseReference = Database.database().reference()

    func hasEchoed(post: Post) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        // Prefer the legacy in-document array if present (backwards compat for old posts),
        // but new writes always go to RTDB so this will naturally drain over time.
        return post.intercessorUids?.contains(uid) ?? false
    }

    /// Check echo state from RTDB (async, always current).
    func hasEchoedAsync(postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        guard let snapshot = try? await rtdb
            .child("prayerActivity").child(postId).child("prayingUsers").child(uid)
            .getData() else { return false }
        return snapshot.exists()
    }

    func toggleEcho(post: Post) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let postId = post.firestoreId
        guard !postId.isEmpty else { return }

        let alreadyEchoed = await hasEchoedAsync(postId: postId)
        let prayerRef = rtdb.child("prayerActivity").child(postId).child("prayingUsers").child(uid)

        // Update RTDB echo state — no unbounded array on the Firestore document.
        if alreadyEchoed {
            try? await prayerRef.removeValue()
        } else {
            try? await prayerRef.setValue(true)
        }

        // Keep the Firestore stoneCount counter (a simple Int field, not an array).
        lazy var db = Firestore.firestore()
        let ref = db.collection("posts").document(postId)
        let delta = alreadyEchoed ? Int64(-1) : Int64(1)
        try? await ref.updateData(["stoneCount": FieldValue.increment(delta)])

        // Notify author on new echo.
        if !alreadyEchoed && post.authorId != uid {
            let notifRef = db
                .collection("users")
                .document(post.authorId)
                .collection("notifications")
                .document()
            try? await notifRef.setData([
                "type": "prayerEcho",
                "userId": post.authorId,
                "toUserId": post.authorId,
                "fromUserId": uid,
                "postId": postId,
                "message": "Someone is echoing your prayer 🙏",
                "createdAt": FieldValue.serverTimestamp(),
                "read": false
            ])
        }
    }
}

struct EchoButton: View {
    let post: Post
    @State private var isEchoed: Bool
    @State private var echoCount: Int
    @State private var isAnimating = false

    init(post: Post) {
        self.post = post
        _isEchoed = State(initialValue: PrayerEchoService.shared.hasEchoed(post: post))
        _echoCount = State(initialValue: post.stoneCount ?? 0)
    }

    var body: some View {
        Button {
            isEchoed.toggle()
            echoCount += isEchoed ? 1 : -1
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.5))) { isAnimating = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isAnimating = false }
            Task { await PrayerEchoService.shared.toggleEcho(post: post) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isEchoed ? "hands.and.sparkles.fill" : "hands.and.sparkles")
                    .font(.systemScaled(15))
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .foregroundStyle(isEchoed ? .purple : .secondary)
                if echoCount > 0 {
                    Text("\(echoCount)")
                        .font(.systemScaled(13))
                        .foregroundStyle(isEchoed ? .purple : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature 3: Testimony Timeline

class TestimonyTimelineService {
    static let shared = TestimonyTimelineService()

    func markAnswered(prayerPostId: String, testimonyContent: String) async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        lazy var db = Firestore.firestore()
        // Update original prayer to answered status
        try? await db.collection("posts").document(prayerPostId).updateData([
            "topicTag": "Answered Prayer",
            "answeredAt": FieldValue.serverTimestamp()
        ])
    }

    func fetchOriginalPrayer(id: String) async -> Post? {
        guard let snap = try? await Firestore.firestore().collection("posts").document(id).getDocument(),
              snap.exists else { return nil }
        return try? snap.data(as: Post.self)
    }
}

struct TestimonyArcView: View {
    let testimony: Post
    @State private var originalPrayer: Post?
    @State private var isLoading = false

    var journeyDays: Int { testimony.journeyDays ?? 0 }

    var body: some View {
        if let linkedId = testimony.linkedPrayerRequestId {
            VStack(alignment: .leading, spacing: 10) {
                Label("Prayer → Testimony Journey", systemImage: "arrow.triangle.path.badge.chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.purple)

                HStack(spacing: 12) {
                    arcStep(icon: "hands.clap.fill", label: "Prayed", color: .blue,
                            date: originalPrayer?.createdAt)
                    Rectangle().frame(width: 24, height: 1).foregroundStyle(.purple.opacity(0.3))

                    if journeyDays > 0 {
                        VStack(spacing: 2) {
                            Text("\(journeyDays)")
                                .font(.systemScaled(16, weight: .bold))
                                .foregroundStyle(.purple)
                            Text("days")
                                .font(.systemScaled(10))
                                .foregroundStyle(.secondary)
                        }
                        Rectangle().frame(width: 24, height: 1).foregroundStyle(.purple.opacity(0.3))
                    }

                    arcStep(icon: "checkmark.seal.fill", label: "Answered", color: .green,
                            date: testimony.createdAt)
                }

                if let prayer = originalPrayer {
                    Text("\"\(prayer.content.prefix(80))…\"")
                        .font(.systemScaled(12, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.purple.opacity(0.06))
                        .cornerRadius(8)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5))
            .onAppear {
                guard originalPrayer == nil else { return }
                Task {
                    isLoading = true
                    originalPrayer = await TestimonyTimelineService.shared.fetchOriginalPrayer(id: linkedId)
                    isLoading = false
                }
            }
        }
    }

    private func arcStep(icon: String, label: String, color: Color, date: Date?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.systemScaled(18)).foregroundStyle(color)
            Text(label).font(.systemScaled(10)).foregroundStyle(.secondary)
            if let date {
                Text(date, style: .date).font(.systemScaled(9)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Feature 4: Church Pulse

@MainActor
class ChurchPulseService: ObservableObject {
    @Published var activePrayerCount = 0
    @Published var recentTestimonies: [Post] = []
    @Published var isLoading = false

    func load(churchId: String) {
        isLoading = true
        lazy var db = Firestore.firestore()

        // Active prayers for this church
        db.collection("posts")
            .whereField("taggedChurchId", isEqualTo: churchId)
            .whereField("category", isEqualTo: "prayer")
            .whereField("topicTag", isEqualTo: "Prayer Request")
            .getDocuments { [weak self] snap, _ in
                DispatchQueue.main.async {
                    self?.activePrayerCount = snap?.documents.count ?? 0
                }
            }

        // Recent testimonies for this church
        db.collection("posts")
            .whereField("taggedChurchId", isEqualTo: churchId)
            .whereField("category", isEqualTo: "testimonies")
            .order(by: "createdAt", descending: true)
            .limit(to: 3)
            .getDocuments { [weak self] snap, _ in
                DispatchQueue.main.async {
                    self?.recentTestimonies = snap?.documents.compactMap { try? $0.data(as: Post.self) } ?? []
                    self?.isLoading = false
                }
            }
    }
}

struct ChurchPulseSection: View {
    let churchId: String
    @StateObject private var service = ChurchPulseService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Church Pulse", systemImage: "waveform.path.ecg")
                .font(AMENFont.bold(16))

            if service.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                HStack(spacing: 12) {
                    pulseStat(value: "\(service.activePrayerCount)", label: "Active Prayers", icon: "hands.clap.fill", color: .blue)
                    pulseStat(value: "\(service.recentTestimonies.count)", label: "Recent Testimonies", icon: "checkmark.seal.fill", color: .green)
                }

                if !service.recentTestimonies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Testimonies")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)
                        ForEach(service.recentTestimonies) { post in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                                Text(post.content.prefix(60) + (post.content.count > 60 ? "…" : ""))
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .accessibilityLabel(post.content)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear { service.load(churchId: churchId) }
    }

    private func pulseStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(AMENFont.bold(22))
            Text(label).font(AMENFont.regular(11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Feature 5: Sermon Connect

@MainActor
class SermonConnectService: ObservableObject {
    static let shared = SermonConnectService()
    @Published var matchedNoteTitle: String?
    @Published var matchedNoteId: String?
    @Published var isDismissed = false

    private let spiritualKeywords = ["heal", "forgiv", "faith", "grace", "redempt", "resurrect",
                                      "prayer", "worship", "peace", "joy", "hope", "love", "salvation",
                                      "repent", "holy spirit", "discipl", "servant", "humble", "trust"]

    func findMatch(for text: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let lower = text.lowercased()
        let matchedKeywords = spiritualKeywords.filter { lower.contains($0) }
        guard !matchedKeywords.isEmpty else { return }

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("notes")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments { [weak self] snap, _ in
                for doc in snap?.documents ?? [] {
                    let title = doc["title"] as? String ?? ""
                    let content = doc["content"] as? String ?? ""
                    let combined = (title + " " + content).lowercased()
                    for keyword in matchedKeywords {
                        if combined.contains(keyword) {
                            DispatchQueue.main.async {
                                self?.matchedNoteTitle = title
                                self?.matchedNoteId = doc.documentID
                                self?.isDismissed = false
                            }
                            return
                        }
                    }
                }
            }
    }
}

struct SermonConnectBanner: View {
    @ObservedObject var service = SermonConnectService.shared
    var onTapNote: (String) -> Void  // called with noteId
    /// Padding applied only when the banner has content — prevents blank space when no match exists.
    var paddingLeading: CGFloat = 0
    var paddingTop: CGFloat = 0

    var body: some View {
        if let title = service.matchedNoteTitle, !service.isDismissed {
            HStack(spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your pastor spoke on this")
                        .font(.systemScaled(12, weight: .semibold))
                    Text(title).font(.systemScaled(11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { onTapNote(service.matchedNoteId ?? "") } label: {
                    Text("Read").font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                }
                Button { service.isDismissed = true } label: {
                    Image(systemName: "xmark").font(.systemScaled(10)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5))
            .padding(.horizontal, paddingLeading)
            .padding(.top, paddingTop)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Feature 6: Prayer Room

struct PrayerRoom: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var hostId: String
    var hostName: String
    var churchId: String?
    var linkedPrayerRequestIds: [String]
    var scheduledAt: Date
    var durationMinutes: Int
    var rsvpUserIds: [String]
    var isArchived: Bool
    var participantCount: Int
    var createdAt: Date
}

@MainActor
class PrayerRoomService: ObservableObject {
    static let shared = PrayerRoomService()
    @Published var upcomingRooms: [PrayerRoom] = []
    @Published var isLoading = false

    private var listener: ListenerRegistration?

    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        listener = Firestore.firestore().collection("prayerRooms")
            .whereField("scheduledAt", isGreaterThan: Timestamp(date: Date()))
            .whereField("isArchived", isEqualTo: false)
            .order(by: "scheduledAt")
            .limit(to: 10)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    dlog("PrayerRoomService: snapshot error — \(error.localizedDescription)")
                    self.isLoading = false
                    return
                }
                self.upcomingRooms = snap?.documents.compactMap { try? $0.data(as: PrayerRoom.self) } ?? []
                self.isLoading = false
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }

    func rsvp(roomId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("prayerRooms").document(roomId).updateData([
            "rsvpUserIds": FieldValue.arrayUnion([uid])
        ])
    }

    func create(title: String, scheduledAt: Date, durationMinutes: Int, churchId: String?, linkedPostIds: [String]) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let name = LegacyUserService.shared.currentUser?.displayName else { return }
        let room: [String: Any] = [
            "title": title,
            "hostId": uid,
            "hostName": name,
            "churchId": churchId as Any,
            "linkedPrayerRequestIds": linkedPostIds,
            "scheduledAt": Timestamp(date: scheduledAt),
            "durationMinutes": durationMinutes,
            "rsvpUserIds": [uid],
            "isArchived": false,
            "participantCount": 0,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try? await Firestore.firestore().collection("prayerRooms").addDocument(data: room)
    }
}

struct PrayerRoomCard: View {
    let room: PrayerRoom
    @State private var hasRSVPd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Prayer Room", systemImage: "person.3.fill")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text(room.scheduledAt, style: .relative)
                    .font(.systemScaled(11))
                    .foregroundStyle(.secondary)
            }

            Text(room.title)
                .font(.systemScaled(15, weight: .semibold))

            HStack {
                Label("\(room.rsvpUserIds.count) joining", systemImage: "person.badge.plus")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    hasRSVPd = true
                    Task { await PrayerRoomService.shared.rsvp(roomId: room.id ?? "") }
                } label: {
                    Text(hasRSVPd ? "Joined ✓" : "Join")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(hasRSVPd ? .secondary : Color.white)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(hasRSVPd ? Color.clear : Color.purple)
                        .overlay(Capsule().strokeBorder(Color.purple.opacity(hasRSVPd ? 0.4 : 0), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(hasRSVPd)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.5))
        .onAppear {
            hasRSVPd = room.rsvpUserIds.contains(Auth.auth().currentUser?.uid ?? "")
        }
    }
}

struct PrayerRoomsSection: View {
    @ObservedObject var service = PrayerRoomService.shared
    @State private var showCreateRoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Prayer Rooms", systemImage: "person.3.sequence.fill")
                    .font(.systemScaled(15, weight: .semibold))
                Spacer()
                Button { showCreateRoom = true } label: {
                    Image(systemName: "plus.circle").foregroundStyle(.purple)
                }
                .accessibilityLabel("Create prayer room")
            }
            .padding(.horizontal, 16)

            if service.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if service.upcomingRooms.isEmpty {
                Text("No prayer rooms yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
            } else {
                ForEach(service.upcomingRooms) { room in
                    PrayerRoomCard(room: room).padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
        .sheet(isPresented: $showCreateRoom) { CreatePrayerRoomView() }
    }
}

struct CreatePrayerRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var duration = 30
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Room Details") {
                    TextField("Prayer room title", text: $title)
                    DatePicker("Scheduled", selection: $scheduledDate, in: Date()...)
                    Picker("Duration", selection: $duration) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                }
            }
            .navigationTitle("New Prayer Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        isSaving = true
                        Task {
                            await PrayerRoomService.shared.create(title: title, scheduledAt: scheduledDate, durationMinutes: duration, churchId: nil, linkedPostIds: [])
                            await MainActor.run { dismiss() }
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Feature 7: Burden Match

@MainActor
class BurdenMatchService: ObservableObject {
    static let shared = BurdenMatchService()
    @Published var pendingMatchUserId: String?
    @Published var showMatchPrompt = false

    func checkForMatches() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lazy var db = Firestore.firestore()

        // Get current user's recent prayer topics
        db.collection("posts")
            .whereField("authorId", isEqualTo: uid)
            .whereField("category", isEqualTo: "prayer")
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .getDocuments { [weak self] snap, _ in
                let tags = snap?.documents.compactMap { $0["topicTag"] as? String } ?? []
                guard let primaryTag = tags.first else { return }

                // Find others with same tag
                db.collection("posts")
                    .whereField("topicTag", isEqualTo: primaryTag)
                    .whereField("category", isEqualTo: "prayer")
                    .whereField("authorId", isNotEqualTo: uid)
                    .limit(to: 1)
                    .getDocuments { snap, _ in
                        if let match = snap?.documents.first,
                           let matchUserId = match["authorId"] as? String {
                            // Check they haven't been matched before
                            db.collection("burdenMatches")
                                .whereField("users", arrayContains: uid)
                                .getDocuments { existing, _ in
                                    let alreadyMatched = existing?.documents.contains(where: { ($0["users"] as? [String] ?? []).contains(matchUserId) }) ?? false
                                    if !alreadyMatched {
                                        DispatchQueue.main.async {
                                            self?.pendingMatchUserId = matchUserId
                                            self?.showMatchPrompt = true
                                        }
                                    }
                                }
                        }
                    }
            }
    }

    func acceptMatch(with userId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lazy var db = Firestore.firestore()
        // Record match
        db.collection("burdenMatches").addDocument(data: [
            "users": [uid, userId],
            "createdAt": FieldValue.serverTimestamp(),
            "status": "accepted"
        ])
        showMatchPrompt = false
    }

    func declineMatch() {
        showMatchPrompt = false
        pendingMatchUserId = nil
    }
}

struct BurdenMatchPrompt: View {
    @ObservedObject var service = BurdenMatchService.shared
    @State private var isConnecting = false

    var body: some View {
        if service.showMatchPrompt {
            VStack(spacing: 12) {
                Image(systemName: "heart.circle.fill").font(.systemScaled(36)).foregroundStyle(.purple)
                Text("Someone nearby is walking through something similar.")
                    .font(.systemScaled(14, weight: .medium))
                    .multilineTextAlignment(.center)
                Text("Want to connect?")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Not now") { service.declineMatch() }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Not now")
                    Button {
                        guard let matchedUserId = service.pendingMatchUserId, !isConnecting else { return }
                        isConnecting = true
                        service.acceptMatch(with: matchedUserId)
                        Task {
                            do {
                                // Fetch matched user's display name for the conversation header
                                let userDoc = try? await Firestore.firestore()
                                    .collection("users").document(matchedUserId).getDocument()
                                let userName = (userDoc?.data()?["displayName"] as? String)
                                    ?? (userDoc?.data()?["username"] as? String)
                                    ?? "Prayer Partner"
                                // Get or create a DM thread and navigate to it
                                let conversationId = try await FirebaseMessagingService.shared
                                    .getOrCreateDirectConversation(withUserId: matchedUserId, userName: userName)
                                await MainActor.run {
                                    isConnecting = false
                                    MessagingCoordinator.shared.openConversation(conversationId)
                                    dlog("✅ BurdenMatch: opened DM \(conversationId) with \(userName)")
                                }
                            } catch {
                                await MainActor.run {
                                    isConnecting = false
                                    dlog("❌ BurdenMatch: failed to open DM — \(error)")
                                    ToastManager.shared.show(ToastNotification(
                                        message: "Unable to open message thread. Please try again.",
                                        style: .error
                                    ))
                                }
                            }
                        }
                    } label: {
                        if isConnecting {
                            ProgressView().scaleEffect(0.8).frame(width: 60)
                        } else {
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isConnecting)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
            .padding()
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Feature 8: Fasting Chain

struct FastingEntry: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var duration: Int  // days
    var startedAt: Date
    var completedAt: Date?
}

@MainActor
class FastingChainService: ObservableObject {
    @Published var totalFastingDays = 0
    @Published var fasterCount = 0
    @Published var userFast: FastingEntry?
    @Published var isLoading = false

    func load(postId: String) {
        isLoading = true
        Firestore.firestore().collection("posts").document(postId).collection("fasts")
            .getDocuments { [weak self] snap, _ in
                DispatchQueue.main.async {
                    let entries = snap?.documents.compactMap { try? $0.data(as: FastingEntry.self) } ?? []
                    self?.fasterCount = entries.count
                    self?.totalFastingDays = entries.reduce(0) { $0 + $1.duration }
                    self?.userFast = entries.first(where: { $0.userId == Auth.auth().currentUser?.uid })
                    self?.isLoading = false
                }
            }
    }

    func joinFast(postId: String, duration: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let entry: [String: Any] = [
            "userId": uid,
            "duration": duration,
            "startedAt": FieldValue.serverTimestamp()
        ]
        try? await Firestore.firestore()
            .collection("posts").document(postId)
            .collection("fasts").addDocument(data: entry)

        // Schedule end notification
        let content = UNMutableNotificationContent()
        content.title = "🔥 Fast Complete"
        content.body = "Your \(duration)-day fast for this prayer has ended. Well done."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(duration) * 86400, repeats: false)
        let request = UNNotificationRequest(identifier: "fast_\(postId)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

struct FastingChainView: View {
    let postId: String
    @StateObject private var service = FastingChainService()
    @State private var showJoinSheet = false
    @State private var selectedDuration = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(service.totalFastingDays > 0 ? .orange : .secondary)
                    Text(service.totalFastingDays > 0
                         ? "\(service.totalFastingDays) days fasted collectively"
                         : "Start a fast for this prayer")
                        .font(.systemScaled(12))
                        .foregroundStyle(service.totalFastingDays > 0 ? .primary : .secondary)
                }
                Spacer()
                if service.userFast == nil {
                    Button("Fast") {
                        showJoinSheet = true
                    }
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
                    .buttonStyle(.plain)
                } else {
                    Label("Fasting", systemImage: "checkmark.circle.fill")
                        .font(.systemScaled(11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear { service.load(postId: postId) }
        .confirmationDialog("How long will you fast?", isPresented: $showJoinSheet) {
            Button("1 Day") { Task { await service.joinFast(postId: postId, duration: 1) } }
            Button("3 Days") { Task { await service.joinFast(postId: postId, duration: 3) } }
            Button("7 Days") { Task { await service.joinFast(postId: postId, duration: 7) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Feature 9: Notes-to-Prayer Bridge

@MainActor
class PrayerPreSeedState: ObservableObject {
    static let shared = PrayerPreSeedState()
    @Published var verseReference: String?
    @Published var verseText: String?
    @Published var noteId: String?
    @Published var hasPendingPreSeed = false

    func seed(verseReference: String, verseText: String, noteId: String) {
        self.verseReference = verseReference
        self.verseText = verseText
        self.noteId = noteId
        self.hasPendingPreSeed = true
    }

    func consume() -> (reference: String, text: String, noteId: String)? {
        guard hasPendingPreSeed,
              let ref = verseReference, let text = verseText, let noteId = noteId else { return nil }
        hasPendingPreSeed = false
        return (ref, text, noteId)
    }
}

// MARK: - Prayer Groups View

/// Service that loads and persists prayer group membership via Firestore.
/// Collection schema: prayerGroups/{groupId}  — members subcollection: prayerGroups/{groupId}/members/{uid}
@MainActor
class PrayerGroupsService: ObservableObject {
    static let shared = PrayerGroupsService()

    @Published var groups: [PrayerGroup] = []
    @Published var joinedGroupIds: Set<String> = []
    @Published var isSaving = false
    /// P1-14: surfaced to the UI via .alert in PrayerGroupsView
    @Published var lastError: String? = nil

    private var listener: ListenerRegistration?

    init() {
        startListening()
    }

    func startListening() {
        guard listener == nil else { return }
        listener = Firestore.firestore().collection("prayerGroups")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    dlog("PrayerGroupsService: snapshot error — \(error.localizedDescription)")
                    return
                }
                let mapped: [PrayerGroup] = snap?.documents.compactMap { doc in
                    let data = doc.data()
                    let name = data["name"] as? String ?? ""
                    guard !name.isEmpty else { return nil }
                    let icon = data["icon"] as? String ?? "person.3.fill"
                    let memberCount = data["memberCount"] as? Int ?? 0
                    let activeNow = data["activeNow"] as? Int ?? 0
                    let description = data["description"] as? String ?? ""
                    let category = data["category"] as? String ?? "General"
                    // Firestore stores color as an optional hex string; fall back to amenPurple.
                    let colorHex = data["colorHex"] as? String ?? ""
                    let color: Color
                    if colorHex.isEmpty {
                        color = Color(red: 0.55, green: 0.45, blue: 1.0) // amenPurple fallback
                    } else {
                        color = Color(hex: colorHex)
                    }
                    // Use the Firestore document ID as a stable string key; synthesise a UUID for Identifiable.
                    let docId = doc.documentID
                    let uuid = UUID(uuidString: docId) ?? UUID()
                    return PrayerGroup(
                        id: uuid,
                        name: name,
                        icon: icon,
                        memberCount: memberCount,
                        activeNow: activeNow,
                        description: description,
                        color: color,
                        category: category
                    )
                } ?? []
                DispatchQueue.main.async {
                    self.groups = mapped
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func loadJoinedGroups() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        Task {
            // Query all prayerGroups where the current user is a member.
            let snap = try? await db.collectionGroup("members").whereField("uid", isEqualTo: uid).getDocuments()
            let joined = Set((snap?.documents ?? []).compactMap { $0.reference.parent.parent?.documentID })
            self.joinedGroupIds = joined
            dlog("PrayerGroupsService: loaded \(joined.count) joined groups")
        }
    }

    func join(groupId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Duplicate-tap guard: bail if already joined.
        guard !joinedGroupIds.contains(groupId) else { return }

        // Optimistic local update.
        joinedGroupIds.insert(groupId)
        if let idx = groups.firstIndex(where: { $0.id.uuidString == groupId || $0.id.uuidString.lowercased() == groupId }) {
            let g = groups[idx]
            groups[idx] = PrayerGroup(
                id: g.id, name: g.name, icon: g.icon,
                memberCount: g.memberCount + 1, activeNow: g.activeNow,
                description: g.description, color: g.color, category: g.category
            )
        }

        isSaving = true
        defer { isSaving = false }
        let db = Firestore.firestore()
        let groupRef = db.collection("prayerGroups").document(groupId)
        let memberRef = groupRef.collection("members").document(uid)
        do {
            try await memberRef.setData(["uid": uid, "joinedAt": FieldValue.serverTimestamp()], merge: true)
            try await groupRef.updateData([
                "memberCount": FieldValue.increment(Int64(1))
            ])
            dlog("PrayerGroupsService: joined group \(groupId)")
        } catch {
            // Rollback optimistic update on failure.
            joinedGroupIds.remove(groupId)
            if let idx = groups.firstIndex(where: { $0.id.uuidString == groupId || $0.id.uuidString.lowercased() == groupId }) {
                let g = groups[idx]
                groups[idx] = PrayerGroup(
                    id: g.id, name: g.name, icon: g.icon,
                    memberCount: max(0, g.memberCount - 1), activeNow: g.activeNow,
                    description: g.description, color: g.color, category: g.category
                )
            }
            dlog("PrayerGroupsService: join error — \(error.localizedDescription)")
            lastError = error.localizedDescription // P1-14: surface to UI
        }
    }

    func leave(groupId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        let db = Firestore.firestore()
        let groupRef = db.collection("prayerGroups").document(groupId)
        do {
            try await groupRef.collection("members").document(uid).delete()
            try await groupRef.setData(["memberCount": FieldValue.increment(Int64(-1))], merge: true)
            joinedGroupIds.remove(groupId)
            dlog("PrayerGroupsService: left group \(groupId)")
        } catch {
            dlog("PrayerGroupsService: leave error — \(error.localizedDescription)")
            lastError = error.localizedDescription // P1-14: surface to UI
        }
    }

    func createGroup(name: String, description: String, category: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        let db = Firestore.firestore()
        let data: [String: Any] = [
            "name": name,
            "description": description,
            "category": category,
            "hostId": uid,
            "memberCount": 1,
            "activeNow": 0,
            "icon": "person.3.fill",
            "createdAt": FieldValue.serverTimestamp()
        ]
        do {
            let ref = try await db.collection("prayerGroups").addDocument(data: data)
            // Auto-join on creation
            try await ref.collection("members").document(uid)
                .setData(["uid": uid, "joinedAt": FieldValue.serverTimestamp()], merge: true)
            dlog("PrayerGroupsService: created group \(ref.documentID)")
        } catch {
            dlog("PrayerGroupsService: create error — \(error.localizedDescription)")
            lastError = error.localizedDescription // P1-14: surface to UI
        }
    }
}

// MARK: - PrayerGroupsView

struct PrayerGroupsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = PrayerGroupsService.shared
    @State private var showCreateGroup = false
    @State private var selectedGroup: PrayerGroup?

    private let columns = [GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if service.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("Prayer Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Create Prayer Group")
                }
            }
            .sheet(item: $selectedGroup) { group in
                PrayerGroupDetailView(group: group)
            }
            .sheet(isPresented: $showCreateGroup) {
                CreatePrayerGroupView()
            }
            .onAppear { service.loadJoinedGroups() }
            // P1-14: surface join/leave/create errors to the user
            .alert("Something went wrong", isPresented: .constant(service.lastError != nil), actions: {
                Button("OK") { service.lastError = nil }
            }, message: {
                Text(service.lastError ?? "")
            })
        }
    }

    // MARK: - Group List

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(service.groups) { group in
                    PrayerGroupListCard(
                        group: group,
                        isJoined: service.joinedGroupIds.contains(group.id.uuidString.lowercased()),
                        isSaving: service.isSaving
                    ) {
                        selectedGroup = group
                    } onJoinLeave: {
                        let gid = group.id.uuidString.lowercased()
                        Task {
                            if service.joinedGroupIds.contains(gid) {
                                await service.leave(groupId: gid)
                            } else {
                                await service.join(groupId: gid)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Prayer Groups Yet")
                .font(AMENFont.bold(20))
            Text("Start or join a prayer group to pray together consistently")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            AmenLiquidGlassPillButton(
                title: "Create a Group",
                systemImage: "plus.circle.fill",
                isLoading: false,
                isDisabled: false,
                hint: "Create a new prayer group"
            ) {
                showCreateGroup = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Prayer Group List Card

struct PrayerGroupListCard: View {
    let group: PrayerGroup
    let isJoined: Bool
    let isSaving: Bool
    let onTap: () -> Void
    let onJoinLeave: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon avatar
                ZStack {
                    Circle()
                        .fill(group.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: group.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(group.color)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(AMENFont.bold(15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(group.category)
                            .font(AMENFont.semiBold(10))
                            .foregroundStyle(group.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(group.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(group.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Label("\(group.memberCount)", systemImage: "person.2.fill")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                        if group.activeNow > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("\(group.activeNow) praying")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Spacer()

                // Join / Leave button
                Button {
                    onJoinLeave()
                } label: {
                    Text(isJoined ? "Joined" : "Join")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(isJoined ? Color.secondary : Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isJoined ? Color.clear : Color.black)
                        .overlay(Capsule().strokeBorder(isJoined ? Color.secondary.opacity(0.4) : Color.clear, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.name), \(group.memberCount) members")
        .accessibilityHint("Tap to view group details")
    }
}

// MARK: - Create Prayer Group View

struct CreatePrayerGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = PrayerGroupsService.shared

    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory = "General"
    @State private var isSaving = false
    @State private var showSuccess = false

    private let categories = [
        "General", "Daily Rhythm", "Fasting", "Intercession",
        "Family", "Healing", "Youth", "Missions", "Finance", "Marriage"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $name)
                        .font(AMENFont.regular(16))
                    TextField("What will this group pray about?", text: $description, axis: .vertical)
                        .font(AMENFont.regular(15))
                        .lineLimit(3...6)
                } header: {
                    Text("Group Details")
                }

                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                } header: {
                    Text("Category")
                }

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("You'll be the first member and group host.")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Prayer Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isSaving = true
                        Task {
                            await service.createGroup(
                                name: name.trimmingCharacters(in: .whitespaces),
                                description: description.trimmingCharacters(in: .whitespaces),
                                category: selectedCategory
                            )
                            await MainActor.run {
                                isSaving = false
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Create")
                                .font(AMENFont.bold(16))
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}

// MARK: - Feature 10: Living Wall Ranker

class LivingWallRanker {
    static let shared = LivingWallRanker()

    /// Score a post for spiritual momentum (higher = surfaces sooner)
    func score(_ post: Post) -> Double {
        var score: Double = 0
        let now = Date()
        let ageHours = now.timeIntervalSince(post.createdAt) / 3600

        // 1. Prayer Echo momentum (echoes gained in last 24h)
        let echoCount = Double(post.stoneCount ?? 0)
        if ageHours < 24 { score += echoCount * 15 }
        else { score += echoCount * 5 }

        // 2. Answered testimony (highest boost)
        if post.topicTag == "Answered Prayer" {
            let answeredRecently = ageHours < 24
            score += answeredRecently ? 80 : 40
        }

        // 3. Fasting chain activity — boosted if stoneCount is high (proxy for fasting engagement)
        if post.category == .prayer && echoCount > 3 {
            score += 20
        }

        // 4. Standard engagement
        score += Double(post.amenCount) * 2
        score += Double(post.commentCount) * 3
        score += Double(post.lightbulbCount) * 1.5

        // 5. Recency decay
        score *= max(0.1, 1.0 - (ageHours / 168))  // decay over 7 days

        return score
    }

    func rank(_ posts: [Post]) -> [Post] {
        posts.sorted { score($0) > score($1) }
    }
}
