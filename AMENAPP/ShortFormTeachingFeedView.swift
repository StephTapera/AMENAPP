// ShortFormTeachingFeedView.swift
// AMENAPP
//
// Short-form teaching/sermon clip feed for church and business accounts.
// Vertical paging format — calmer and more reflective than social reels.

import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

enum ClipType: String, CaseIterable {
    case sermonClip     = "Sermon Clip"
    case teachingClip   = "Teaching"
    case ministryUpdate = "Ministry Update"
    case invitation     = "Invitation"
    case missionUpdate  = "Mission Update"
    case opportunity    = "Opportunity"
    case resource       = "Resource"

    var chipColor: Color {
        switch self {
        case .sermonClip:     return Color(red: 0.93, green: 0.70, blue: 0.20) // amber
        case .teachingClip:   return Color(red: 0.93, green: 0.70, blue: 0.20) // amber
        case .ministryUpdate: return Color(red: 0.30, green: 0.55, blue: 0.90) // blue
        case .invitation:     return Color(red: 0.45, green: 0.78, blue: 0.62) // green
        case .missionUpdate:  return Color(red: 0.30, green: 0.55, blue: 0.90) // blue
        case .opportunity:    return Color(red: 0.60, green: 0.45, blue: 0.90) // purple
        case .resource:       return Color(red: 0.45, green: 0.78, blue: 0.62) // green
        }
    }
}

struct TeachingClip: Identifiable {
    let id: String
    let churchOrBusinessId: String
    let authorName: String
    let title: String
    let type: ClipType
    let thumbnailURL: String?
    let videoURL: String?
    let scriptureRef: String?
    let duration: TimeInterval
    let smartSignals: [String]
}

// MARK: - ViewModel

@MainActor
class ShortFormTeachingViewModel: ObservableObject {
    @Published var clips: [TeachingClip] = []
    @Published var currentIndex: Int = 0

    private lazy var db = Firestore.firestore()

    func loadClips() async {
        // Fetch teaching clips ordered by creation date, limit 30.
        // Filters to clips authored by church/business accounts (clipType != nil implies
        // they were uploaded via the teaching clip flow rather than regular posts).
        do {
            let snap = try await db
                .collection("teachingClips")
                .whereField("isPublished", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            clips = snap.documents.compactMap { doc -> TeachingClip? in
                let d = doc.data()
                guard
                    let churchId  = d["churchOrBusinessId"] as? String,
                    let author    = d["authorName"] as? String,
                    let title     = d["title"] as? String,
                    let typeRaw   = d["clipType"] as? String,
                    let clipType  = ClipType(rawValue: typeRaw),
                    let duration  = d["duration"] as? TimeInterval
                else { return nil }
                return TeachingClip(
                    id: doc.documentID,
                    churchOrBusinessId: churchId,
                    authorName: author,
                    title: title,
                    type: clipType,
                    thumbnailURL: d["thumbnailURL"] as? String,
                    videoURL: d["videoURL"] as? String,
                    scriptureRef: d["scriptureRef"] as? String,
                    duration: duration,
                    smartSignals: d["smartSignals"] as? [String] ?? []
                )
            }
        } catch {
            // Leave clips empty — the view will show an empty state
        }
    }

    func recordEncouragement(clipId: String) async {
        // Non-vanity engagement signal — writes to engagementSignals subcollection.
        // No public count is surfaced; this feeds the recommendation engine only.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let signalId = "\(uid)_\(clipId)_encouraged"
        try? await db
            .collection("engagementSignals")
            .document(signalId)
            .setData([
                "userId": uid,
                "targetId": clipId,
                "targetType": "teachingClip",
                "signalType": "encouraged",
                "recordedAt": FieldValue.serverTimestamp()
            ], merge: false)
    }

    func saveToNotes(clipId: String) async {
        // Writes a clip reference entry to the user's personal notes collection.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let noteId = UUID().uuidString
        try? await db
            .collection("users").document(uid)
            .collection("notes")
            .document(noteId)
            .setData([
                "id": noteId,
                "type": "clipReference",
                "clipId": clipId,
                "savedAt": FieldValue.serverTimestamp()
            ])
    }
}

// MARK: - Main Feed View

struct ShortFormTeachingFeedView: View {
    @StateObject private var vm = ShortFormTeachingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $vm.currentIndex) {
                ForEach(Array(vm.clips.enumerated()), id: \.element.id) { index, clip in
                    TeachingClipCard(clip: clip, vm: vm)
                        .tag(index)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            ZStack {
                                Color.white.opacity(0.55)
                                Color(white: 0.88).opacity(0.5)
                            }
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.06), radius: 12)
                        )
                }

                Spacer()

                Text("Teachings")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                // Balance spacer
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
        .task {
            await vm.loadClips()
        }
    }
}

