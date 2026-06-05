// AmenCommunityAIManagerView.swift
// AMEN ConnectSpaces — "While You Were Away" Host Dashboard
// Built 2026-06-03
//
// Host-only view. Accessible from Space settings for the space creator.
// Calls CF `getCommunityAIDigest` and `getMemberInsights` via
// AmenRelationshipIntelligenceService.
//
// Glass chrome only on section headers and stat cards.
// Prayer / care content stays on matte surfaces.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class AmenCommunityAIManagerViewModel: ObservableObject {
    @Published var digest: CommunityDigest?
    @Published var memberInsights: [MemberInsight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let spaceId: String
    private let service = AmenRelationshipIntelligenceService.shared

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func loadDigest() async {
        isLoading = true
        errorMessage = nil
        do {
            async let digestTask   = service.fetchDigest(spaceId: spaceId)
            async let insightsTask = service.fetchMemberInsights(spaceId: spaceId)
            let (d, i) = try await (digestTask, insightsTask)
            digest = d
            memberInsights = i
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func followUp(insight: MemberInsight) async {
        try? await service.markMemberFollowedUp(spaceId: spaceId, userId: insight.userId)
        memberInsights.removeAll { $0.id == insight.id }
    }

    func dismiss(insight: MemberInsight) async {
        try? await service.dismissInsight(spaceId: spaceId, insightId: insight.id)
        memberInsights.removeAll { $0.id == insight.id }
    }
}

// MARK: - Skeleton placeholder bar

private struct SkeletonBar: View {
    var width: CGFloat = .infinity
    var height: CGFloat = 16
    @State private var opacity: Double = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(maxWidth: width == .infinity ? nil : width)
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.07
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SkeletonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBar(width: 180, height: 18)
            SkeletonBar(height: 14)
            SkeletonBar(height: 14)
            SkeletonBar(width: 220, height: 14)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Gold chip pill

private struct DigestTopicPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "D9A441"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(hex: "D9A441").opacity(0.14))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 0.5)
                    }
            }
            .accessibilityLabel(label)
    }
}

// MARK: - Stat row inside digest card

private struct DigestStatRow: View {
    let icon: String
    let count: Int
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }
}

// MARK: - Member insight row

private struct MemberInsightRow: View {
    let insight: MemberInsight
    let onAction: () -> Void
    let onDismiss: () -> Void

    @State private var showShareSheet = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle with initials
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "6E4BB5").opacity(0.3), lineWidth: 1)
                    }
                Text(initials(for: insight.displayName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(insight.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Action chip
            Button(action: onAction) {
                HStack(spacing: 4) {
                    Image(systemName: insight.recommendedAction.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(insight.recommendedAction.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "D9A441"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(hex: "D9A441").opacity(0.14))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color(hex: "D9A441").opacity(0.4), lineWidth: 0.5)
                        }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(insight.recommendedAction.label) \(insight.displayName)")

            // Dismiss
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss insight for \(insight.displayName)")
        }
        .padding(.vertical, 8)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last  = parts.count > 1 ? (parts.last?.prefix(1) ?? "") : ""
        return (first + last).uppercased()
    }
}

// MARK: - Glass section container

private struct GlassSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Glass section header pill
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                    }
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)

            content()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Unanswered question row

private struct QuestionRow: View {
    let question: DigestQuestion
    let onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(question.authorFirstName) · \(daysAgoLabel(question.askedDaysAgo))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.50))
                Spacer()
                Button(action: onReply) {
                    Text("Reply")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(hex: "D9A441").opacity(0.14))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reply to \(question.authorFirstName)'s question")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(question.authorFirstName) asked \(daysAgoLabel(question.askedDaysAgo)): \(question.text)")
    }

    private func daysAgoLabel(_ days: Int) -> String {
        days == 0 ? "today" : days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

// MARK: - Prayer request row

private struct PrayerRequestRow: View {
    let request: DigestPrayerRequest
    let onPray: () -> Void
    let onRespond: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(request.authorFirstName) · \(daysAgoLabel(request.postedDaysAgo))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.50))
                Spacer()
                HStack(spacing: 8) {
                    Button(action: onPray) {
                        Label("Pray", systemImage: "hands.sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "6E4BB5"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color(hex: "6E4BB5").opacity(0.14))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pray for \(request.authorFirstName)")

                    Button(action: onRespond) {
                        Text("Respond")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color(hex: "D9A441").opacity(0.14))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Respond to \(request.authorFirstName)'s prayer request")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(request.authorFirstName) posted \(daysAgoLabel(request.postedDaysAgo)): \(request.text)")
    }

    private func daysAgoLabel(_ days: Int) -> String {
        days == 0 ? "today" : days == 1 ? "1 day ago" : "\(days) days ago"
    }
}

// MARK: - Main View

struct AmenCommunityAIManagerView: View {
    let spaceId: String
    let spaceName: String

    @StateObject private var vm: AmenCommunityAIManagerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var selectedQuestion: DigestQuestion?
    @State private var showingDMSheet = false
    @State private var dmPrefilledText = ""

