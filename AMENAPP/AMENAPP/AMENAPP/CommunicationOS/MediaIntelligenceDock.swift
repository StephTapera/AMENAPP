// MediaIntelligenceDock.swift
// AMENAPP
//
// Floating dock shown when user opens a media message (photo, video, voice, file, link).
// Only shows actions that are actually available for the media type.
// Gated by mediaIntelligenceEnabled.

import SwiftUI
import FirebaseFunctions

enum AmenMediaAttachmentType {
    case photo, video, voice, file, link
}

enum MediaDockAction: String, CaseIterable {
    case summarize    = "Summarize"
    case transcribe   = "Transcribe"
    case keyMoments   = "Key Moments"
    case replyMoment  = "Reply to Moment"
    case save         = "Save"
    case createTask   = "Create Task"
    case extractText  = "Extract Text"
    case searchRelated = "Search Related"
    case share        = "Share"

    var icon: String {
        switch self {
        case .summarize:    return "text.quote"
        case .transcribe:   return "waveform"
        case .keyMoments:   return "sparkles"
        case .replyMoment:  return "arrowshape.turn.up.left"
        case .save:         return "square.and.arrow.down"
        case .createTask:   return "checkmark.circle"
        case .extractText:  return "text.viewfinder"
        case .searchRelated: return "magnifyingglass"
        case .share:        return "square.and.arrow.up"
        }
    }

    func isAvailable(for mediaType: AmenMediaAttachmentType) -> Bool {
        switch (self, mediaType) {
        case (.summarize, .video), (.summarize, .voice), (.summarize, .link): return true
        case (.transcribe, .video), (.transcribe, .voice): return true
        case (.keyMoments, .video): return true
        case (.replyMoment, .video): return true
        case (.save, _): return true
        case (.createTask, _): return AMENFeatureFlags.shared.threadActionExtractionEnabled
        case (.extractText, .photo): return true
        case (.searchRelated, _): return AMENFeatureFlags.shared.conversationMemorySearchEnabled
        case (.share, _): return true
        default: return false
        }
    }
}

enum MediaContextState: Equatable {
    case idle, loading, succeeded(String), failed
}

@MainActor
final class MediaIntelligenceViewModel: ObservableObject {
    @Published var contextState: MediaContextState = .idle

    func generateContext(messageId: String, mediaUrl: String, mediaType: AmenMediaAttachmentType) {
        guard AMENFeatureFlags.shared.mediaIntelligenceEnabled else { return }
        contextState = .loading
        AmenMessagingAnalytics.track(.mediaContextOpened)
        Task {
            do {
                let functions = Functions.functions()
                let typeStr: String
                switch mediaType {
                case .photo: typeStr = "photo"
                case .video: typeStr = "video"
                case .voice: typeStr = "voice"
                case .file:  typeStr = "file"
                case .link:  typeStr = "link"
                }
                let result = try await functions.httpsCallable("generateMediaContext").call([
                    "messageId": messageId,
                    "mediaUrl": mediaUrl,
                    "mediaType": typeStr
                ])
                if let data = result.data as? [String: Any],
                   let summary = data["summary"] as? String {
                    contextState = .succeeded(summary)
                    AmenMessagingAnalytics.track(.mediaSummaryGenerated)
                } else {
                    contextState = .failed
                }
            } catch {
                contextState = .failed
            }
        }
    }
}

struct MediaIntelligenceDock: View {
    let messageId: String
    let mediaUrl: String
    let mediaType: AmenMediaAttachmentType
    var onAction: (MediaDockAction) -> Void
    var onDismiss: () -> Void

    @StateObject private var viewModel = MediaIntelligenceViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    private var availableActions: [MediaDockAction] {
        MediaDockAction.allCases.filter { $0.isAvailable(for: mediaType) }
    }

    var body: some View {
        VStack(spacing: 12) {
            dockHeader
            contextSummary
            actionsScrollView
        }
        .padding(16)
        .background(dockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 6)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.78)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media actions")
    }

    private var dockHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: mediaTypeIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(mediaTypeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close media actions")
        }
    }

    @ViewBuilder
    private var contextSummary: some View {
        switch viewModel.contextState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .succeeded(let summary):
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    private var actionsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableActions, id: \.self) { action in
                    dockButton(action)
                }
            }
        }
    }

    private func dockButton(_ action: MediaDockAction) -> some View {
        Button {
            AmenMessagingAnalytics.track(.mediaContextOpened, parameters: ["action": action.rawValue])
            if action == .summarize {
                viewModel.generateContext(messageId: messageId, mediaUrl: mediaUrl, mediaType: mediaType)
            } else {
                onAction(action)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .background(actionBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.primary)
                Text(action.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
        .buttonStyle(ClusterButtonStyle2())
        .accessibilityLabel(action.rawValue)
    }

    private var mediaTypeIcon: String {
        switch mediaType {
        case .photo: return "photo"
        case .video: return "play.rectangle"
        case .voice: return "waveform"
        case .file:  return "doc"
        case .link:  return "link"
        }
    }

    private var mediaTypeLabel: String {
        switch mediaType {
        case .photo: return "Photo"
        case .video: return "Video"
        case .voice: return "Voice Note"
        case .file:  return "File"
        case .link:  return "Link"
        }
    }

    private var dockBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.systemBackground)) }
        return AnyShapeStyle(.regularMaterial)
    }

    private var actionBackground: some ShapeStyle {
        if reduceTransparency { return AnyShapeStyle(Color(.tertiarySystemBackground)) }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct ClusterButtonStyle2: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
