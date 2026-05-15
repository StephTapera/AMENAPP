import SwiftUI
import UIKit

enum UploadCapsuleState: Equatable {
    case preparing
    case uploading
    case processing
    case moderating
    case finalizing
    case success
    case failed(message: String?)
    case blocked(reason: String?)
    case reviewRequired
}

enum UploadCapsuleMediaStatus: Equatable {
    case waiting
    case preparing
    case uploading(progress: Double)
    case uploaded
    case processing
    case moderating
    case passed
    case failed
    case blocked
    case reviewRequired
}

enum UploadCapsuleMediaKind: Equatable {
    case image
    case video
}

struct UploadCapsuleMediaItem: Identifiable, Equatable {
    let id: String
    let thumbnailImage: UIImage?
    let kind: UploadCapsuleMediaKind
    let status: UploadCapsuleMediaStatus

    static func == (lhs: UploadCapsuleMediaItem, rhs: UploadCapsuleMediaItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.status == rhs.status
    }
}

enum UploadCapsuleMetrics {
    static func clampedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func percent(_ progress: Double) -> Int {
        Int((clampedProgress(progress) * 100).rounded())
    }

    static func weightedProgress(for state: UploadCapsuleState, stageProgress: Double) -> Double {
        let stageValue = clampedProgress(stageProgress)
        switch state {
        case .preparing:
            return stageValue * 0.10
        case .uploading:
            return 0.10 + (stageValue * 0.60)
        case .processing:
            return 0.70 + (stageValue * 0.12)
        case .moderating:
            return 0.82 + (stageValue * 0.12)
        case .finalizing:
            return 0.94 + (stageValue * 0.06)
        case .success:
            return 1
        case .failed, .blocked, .reviewRequired:
            return stageValue
        }
    }

    static func title(for state: UploadCapsuleState, uploadedCount: Int, totalCount: Int) -> String {
        switch state {
        case .preparing:
            return "Preparing media"
        case .uploading:
            let noun = totalCount == 1 ? "item" : "items"
            return "Uploading \(max(totalCount, 1)) \(noun)"
        case .processing:
            return "Processing media"
        case .moderating:
            return "Checking media"
        case .finalizing:
            return "Finalizing post"
        case .success:
            return "Posted"
        case .failed:
            return "Upload failed"
        case .blocked:
            return "Cannot post media"
        case .reviewRequired:
            return "Under review"
        }
    }

    static func meta(
        for state: UploadCapsuleState,
        progress: Double,
        uploadedCount: Int,
        totalCount: Int
    ) -> String {
        switch state {
        case .preparing:
            return "Getting images ready"
        case .uploading:
            return "\(percent(progress))% • safe to keep editing"
        case .processing:
            return "Optimizing quality"
        case .moderating:
            if totalCount > 0 {
                return "\(min(uploadedCount, totalCount)) of \(totalCount) ready • safety review in progress"
            }
            return "Safety review in progress"
        case .finalizing:
            return "Almost done"
        case .success:
            return "Saved"
        case .failed(let message):
            return message?.isEmpty == false ? message! : "Tap retry"
        case .blocked:
            return "Review the selected media"
        case .reviewRequired:
            return "We'll keep this private for now"
        }
    }

    static func accessibilitySummary(
        for state: UploadCapsuleState,
        progress: Double,
        uploadedCount: Int,
        totalCount: Int
    ) -> String {
        let title = title(for: state, uploadedCount: uploadedCount, totalCount: totalCount)
        let meta = meta(for: state, progress: progress, uploadedCount: uploadedCount, totalCount: totalCount)
        if totalCount > 0 {
            return "\(title). \(uploadedCount) of \(totalCount) items ready. \(meta)"
        }
        return "\(title). \(meta)"
    }
}

struct LiquidGlassUploadCapsule: View {
    let state: UploadCapsuleState
    let progress: Double
    let uploadedCount: Int
    let totalCount: Int
    let mediaItems: [UploadCapsuleMediaItem]
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onRetry: (() -> Void)?
    let onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -0.8
    @State private var amenPulse = false
    @State private var successBloom = false

    private var normalizedProgress: Double {
        UploadCapsuleMetrics.clampedProgress(progress)
    }

    private var title: String {
        UploadCapsuleMetrics.title(for: state, uploadedCount: uploadedCount, totalCount: totalCount)
    }

    private var meta: String {
        UploadCapsuleMetrics.meta(for: state, progress: normalizedProgress, uploadedCount: uploadedCount, totalCount: totalCount)
    }

    private var accessibilitySummary: String {
        UploadCapsuleMetrics.accessibilitySummary(
            for: state,
            progress: normalizedProgress,
            uploadedCount: uploadedCount,
            totalCount: totalCount
        )
    }

