// AttachmentCardsB.swift
// AMEN — Smart Attachment Cards Set B
// AdaptiveCardContainer, MusicCard, PodcastCard, YouTubeCard, LocationCard, FileCard, ChecklistCard
import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseAuth

// MARK: - Internal gold color (matches Set A private constant)

private let _acbAmenGold = Color(red: 198 / 255, green: 151 / 255, blue: 63 / 255)

// MARK: - AdaptiveCardContainer (shared glass container for B + C sets)

struct AdaptiveCardContainer<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(.secondarySystemBackground))
                    : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Remove attachment")
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
    }
}

// MARK: - AC_MusicCard

struct AC_MusicCard: View {
    let payload: MusicPayload
    let onRemove: () -> Void

    @State private var isPlaying = false

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                // Artwork
                Group {
                    if let urlString = payload.artworkURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                fallbackArtwork
                            case .empty:
                                fallbackArtwork
                                    .overlay(ProgressView().tint(.secondary))
                            @unknown default:
                                fallbackArtwork
                            }
                        }
                    } else {
                        fallbackArtwork
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(payload.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(payload.source.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // BTN-002 LANE-8: music preview gated — AVPlayer session wiring requires MediaPlaybackService
                // Flag-gated OFF until MusicContentLayer AVPlayer coordinator is wired into cards.
                Button {
                    // Optimistic toggle only — real playback requires AVPlayer session from MusicContentLayer
                    guard AMENFeatureFlags.shared.musicAttachmentEnabled else { return }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(_acbAmenGold)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause \(payload.title)" : "Play preview of \(payload.title) by \(payload.artist)")
                .padding(.trailing, 44) // leave room for remove button
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Music: \(payload.title) by \(payload.artist)")
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AC_PodcastCard

struct AC_PodcastCard: View {
    let payload: PodcastPayload
    let onRemove: () -> Void

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                // Artwork
                Group {
                    if let urlString = payload.artworkURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                fallbackArtwork
                            case .empty:
                                fallbackArtwork
                                    .overlay(ProgressView().tint(.secondary))
                            @unknown default:
                                fallbackArtwork
                            }
                        }
                    } else {
                        fallbackArtwork
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(payload.episodeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // BTN-002 LANE-8: wired — opens feedURL in Podcasts app or default handler
                Button {
                    if let url = URL(string: payload.feedURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Listen", systemImage: "headphones")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(_acbAmenGold, in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Listen to \(payload.episodeTitle) from \(payload.title)")
                .padding(.trailing, 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Podcast: \(payload.title), episode \(payload.episodeTitle)")
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AC_YouTubeCard

struct AC_YouTubeCard: View {
    let payload: YouTubePayload
    let onRemove: () -> Void

    private var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(payload.videoId)")
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 0) {
                // 16:9 Thumbnail
                GeometryReader { geo in
                    AsyncImage(url: URL(string: payload.thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure, .empty:
                            ZStack {
                                Color(.tertiarySystemFill)
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        @unknown default:
                            Color(.tertiarySystemFill)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

                // Info row
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.red)
                                .accessibilityHidden(true)
                            Text(payload.duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 6) {
                        Button {
                            if let url = watchURL {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Watch", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red, in: Capsule())
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Watch \(payload.title) on YouTube")

                        // BTN-002 LANE-8: Summarize gated — bereanHelperLinkSummaryEnabled controls CF readiness
                        if AMENFeatureFlags.shared.bereanHelperLinkSummaryEnabled {
                            Button {
                                // Wire: invoke Berean helper CF with YouTube videoId context
                                NotificationCenter.default.post(
                                    name: Notification.Name("berean.summarizeYouTube"),
                                    object: nil,
                                    userInfo: ["videoId": payload.videoId, "title": payload.title]
                                )
                            } label: {
                                Text("Summarize")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(_acbAmenGold)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Summarize \(payload.title)")
                            .accessibilityHint("Uses Berean AI to summarize this video")
                        }
                    }
                    .padding(.trailing, 44)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("YouTube video: \(payload.title), duration \(payload.duration)")
    }
}

// MARK: - AC_LocationCard

struct AC_LocationCard: View {
    let payload: LocationPayload
    let onRemove: () -> Void

    @State private var region: MKCoordinateRegion

    init(payload: LocationPayload, onRemove: @escaping () -> Void) {
        self.payload = payload
        self.onRemove = onRemove
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: payload.latitude,
                longitude: payload.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 0) {
                // Map view
                Map(coordinateRegion: $region, annotationItems: [payload]) { item in
                    MapPin(
                        coordinate: CLLocationCoordinate2D(
                            latitude: item.latitude,
                            longitude: item.longitude
                        ),
                        tint: _acbAmenGold
                    )
                }
                .frame(height: 140)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                )
                .accessibilityLabel("Map showing \(payload.name)")
                .accessibilityHint("Interactive map")
                .disabled(false)

                // Info row
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let address = payload.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        let placemark = MKPlacemark(
                            coordinate: CLLocationCoordinate2D(
                                latitude: payload.latitude,
                                longitude: payload.longitude
                            )
                        )
                        let mapItem = MKMapItem(placemark: placemark)
                        mapItem.name = payload.name
                        mapItem.openInMaps(launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                        ])
                    } label: {
                        Label("Open in Maps", systemImage: "map.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(payload.name) in Maps")
                    .padding(.trailing, 44)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location: \(payload.name)\(payload.address.map { ", \($0)" } ?? "")")
    }
}

// MARK: - LocationPayload + MapAnnotationProtocol conformance (Identifiable bridging)

extension LocationPayload: Identifiable {
    public var id: String { "\(latitude),\(longitude)" }
}

// MARK: - AC_FileCard

struct AC_FileCard: View {
    let payload: FilePayload
    let onRemove: () -> Void

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            HStack(spacing: 12) {
                // File type icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: mimeIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(iconForeground)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mimeLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    // BTN-002 LANE-8: Preview gated — QLPreviewController requires UIKit sheet presentation
                    // Disabled until a SwiftUI-compatible QuickLook wrapper is wired at the host level.
                    Button {
                        // no-op placeholder; guarded by .disabled below
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .accessibilityLabel("Preview \(payload.name)")
                    .accessibilityHint("File preview not available in this version")

                    // BTN-002 LANE-8: wired — opens downloadURL in Files app / Safari
                    Button {
                        if let url = URL(string: payload.downloadURL) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(_acbAmenGold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Download \(payload.name)")
                    .accessibilityHint("Opens file in browser or Files app")
                }
                .padding(.trailing, 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File attachment: \(payload.name), \(formattedSize)")
    }

    private var formattedSize: String {
        let bytes = payload.sizeBytes
        switch bytes {
        case 0 ..< 1_024:
            return "\(bytes) B"
        case 1_024 ..< 1_048_576:
            return String(format: "%.1f KB", Double(bytes) / 1_024)
        case 1_048_576 ..< 1_073_741_824:
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        default:
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
    }

    private var mimeIcon: String {
        let mime = payload.mimeType.lowercased()
        if mime.contains("pdf") { return "doc.fill" }
        if mime.contains("image") { return "photo.fill" }
        if mime.contains("video") { return "video.fill" }
        if mime.contains("audio") { return "waveform" }
        if mime.contains("word") || mime.contains("document") { return "doc.text.fill" }
        if mime.contains("sheet") || mime.contains("excel") || mime.contains("csv") { return "tablecells.fill" }
        if mime.contains("presentation") || mime.contains("powerpoint") { return "rectangle.on.rectangle.fill" }
        if mime.contains("zip") || mime.contains("compressed") { return "archivebox.fill" }
        return "paperclip"
    }

    private var mimeLabel: String {
        let mime = payload.mimeType.lowercased()
        if mime.contains("pdf") { return "PDF" }
        if mime.contains("jpeg") || mime.contains("jpg") { return "JPEG Image" }
        if mime.contains("png") { return "PNG Image" }
        if mime.contains("mp4") { return "MP4 Video" }
        if mime.contains("mp3") { return "MP3 Audio" }
        if mime.contains("word") { return "Word Document" }
        if mime.contains("sheet") || mime.contains("excel") { return "Spreadsheet" }
        if mime.contains("presentation") { return "Presentation" }
        if mime.contains("zip") { return "Archive" }
        return payload.mimeType
    }

    private var iconBackground: Color {
        let mime = payload.mimeType.lowercased()
        if mime.contains("pdf") { return Color.red.opacity(0.12) }
        if mime.contains("image") { return Color.purple.opacity(0.12) }
        if mime.contains("video") { return Color.blue.opacity(0.12) }
        if mime.contains("audio") { return Color.green.opacity(0.12) }
        if mime.contains("word") || mime.contains("document") { return Color.blue.opacity(0.12) }
        if mime.contains("sheet") || mime.contains("excel") { return Color.green.opacity(0.12) }
        return Color(.tertiarySystemFill)
    }

    private var iconForeground: Color {
        let mime = payload.mimeType.lowercased()
        if mime.contains("pdf") { return .red }
        if mime.contains("image") { return .purple }
        if mime.contains("video") { return .blue }
        if mime.contains("audio") { return .green }
        if mime.contains("word") || mime.contains("document") { return .blue }
        if mime.contains("sheet") || mime.contains("excel") { return .green }
        return .secondary
    }
}

// MARK: - AC_ChecklistCard

struct AC_ChecklistCard: View {
    let payload: AdaptiveComposerChecklistPayload
    let onRemove: () -> Void
    /// Caller injects the parent postId so checklist toggles persist to Firestore.
    @Environment(\.adaptiveComposerPostId) private var postId

    // Local checked state for optimistic UI; Firestore write is deferred below
    @State private var checkedIds: Set<String>

    init(payload: AdaptiveComposerChecklistPayload, onRemove: @escaping () -> Void) {
        self.payload = payload
        self.onRemove = onRemove
        let initialChecked = Set(payload.items.filter(\.isChecked).map(\.id))
        _checkedIds = State(initialValue: initialChecked)
    }

    private var completedCount: Int { checkedIds.count }
    private var totalCount: Int { payload.items.count }

    var body: some View {
        AdaptiveCardContainer(onRemove: onRemove) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(_acbAmenGold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(completedCount) of \(totalCount) complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 44)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
                .padding(.top, 4)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(_acbAmenGold)
                            .frame(
                                width: totalCount > 0
                                    ? geo.size.width * CGFloat(completedCount) / CGFloat(totalCount)
                                    : 0
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: completedCount)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .accessibilityLabel("Progress: \(completedCount) of \(totalCount) items complete")

                // Checklist items
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(payload.items) { item in
                        AC_ChecklistRow(
                            item: item,
                            isChecked: checkedIds.contains(item.id)
                        ) { newValue in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if newValue {
                                    checkedIds.insert(item.id)
                                } else {
                                    checkedIds.remove(item.id)
                                }
                            }
                            // BTN-002 LANE-8: Firestore update checklist item isChecked
                            if let pid = postId {
                                let db = Firestore.firestore()
                                db.collection("posts").document(pid)
                                    .updateData([
                                        "checklist.items.\(item.id).isChecked": newValue,
                                        "checklist.updatedAt": FieldValue.serverTimestamp()
                                    ])
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checklist: \(payload.title), \(completedCount) of \(totalCount) complete")
    }
}

private struct AC_ChecklistRow: View {
    let item: AdaptiveComposerChecklistItem
    let isChecked: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isChecked)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isChecked ? _acbAmenGold : Color(.tertiaryLabel))
                    .accessibilityHidden(true)

                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .strikethrough(isChecked, color: .secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let assignee = item.assigneeUID {
                    Text(assignee.prefix(2).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(_acbAmenGold.opacity(0.75)))
                        .accessibilityLabel("Assigned to user \(assignee)")
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.text)\(isChecked ? ", completed" : ", not completed")\(item.assigneeUID != nil ? ", assigned" : "")")
        .accessibilityHint(isChecked ? "Tap to uncheck" : "Tap to check")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