// MARK: - Clip Card

struct TeachingClipCard: View {
    let clip: TeachingClip
    @ObservedObject var vm: ShortFormTeachingViewModel
    @State private var isPlaying: Bool = false
    @State private var hasEncouraged: Bool = false
    @State private var fullscreenVideoURL: URL?
    @State private var showingVideoPlayer: Bool = false
    @State private var showingBereanAI: Bool = false
    @State private var showingShareSheet: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background
                clipBackground(size: geo.size)

                // Play button overlay
                if !isPlaying {
                    playButtonOverlay
                }

                // Bottom gradient + content
                bottomOverlay

                // Right action column
                rightActionColumn
                    .padding(.trailing, 16)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: Background

    @ViewBuilder
    private func clipBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.85)

            if let urlString = clip.thumbnailURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    case .failure:
                        placeholderBackground
                    case .empty:
                        placeholderBackground
                    @unknown default:
                        placeholderBackground
                    }
                }
            } else {
                placeholderBackground
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderBackground: some View {
        ZStack {
            Color.black.opacity(0.85)
            Image(systemName: "play.rectangle.fill")
                .font(.systemScaled(48))
                .foregroundColor(.white.opacity(0.2))
        }
    }

    // MARK: Play Button

    private var playButtonOverlay: some View {
        Button {
            withAnimation(.easeIn(duration: 0.2)) {
                isPlaying = true
            }
            if let urlString = clip.videoURL, let url = URL(string: urlString) {
                fullscreenVideoURL = url
                showingVideoPlayer = true
            }
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.systemScaled(60))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Bottom Gradient + Content

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            // Gradient fade from transparent to black
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.85), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: UIScreen.main.bounds.height * 0.55)

            Color.black.opacity(0.85)
                .frame(height: 10)
        }
        .overlay(alignment: .bottom) {
            bottomContentArea
                .padding(.horizontal, 16)
                .padding(.bottom, 48)
                .padding(.trailing, 72) // leave room for action column
        }
    }

    private var bottomContentArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author badge pill
            authorBadge

            // Clip type chip
            clipTypeChip

            // Title
            Text(clip.title)
                .font(.systemScaled(18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Scripture reference
            if let ref = clip.scriptureRef {
                Text(ref)
                    .font(.systemScaled(13))
                    .italic()
                    .foregroundColor(.white.opacity(0.85))
            }

            // Smart signal pills (non-vanity)
            if !clip.smartSignals.isEmpty {
                smartSignalPills
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorBadge: some View {
        Text(clip.authorName)
            .font(.systemScaled(12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    Color.white.opacity(0.55)
                    Color(white: 0.88).opacity(0.5)
                }
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.06), radius: 12)
            )
    }

    private var clipTypeChip: some View {
        Text(clip.type.rawValue)
            .font(.systemScaled(11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                clip.type.chipColor.opacity(0.75)
                    .clipShape(Capsule())
            )
    }

    private var smartSignalPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clip.smartSignals, id: \.self) { signal in
                    Text(signal)
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            ZStack {
                                Color.white.opacity(0.55)
                                Color(white: 0.88).opacity(0.5)
                            }
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.06), radius: 12)
                        )
                }
            }
        }
    }

    // MARK: Right Action Column

    private var rightActionColumn: some View {
        VStack(spacing: 20) {
            // Encourage (heart) — no count shown
            actionButton(
                icon: hasEncouraged ? "heart.fill" : "heart",
                label: "Encourage",
                tint: hasEncouraged ? Color(red: 0.93, green: 0.30, blue: 0.30) : .white
            ) {
                withAnimation(Motion.adaptive(.spring(response: 0.3))) {
                    hasEncouraged.toggle()
                }
                if hasEncouraged {
                    Task { await vm.recordEncouragement(clipId: clip.id) }
                }
            }

            // Save to Notes
            actionButton(icon: "bookmark.fill", label: "Save") {
                Task { await vm.saveToNotes(clipId: clip.id) }
            }

            // Ask Berean (AI)
            actionButton(icon: "sparkles", label: "Ask Berean") {
                showingBereanAI = true
            }

            // Share
            actionButton(icon: "square.and.arrow.up", label: "Share") {
                showingShareSheet = true
            }
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let url = fullscreenVideoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingBereanAI) {
            BereanAIAssistantView(
                seedMessage: "I'm watching a clip called \"\(clip.title)\" by \(clip.authorName)\(clip.scriptureRef.map { " on \($0)" } ?? ""). Help me go deeper with this teaching."
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            let shareText: String = {
                var text = "\(clip.title) — \(clip.authorName)"
                if let ref = clip.scriptureRef { text += "\n\(ref)" }
                if let urlString = clip.videoURL { text += "\n\(urlString)" }
                text += "\n\nWatched on AMEN"
                return text
            }()
            ShareSheet(items: [shareText])
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(24, weight: .medium))
                    .foregroundColor(tint)
                Text(label)
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
private let sampleClips: [TeachingClip] = [
    TeachingClip(
        id: "clip-001",
        churchOrBusinessId: "church-grace-fellowship",
        authorName: "Grace Fellowship Church",
        title: "Walking in the Spirit: Everyday Faith in Hard Seasons",
        type: .sermonClip,
        thumbnailURL: nil,
        videoURL: nil,
        scriptureRef: "Galatians 5:16–25",
        duration: 180,
        smartSignals: ["Many were encouraged", "Widely saved to notes"]
    ),
    TeachingClip(
        id: "clip-002",
        churchOrBusinessId: "church-cornerstone",
        authorName: "Cornerstone Ministries",
        title: "This Week's Mission Update — Guatemala Village Schools",
        type: .missionUpdate,
        thumbnailURL: nil,
        videoURL: nil,
        scriptureRef: nil,
        duration: 90,
        smartSignals: ["Resonated with many"]
    ),
    TeachingClip(
        id: "clip-003",
        churchOrBusinessId: "org-light-house",
        authorName: "The Light House",
        title: "Resource: Free Bible Reading Plan — The Psalms in 30 Days",
        type: .resource,
        thumbnailURL: nil,
        videoURL: nil,
        scriptureRef: "Psalm 1:1–3",
        duration: 45,
        smartSignals: ["Highly downloaded", "Saved by many believers"]
    )
]

struct ShortFormTeachingFeedView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TeachingClipCard(clip: sampleClips[0], vm: ShortFormTeachingViewModel())
                .previewDisplayName("Sermon Clip Card")
                .ignoresSafeArea()
                .preferredColorScheme(.dark)

            TeachingClipCard(clip: sampleClips[1], vm: ShortFormTeachingViewModel())
                .previewDisplayName("Mission Update Card")
                .ignoresSafeArea()
                .preferredColorScheme(.dark)

            TeachingClipCard(clip: sampleClips[2], vm: ShortFormTeachingViewModel())
                .previewDisplayName("Resource Card")
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}
#endif