    private var isActive: Bool {
        switch state {
        case .preparing, .uploading, .processing, .moderating, .finalizing:
            return true
        default:
            return false
        }
    }

    private var isFailure: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private var tintGradient: LinearGradient {
        if isFailure {
            return LinearGradient(
                colors: [
                    Color.red.opacity(0.08),
                    Color.red.opacity(0.18),
                    Color.white.opacity(0.14)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        if case .blocked = state {
            return LinearGradient(
                colors: [
                    Color.orange.opacity(0.08),
                    Color.orange.opacity(0.16),
                    Color.white.opacity(0.14)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.43, green: 0.70, blue: 1.0).opacity(0.10),
                Color(red: 0.33, green: 0.63, blue: 1.0).opacity(0.24),
                Color.white.opacity(0.18)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)

                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(tintGradient)
                        .frame(width: max(proxy.size.width * normalizedProgress, 28))
                        .blur(radius: 0.4)
                }
                .allowsHitTesting(false)

                if isActive && !reduceMotion {
                    GeometryReader { proxy in
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.white.opacity(0.34), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: min(110, proxy.size.width * 0.35))
                            .offset(x: proxy.size.width * shimmerOffset)
                            .blur(radius: 0.8)
                    }
                    .allowsHitTesting(false)
                }

                capsuleContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            }
            .frame(minHeight: 62)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.10), radius: 20, y: 10)
            .overlay(successGlow)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isExpanded ? 124 : 62, alignment: .top)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpanded)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
        .onAppear(perform: startAnimationsIfNeeded)
        .onChange(of: state) { _, _ in
            startAnimationsIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") upload details.")
    }

    @ViewBuilder
    private var capsuleContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statusOrb

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(meta)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                mediaRail

                HStack(spacing: 8) {
                    if let onRetry, isFailure {
                        Button("Retry", action: onRetry)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red.opacity(0.78))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.76), lineWidth: 0.7))
                            .accessibilityLabel("Retry upload")
                    }

                    if let onCancel, isExpanded, isActive {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.65))
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel upload")
                    }

                    amenMark
                }
            }

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.62))
            Circle()
                .stroke(Color.white.opacity(0.80), lineWidth: 0.8)

            Image(systemName: statusIconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusIconColor)
                .rotationEffect(isActive && !reduceMotion ? .degrees(amenPulse ? 360 : 0) : .zero)
                .animation(isActive && !reduceMotion ? .linear(duration: 2.2).repeatForever(autoreverses: false) : .default, value: amenPulse)
        }
        .frame(width: 40, height: 40)
    }

    private var mediaRail: some View {
        HStack(spacing: 5) {
            ForEach(mediaItems.prefix(3)) { item in
                UploadCapsuleThumbnail(item: item, reduceMotion: reduceMotion)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: mediaItems.isEmpty ? 0 : 34)
    }

    private var amenMark: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.66))
                Circle()
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)

                Text("A")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(Color.black)
            }
            .frame(width: 36, height: 36)
            .scaleEffect(isActive && !reduceMotion ? (amenPulse ? 1.04 : 0.98) : 1)
            .animation(
                isActive && !reduceMotion ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .easeOut(duration: 0.18),
                value: amenPulse
            )

            if case .success = state {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Color.black, in: Circle())
                    .offset(x: 2, y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(UploadCapsuleMetrics.percent(normalizedProgress))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .monospacedDigit()

                Text(expandedCaption)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.46))
                    .textCase(.uppercase)
            }
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(expandedDetail)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)

                if !mediaItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(mediaItems) { item in
                                HStack(spacing: 6) {
                                    UploadCapsuleThumbnail(item: item, reduceMotion: reduceMotion)
                                    Text(item.status.accessibilityLabel)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.black.opacity(0.52))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.34), in: Capsule(style: .continuous))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.56), lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private var successGlow: some View {
        if case .success = state {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(successBloom ? 0 : 0.54), lineWidth: successBloom ? 14 : 1)
                .scaleEffect(successBloom ? 1.06 : 1)
                .opacity(successBloom ? 0 : 1)
        }
    }

    private var statusIconName: String {
        switch state {
        case .preparing, .uploading, .processing, .moderating, .finalizing:
            return "sparkle"
        case .success:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        case .blocked, .reviewRequired:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusIconColor: Color {
        switch state {
        case .failed:
            return Color.red.opacity(0.82)
        case .blocked, .reviewRequired:
            return Color.orange.opacity(0.82)
        case .success:
            return Color.black
        default:
            return Color.blue.opacity(0.92)
        }
    }

    private var expandedCaption: String {
        switch state {
        case .success:
            return "Complete"
        case .failed:
            return "Needs Action"
        case .blocked:
            return "Blocked"
        case .reviewRequired:
            return "Pending Review"
        default:
            return "Upload Progress"
        }
    }

    private var expandedDetail: String {
        switch state {
        case .preparing:
            return "Creating thumbnails, validating media, and preparing the upload queue."
        case .uploading:
            return "You can keep editing while Amen uploads your media in the background."
        case .processing:
            return "Amen is organizing metadata and preparing display assets."
        case .moderating:
            return "Safety review is running before media is finalized for the post."
        case .finalizing:
            return "Saving the post and linking the uploaded media."
        case .success:
            return "Your post and media were saved successfully."
        case .failed(let message):
            return message?.isEmpty == false ? message! : "The composer stays open so you can retry without losing work."
        case .blocked:
            return "This media could not be posted because it may violate community safety rules. Remove it or choose different media."
        case .reviewRequired:
            return "This post stays private until Amen finishes review."
        }
    }

    private func startAnimationsIfNeeded() {
        if isActive && !reduceMotion {
            shimmerOffset = -0.4
            amenPulse = true
            withAnimation(.linear(duration: 2.1).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.2
            }
        } else {
            shimmerOffset = -0.8
            amenPulse = false
        }

        if case .success = state {
            successBloom = false
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                successBloom = true
            }
        }
    }
}

