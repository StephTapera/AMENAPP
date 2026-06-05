import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct StreamChapter: Identifiable {
    let id: String
    let title: String
    let timestamp: TimeInterval
    let summary: String
    let detectedVerses: [String]

    var formattedTimestamp: String {
        let mins = Int(timestamp) / 60
        let secs = Int(timestamp) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct StreamHighlight: Identifiable {
    let id: String
    let text: String
    let timestamp: TimeInterval
    let chapter: String
    var isApproved: Bool = false
    var isPendingApproval: Bool = false
}

struct PostStreamRecap: Identifiable {
    let id: String
    let streamTitle: String
    let speakerName: String
    let date: Date
    let durationSeconds: TimeInterval
    let summary: String
    let keyPoints: [String]
    let detectedVerses: [String]
    let prayerPoints: [String]
    let actionItems: [String]
    let chapters: [StreamChapter]
    var highlights: [StreamHighlight]

    static let preview = PostStreamRecap(
        id: "preview-recap",
        streamTitle: "Walking by Faith, Not by Sight",
        speakerName: "Pastor James Williams",
        date: Date(),
        durationSeconds: 3720,
        summary: "An exploration of 2 Corinthians 5:7 and what it means to trust God when circumstances are unclear. The message emphasized that faith is not the absence of doubt, but choosing to act on God's word despite uncertainty.",
        keyPoints: [
            "Faith is a daily practice, not a one-time decision",
            "God's promises are more reliable than our circumstances",
            "Community provides accountability in seasons of doubt"
        ],
        detectedVerses: ["2 Corinthians 5:7", "Hebrews 11:1", "Romans 8:28", "Proverbs 3:5-6"],
        prayerPoints: [
            "For members facing financial uncertainty",
            "For those in difficult relationships",
            "For wisdom in upcoming community decisions"
        ],
        actionItems: [
            "Identify one area where you need to trust God more fully this week",
            "Share your faith story with one person",
            "Join a small group for accountability"
        ],
        chapters: [
            StreamChapter(id: "c1", title: "Introduction & Context", timestamp: 0, summary: "Opening worship and service context", detectedVerses: []),
            StreamChapter(id: "c2", title: "The Foundation of Faith", timestamp: 840, summary: "Unpacking Hebrews 11:1 and the nature of faith", detectedVerses: ["Hebrews 11:1"]),
            StreamChapter(id: "c3", title: "Faith in Action", timestamp: 1800, summary: "Practical application of walking by faith", detectedVerses: ["2 Corinthians 5:7", "Romans 8:28"]),
            StreamChapter(id: "c4", title: "Community & Accountability", timestamp: 2700, summary: "The role of the church in sustaining faith", detectedVerses: ["Proverbs 3:5-6"])
        ],
        highlights: [
            StreamHighlight(id: "h1", text: "Faith is choosing to act on God's word when everything in us wants to act on our feelings.", timestamp: 1920, chapter: "Faith in Action"),
            StreamHighlight(id: "h2", text: "The church is not a building — it's the people who hold you up when your faith is weak.", timestamp: 2850, chapter: "Community & Accountability")
        ]
    )
}

// MARK: - Section Enum

private enum RecapSection: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case chapters = "Chapters"
    case verses = "Scripture"
    case prayer = "Prayer Points"
    case action = "Action Items"
    case highlights = "Highlights"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "doc.text"
        case .chapters: return "list.number"
        case .verses: return "book"
        case .prayer: return "hands.sparkles"
        case .action: return "checkmark.circle"
        case .highlights: return "star"
        }
    }
}

// MARK: - Main View

struct PostStreamRecapView: View {
    let recap: PostStreamRecap
    var onDismiss: (() -> Void)? = nil

