import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Amen Covenant Story Viewer

struct AmenCovenantStoryViewer: View {
    let covenantId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var vm = AmenCovenantStoryViewerViewModel()

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.25)

            if vm.isLoading {
                ProgressView()
                    .tint(.white)
            } else if vm.stories.isEmpty {
                emptyState
            } else {
                storyContent
            }
        }
        .task { await vm.load(covenantId: covenantId) }
        .onReceive(timer) { _ in
            guard !vm.stories.isEmpty, !vm.isLoading else { return }
            let increment = 0.05 / 6.0
            vm.progress += increment
            if vm.progress >= 1.0 {
                vm.advance(dismiss: dismiss)
            }
        }
    }

    // MARK: - Story Content

    @ViewBuilder
    private var storyContent: some View {
        let story = vm.stories[vm.currentIndex]

        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 12)
                .padding(.top, 56)

            creatorRow(story: story)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            Spacer()

            storyBody(story: story)
                .padding(.horizontal, 28)

            Spacer()

            reactionBar(story: story)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
        }
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
        .overlay(alignment: .center) {
            tapZones
        }
        .id(vm.currentIndex)
        .transition(
            reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: vm.currentIndex)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(vm.stories.enumerated()), id: \.offset) { index, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: progressWidth(for: index, in: geo.size.width))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func progressWidth(for index: Int, in totalWidth: CGFloat) -> CGFloat {
        if index < vm.currentIndex { return totalWidth }
        if index == vm.currentIndex { return totalWidth * vm.progress }
        return 0
    }

    // MARK: - Creator Row

    private func creatorRow(story: AmenCovenantStoryViewerViewModel.StoryItem) -> some View {
        HStack(spacing: 10) {
            Text(story.authorInitial)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.25)))
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(story.authorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(story.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(story.authorDisplayName), \(story.timeAgo)")
    }

    // MARK: - Story Body

    private func storyBody(story: AmenCovenantStoryViewerViewModel.StoryItem) -> some View {
        VStack(spacing: 14) {
            Text(story.text)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let ref = story.scriptureRef {
                Text(ref)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.18))
                    )
            }
        }
    }

    // MARK: - Reaction Bar

    private func reactionBar(story: AmenCovenantStoryViewerViewModel.StoryItem) -> some View {
        HStack(spacing: 12) {
            StoryReactionButton(icon: "hands.sparkles.fill", label: "Pray") {
                Task { await vm.react(storyId: story.id, reaction: "pray") }
            }
            StoryReactionButton(icon: "checkmark.seal.fill", label: "Amen") {
                Task { await vm.react(storyId: story.id, reaction: "amen") }
            }
            StoryReactionButton(icon: "heart.fill", label: "Encourage") {
                Task { await vm.react(storyId: story.id, reaction: "encourage") }
            }
            Spacer()
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    if reduceTransparency {
                        Circle().fill(Color(.systemBackground).opacity(0.85))
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle().fill(Color.white.opacity(0.14))
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.32), lineWidth: 0.5)
                                    .blur(radius: 0.2)
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8)
                            }
                    }
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
        .padding(.top, 56)
        .padding(.trailing, 20)
        .accessibilityLabel("Dismiss stories")
    }

    // MARK: - Tap Zones

    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: geo.size.width * 0.4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                            vm.retreat()
                        }
                    }
                Color.clear
                    .frame(width: geo.size.width * 0.6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                            vm.advance(dismiss: dismiss)
                        }
                    }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.5))
            Text("No stories right now")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Stories expire after 24 hours.\nCheck back later.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .overlay(alignment: .topTrailing) {
            dismissButton
        }
    }
}

// MARK: - Story Reaction Button

private struct StoryReactionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.85))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.36), lineWidth: 0.5)
                                .blur(radius: 0.2)
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.84), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .accessibilityLabel(label)
    }
}

// MARK: - Story Viewer ViewModel

@MainActor
final class AmenCovenantStoryViewerViewModel: ObservableObject {

    struct StoryItem: Identifiable {
        let id: String
        let authorDisplayName: String
        let authorInitial: String
        let text: String
        let scriptureRef: String?
        let timeAgo: String
        let expiresAt: Date
    }

    @Published var stories: [StoryItem] = []
    @Published var currentIndex: Int = 0
    @Published var progress: Double = 0.0
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    func load(covenantId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Timestamp(date: Date())
            let snap = try await db
                .collection("covenants").document(covenantId)
                .collection("stories")
                .whereField("expiresAt", isGreaterThan: now)
                .order(by: "expiresAt")
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            stories = snap.documents.compactMap { doc -> StoryItem? in
                let data = doc.data()
                guard
                    let text = data["text"] as? String,
                    let expiresTimestamp = data["expiresAt"] as? Timestamp
                else { return nil }

                let displayName = data["authorDisplayName"] as? String ?? "Creator"
                let initial = String(displayName.prefix(1)).uppercased()
                let expiresAt = expiresTimestamp.dateValue()
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let scriptureRef = data["scriptureRef"] as? String

                return StoryItem(
                    id: doc.documentID,
                    authorDisplayName: displayName,
                    authorInitial: initial,
                    text: String(text.prefix(200)),
                    scriptureRef: scriptureRef,
                    timeAgo: Self.relativeTimeAgo(from: createdAt),
                    expiresAt: expiresAt
                )
            }
            currentIndex = 0
            progress = 0.0
        } catch {
            stories = []
        }
    }

    func advance(dismiss: DismissAction) {
        let next = currentIndex + 1
        if next >= stories.count {
            dismiss()
        } else {
            currentIndex = next
            progress = 0.0
        }
    }

    func retreat() {
        if currentIndex > 0 {
            currentIndex -= 1
            progress = 0.0
        } else {
            progress = 0.0
        }
    }

    func react(storyId: String, reaction: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let reactionRef = db
            .collection("storyReactions")
            .document("\(storyId)_\(uid)_\(reaction)")
        try? await reactionRef.setData([
            "storyId": storyId,
            "userId": uid,
            "reaction": reaction,
            "createdAt": Timestamp(date: Date())
        ], merge: true)
    }

    private static func relativeTimeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