private struct UploadCapsuleThumbnail: View {
    let item: UploadCapsuleMediaItem
    let reduceMotion: Bool

    private var statusColor: Color {
        switch item.status {
        case .failed:
            return .red
        case .blocked, .reviewRequired:
            return .orange
        case .passed, .uploaded:
            return .black
        default:
            return Color.blue.opacity(0.88)
        }
    }

    private var statusBadgeName: String? {
        switch item.status {
        case .passed, .uploaded:
            return "checkmark"
        case .failed:
            return "xmark"
        case .blocked, .reviewRequired:
            return "exclamationmark"
        default:
            return nil
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.76))

                if let thumbnailImage = item.thumbnailImage {
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 0.8)
            )
            .overlay(alignment: .center) {
                if case .uploading(let progress) = item.status {
                    Circle()
                        .trim(from: 0, to: UploadCapsuleMetrics.clampedProgress(progress))
                        .stroke(
                            statusColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .linear(duration: 0.18), value: progress)
                } else if [.preparing, .processing, .moderating].contains(item.status.staticState) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(statusColor.opacity(0.70), lineWidth: 1.6)
                        .padding(1.5)
                        .opacity(reduceMotion ? 1 : 0.72)
                }
            }

            if let statusBadgeName {
                Image(systemName: statusBadgeName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(statusColor, in: Circle())
                    .offset(x: 2, y: -2)
            }
        }
    }
}

private extension UploadCapsuleMediaStatus {
    var staticState: UploadCapsuleMediaStatus {
        switch self {
        case .uploading:
            return .uploading(progress: 0)
        default:
            return self
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .preparing:
            return "Preparing"
        case .uploading(let progress):
            return "Uploading \(UploadCapsuleMetrics.percent(progress)) percent"
        case .uploaded:
            return "Uploaded"
        case .processing:
            return "Processing"
        case .moderating:
            return "Checking"
        case .passed:
            return "Ready"
        case .failed:
            return "Failed"
        case .blocked:
            return "Blocked"
        case .reviewRequired:
            return "Under review"
        }
    }
}

#Preview("Compact Uploading") {
    LiquidGlassUploadCapsule(
        state: .uploading,
        progress: 0.43,
        uploadedCount: 1,
        totalCount: 2,
        mediaItems: [
            UploadCapsuleMediaItem(id: "1", thumbnailImage: nil, kind: .image, status: .uploaded),
            UploadCapsuleMediaItem(id: "2", thumbnailImage: nil, kind: .image, status: .uploading(progress: 0.43))
        ],
        isExpanded: false,
        onToggleExpanded: {},
        onRetry: nil,
        onCancel: nil
    )
    .padding()
    .background(Color.white)
}

#Preview("Expanded Failed") {
    LiquidGlassUploadCapsule(
        state: .failed(message: nil),
        progress: 0.58,
        uploadedCount: 1,
        totalCount: 2,
        mediaItems: [
            UploadCapsuleMediaItem(id: "1", thumbnailImage: nil, kind: .image, status: .uploaded),
            UploadCapsuleMediaItem(id: "2", thumbnailImage: nil, kind: .video, status: .failed)
        ],
        isExpanded: true,
        onToggleExpanded: {},
        onRetry: {},
        onCancel: nil
    )
    .padding()
    .background(Color.white)
}