    @State private var selectedSection: RecapSection = .summary
    @State private var highlightPendingApproval: StreamHighlight? = nil
    @State private var showApprovalSheet = false
    @State private var localHighlights: [StreamHighlight]
    @State private var showShareSuccess = false
    @State private var successMessage = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    init(recap: PostStreamRecap, onDismiss: (() -> Void)? = nil) {
        self.recap = recap
        self.onDismiss = onDismiss
        self._localHighlights = State(initialValue: recap.highlights)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                recapHeader
                sectionPicker
                Divider()
                sectionContent
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let onDismiss {
                        Button("Done", action: onDismiss)
                            .foregroundStyle(Color.amenGold)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showShareSuccess {
                    successBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding()
                }
            }
            .sheet(isPresented: $showApprovalSheet) {
                if let highlight = highlightPendingApproval,
                   let card = makeContentCard(from: highlight) {
                    ApprovalSheetView(
                        card: card,
                        proposedAction: .discussInSpace,
                        requestorIsCreator: true,
                        requestorIsSpaceAdmin: false,
                        requestorIsChurchAdmin: false,
                        requestorIsTrustedMember: false,
                        targetSurface: .space,
                        onApproved: { _, _ in
                            handleHighlightApproval(highlight: highlight, approved: true)
                            showApprovalSheet = false
                            highlightPendingApproval = nil
                        },
                        onDenied: { _ in
                            handleHighlightApproval(highlight: highlight, approved: false)
                            showApprovalSheet = false
                            highlightPendingApproval = nil
                        },
                        onDismiss: {
                            showApprovalSheet = false
                            highlightPendingApproval = nil
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showShareSuccess)
        }
    }

    // MARK: - Header

    private var recapHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recap.streamTitle)
                .font(.title2)
                .fontWeight(.semibold)
            HStack {
                Label(recap.speakerName, systemImage: "person")
                Spacer()
                Label(formattedDuration, systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecapSection.allCases) { section in
                    sectionTab(section)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func sectionTab(_ section: RecapSection) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedSection = section
            }
        } label: {
            Label(section.rawValue, systemImage: section.icon)
                .font(.subheadline)
                .fontWeight(selectedSection == section ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selectedSection == section
                        ? Color.amenGold.opacity(0.15)
                        : Color(.secondarySystemFill)
                )
                .foregroundStyle(selectedSection == section ? Color.amenGold : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                switch selectedSection {
                case .summary:    summarySection
                case .chapters:   chaptersSection
                case .verses:     versesSection
                case .prayer:     prayerSection
                case .action:     actionSection
                case .highlights: highlightsSection
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecapSectionHeader(title: "Message Summary", icon: "doc.text.fill")
            Text(recap.summary)
                .font(.body)
                .foregroundStyle(.primary)
            if !recap.keyPoints.isEmpty {
                Divider()
                RecapSectionHeader(title: "Key Points", icon: "lightbulb.fill")
                ForEach(recap.keyPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.amenGold)
                            .padding(.top, 6)
                        Text(point)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Chapters Section

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecapSectionHeader(title: "Message Chapters", icon: "list.number")
            ForEach(recap.chapters) { chapter in
                ChapterRow(chapter: chapter)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Verses Section

    private var versesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecapSectionHeader(title: "Scripture Detected", icon: "book.fill")
            Text("These verses were detected during the stream. Tap any to open in Selah.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(recap.detectedVerses, id: \.self) { verse in
                HStack {
                    Image(systemName: "book.closed")
                        .foregroundStyle(Color.amenGold)
                        .frame(width: 28)
                    Text(verse)
                        .font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Prayer Section

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecapSectionHeader(title: "Prayer Points", icon: "hands.sparkles.fill")
            Text("These prayer needs were identified during the stream.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(recap.prayerPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.amenGold)
                        .padding(.top, 4)
                    Text(point)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecapSectionHeader(title: "This Week's Action Items", icon: "checkmark.circle.fill")
            Text("Apply this message to your daily walk.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(recap.actionItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.amenGold)
                        .clipShape(Circle())
                    Text(item)
                        .font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecapSectionHeader(title: "Stream Highlights", icon: "star.fill")
            Text("Highlights must be individually approved before sharing. Nothing posts automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.amenGold.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            ForEach($localHighlights) { $highlight in
                HighlightRow(
                    highlight: highlight,
                    onRequestShare: {
                        highlightPendingApproval = highlight
                        showApprovalSheet = true
                    }
                )
            }

            if localHighlights.isEmpty {
                Text("No highlights detected in this stream.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let mins = Int(recap.durationSeconds) / 60
        return "\(mins) min"
    }

    private var successBanner: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(successMessage)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }

    private func makeContentCard(from highlight: StreamHighlight) -> ContentCard? {
        ContentCard(
            id: highlight.id,
            title: "Stream Highlight: \(highlight.chapter)",
            body: highlight.text,
            sourceType: .livestreamMoment,
            sourceSurface: .livestream,
            sourceId: highlight.id,
            originalAudience: .churchOnly,
            creatorId: "current-user",
            creatorDisplayName: nil,
            sensitivityScore: 0.1,
            hasPrayerContent: false,
            hasChildContent: false,
            hasLocationData: false,
            hasMinors: false,
            isAnonymous: false,
            isPaidContent: false,
            isDM: false,
            isChurchInternal: true,
            createdAt: Date(),
            expiresAt: nil,
            moderationState: .safe,
            discussionStatus: .open,
            attributionRules: ContentAttributionRules(
                requiresAttribution: true,
                allowsAnonymous: false,
                allowsQuoteOnly: true,
                expiresAfterDays: nil
            )
        )
    }

    private func handleHighlightApproval(highlight: StreamHighlight, approved: Bool) {
        guard let idx = localHighlights.firstIndex(where: { $0.id == highlight.id }) else { return }
        localHighlights[idx].isApproved = approved
        localHighlights[idx].isPendingApproval = false
        if approved {
            successMessage = "Highlight approved and queued for posting."
            withAnimation { showShareSuccess = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { showShareSuccess = false }
            }
        }
    }
}

// MARK: - Sub-views

private struct RecapSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(Color.amenGold)
    }
}

private struct ChapterRow: View {
    let chapter: StreamChapter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(chapter.formattedTimestamp)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.subheadline.weight(.medium))
                Text(chapter.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !chapter.detectedVerses.isEmpty {
                    HStack {
                        ForEach(chapter.detectedVerses, id: \.self) { verse in
                            Text(verse)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.amenGold.opacity(0.15))
                                .foregroundStyle(Color.amenGold)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        Divider()
    }
}

private struct HighlightRow: View {
    let highlight: StreamHighlight
    let onRequestShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "quote.opening")
                    .foregroundStyle(Color.amenGold)
                Text(highlight.text)
                    .font(.body)
                    .italic()
            }
            HStack {
                Text(highlight.chapter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(formattedTimestamp)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if highlight.isApproved {
                    Label("Approved", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button(action: onRequestShare) {
                        Label("Share", systemImage: "arrow.up.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.amenGold)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var formattedTimestamp: String {
        let mins = Int(highlight.timestamp) / 60
        let secs = Int(highlight.timestamp) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    PostStreamRecapView(recap: .preview)
}
