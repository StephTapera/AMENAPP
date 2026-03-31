import SwiftUI

// MARK: - ChurchSermonEntry

struct ChurchSermonEntry: Identifiable {
    let id: String
    let title: String
    let preacherName: String
    let preachedAt: Date
    let thumbnailURL: String?
    let videoURL: String?
    let scriptureReferences: [String]
    let summary: String?
    let topics: [String]
}

// MARK: - ChurchSermonArchiveModuleView

/// Horizontal scroll of recent sermon cards on a church profile.
/// Tapping a card opens the full sermon detail sheet.
struct ChurchSermonArchiveModuleView: View {
    let sermons: [ChurchSermonEntry]
    let onSermonTap: (ChurchSermonEntry) -> Void

    @State private var selectedSermon: ChurchSermonEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if sermons.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sermons) { sermon in
                            SermonCard(sermon: sermon)
                                .onTapGesture {
                                    selectedSermon = sermon
                                    onSermonTap(sermon)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
            }
        }
        .sheet(item: $selectedSermon) { sermon in
            SermonDetailSheet(sermon: sermon)
        }
    }

    private var sectionHeader: some View {
        HStack {
            Label("Sermons", systemImage: "play.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if sermons.count > 3 {
                Button("See All") { }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "play.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.black.opacity(0.25))
                Text("No sermons yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - SermonCard

private struct SermonCard: View {
    let sermon: ChurchSermonEntry

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.07))
                    .frame(width: 200, height: 112)

                if sermon.thumbnailURL != nil {
                    // AsyncImage would go here; placeholder for now
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.black.opacity(0.3))
                } else {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.black.opacity(0.25))
                }

                // Play badge
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            }
            .frame(width: 200, height: 112)

            VStack(alignment: .leading, spacing: 3) {
                Text(sermon.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(sermon.preacherName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(sermon.preachedAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.6))

                if !sermon.scriptureReferences.isEmpty {
                    Text(sermon.scriptureReferences.prefix(2).joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}

// MARK: - SermonDetailSheet

private struct SermonDetailSheet: View {
    let sermon: ChurchSermonEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Video placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16/9, contentMode: .fit)

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.black.opacity(0.3))
                    }
                    .padding(.horizontal, 16)

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sermon.title)
                            .font(.system(size: 20, weight: .bold))

                        HStack(spacing: 12) {
                            Text(sermon.preacherName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text(sermon.preachedAt, style: .date)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(white: 0.6))
                        }

                        if !sermon.scriptureReferences.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(sermon.scriptureReferences, id: \.self) { ref in
                                        Text(ref)
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.ultraThinMaterial)
                                            .background(Color.white.opacity(0.55))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color(white: 0.85).opacity(0.5), lineWidth: 0.5)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Summary
                    if let summary = sermon.summary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(summary)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 16)
                    }

                    // Reflection prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflect")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 8) {
                            ForEach([
                                "What stood out to you?",
                                "What scripture stayed with you?",
                                "How will you apply this this week?",
                                "What would you like prayer for after hearing this?"
                            ], id: \.self) { prompt in
                                HStack {
                                    Text(prompt)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .background(Color.white.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Ask Berean
                    Button {
                        // Navigate to Berean with sermon context
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Ask Berean about this sermon")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Sermon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
    }
}

// MARK: - Preview

struct ChurchSermonArchiveModuleView_Previews: PreviewProvider {
    static let sampleSermons = [
        ChurchSermonEntry(
            id: "1",
            title: "Walking in the Spirit",
            preacherName: "Pastor James",
            preachedAt: Date().addingTimeInterval(-7 * 86400),
            thumbnailURL: nil,
            videoURL: nil,
            scriptureReferences: ["Galatians 5:16", "Romans 8:4"],
            summary: "An exploration of what it means to walk daily in the Holy Spirit.",
            topics: ["Holy Spirit", "Daily Walk", "Faith"]
        ),
        ChurchSermonEntry(
            id: "2",
            title: "The Power of Grace",
            preacherName: "Pastor Lisa",
            preachedAt: Date().addingTimeInterval(-14 * 86400),
            thumbnailURL: nil,
            videoURL: nil,
            scriptureReferences: ["Ephesians 2:8-9"],
            summary: "Understanding God's unmerited favor in our daily lives.",
            topics: ["Grace", "Salvation"]
        ),
        ChurchSermonEntry(
            id: "3",
            title: "Faith Over Fear",
            preacherName: "Pastor James",
            preachedAt: Date().addingTimeInterval(-21 * 86400),
            thumbnailURL: nil,
            videoURL: nil,
            scriptureReferences: ["Isaiah 41:10", "Matthew 14:27"],
            summary: nil,
            topics: ["Faith", "Fear", "Trust"]
        )
    ]

    static var previews: some View {
        ScrollView {
            ChurchSermonArchiveModuleView(
                sermons: sampleSermons,
                onSermonTap: { _ in }
            )
            .padding(.vertical)
        }
        .background(Color(white: 0.97))
    }
}