    init(spaceId: String, spaceName: String) {
        self.spaceId = spaceId
        self.spaceName = spaceName
        _vm = StateObject(wrappedValue: AmenCommunityAIManagerViewModel(spaceId: spaceId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                if vm.isLoading {
                    skeletonBody
                } else if let error = vm.errorMessage {
                    errorBody(error)
                } else {
                    mainScrollBody
                }
            }
            .navigationTitle("While You Were Away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.loadDigest() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                    }
                    .accessibilityLabel("Refresh digest")
                }
            }
            .task { await vm.loadDigest() }
            .sheet(item: $selectedQuestion) { question in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reply to Question")
                            .font(.title2.bold())
                            .padding(.horizontal)
                        Text(question.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.top)
                    .navigationTitle("Discussion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedQuestion = nil }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDMSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Send a Message")
                            .font(.title2.bold())
                            .padding(.horizontal)
                        Text(dmPrefilledText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.top)
                    .navigationTitle("Message")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingDMSheet = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skeleton loading

    private var skeletonBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonSection()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .accessibilityLabel("Loading digest")
    }

    // MARK: - Error state

    private func errorBody(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
            Text("Couldn't load digest")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await vm.loadDigest() }
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(hex: "D9A441"), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading digest: \(message)")
    }

    // MARK: - Main scroll content

    private var mainScrollBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if let digest = vm.digest {
                    digestCard(digest)
                }

                if !vm.memberInsights.isEmpty {
                    membersNeedingAttentionSection
                }

                if let digest = vm.digest, !digest.unansweredQuestions.isEmpty {
                    unansweredQuestionsSection(digest.unansweredQuestions)
                }

                if let digest = vm.digest, !digest.prayerRequestsNeedingAttention.isEmpty {
                    prayerRequestsSection(digest.prayerRequestsNeedingAttention)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Section 1: Digest card (glass, gold border)

    private func digestCard(_ digest: CommunityDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Since Your Last Visit")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Divider().opacity(0.12)

            DigestStatRow(
                icon: "bubble.left.and.bubble.right",
                count: digest.totalNewMessages,
                label: "New messages",
                tint: Color.white.opacity(0.65)
            )

            DigestStatRow(
                icon: "questionmark.bubble",
                count: digest.unansweredQuestions.count,
                label: "Unanswered questions",
                tint: Color(hex: "D9A441")
            )

            DigestStatRow(
                icon: "hands.sparkles",
                count: digest.prayerRequestsNeedingAttention.count,
                label: "Prayer requests needing attention",
                tint: Color(hex: "6E4BB5")
            )

            // Active topics — max 4 chips + overflow label
            if !digest.activeTopics.isEmpty {
                Divider().opacity(0.12)

                Text("Active Topics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .textCase(.uppercase)
                    .kerning(0.8)

                let visible = Array(digest.activeTopics.prefix(4))
                let overflow = max(0, digest.activeTopics.count - 4)
                FlowRow(spacing: 8) {
                    ForEach(visible, id: \.self) { topic in
                        DigestTopicPill(label: topic)
                    }
                    if overflow > 0 {
                        DigestTopicPill(label: "+\(overflow) more")
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.45), lineWidth: 1)
                }
        }
    }

    // MARK: - Section 2: Members needing attention

    private var membersNeedingAttentionSection: some View {
        GlassSectionCard(
            title: "Members Needing Attention",
            icon: "person.crop.circle.badge.exclamationmark",
            accent: Color(hex: "6E4BB5")
        ) {
            VStack(spacing: 0) {
                ForEach(Array(vm.memberInsights.enumerated()), id: \.element.id) { index, insight in
                    MemberInsightRow(
                        insight: insight,
                        onAction: {
                            Task {
                                await vm.followUp(insight: insight)
                            }
                        },
                        onDismiss: {
                            Task {
                                await vm.dismiss(insight: insight)
                            }
                        }
                    )
                    if index < vm.memberInsights.count - 1 {
                        Divider().opacity(0.10)
                    }
                }
            }
        }
    }

    // MARK: - Section 3: Unanswered questions

    private func unansweredQuestionsSection(_ questions: [DigestQuestion]) -> some View {
        GlassSectionCard(
            title: "Unanswered Questions",
            icon: "questionmark.bubble",
            accent: Color(hex: "D9A441")
        ) {
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    QuestionRow(
                        question: question,
                        onReply: {
                            // TODO: Navigate to DiscussionThreadView or DM composer for this question
                        }
                    )
                    if index < questions.count - 1 {
                        Divider().opacity(0.10)
                    }
                }
            }
        }
    }

    // MARK: - Section 4: Prayer requests

    private func prayerRequestsSection(_ requests: [DigestPrayerRequest]) -> some View {
        // Matte card — prayer/care content never behind glass (AMEN hard rule)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hands.sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                Text("PRAYER REQUESTS")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(Color(hex: "6E4BB5"))
            }
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Prayer Requests")

            VStack(spacing: 0) {
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                    PrayerRequestRow(
                        request: request,
                        onPray: {
                            // TODO: Record prayer action via CF or Firestore prayer log
                        },
                        onRespond: {
                            // TODO: Navigate to DM composer pre-filled with request context
                        }
                    )
                    if index < requests.count - 1 {
                        Divider().opacity(0.10)
                    }
                }
            }
            .padding(14)
            .background {
                // Matte — not glass
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "1A1620"))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(hex: "6E4BB5").opacity(0.25), lineWidth: 0.5)
                    }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "100E14"))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - FlowRow (simple wrapping layout for topic chips)

private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenCommunityAIManagerView(spaceId: "preview-space", spaceName: "Sunday Worship Team")
        .preferredColorScheme(.dark)
}
#endif
