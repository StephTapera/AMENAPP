//
//  AmenPostMediaRenderer.swift
//  AMENAPP
//
//  Renders [AmenMediaAttachment] from a published post.
//  Used in feed cells (isCompact: true) and post detail (isCompact: false).
//
//  Autoplay policy:
//  - Music: never autoplays — tap only.
//  - Video: tap-to-play only — no autoplay.
//  - Includes AmenMediaVisibilityModifier for future autoplay-on-scroll wiring.
//

import SwiftUI

// MARK: - AmenPostMediaRenderer

struct AmenPostMediaRenderer: View {

    let attachments: [AmenMediaAttachment]
    var isCompact: Bool = true
    var onAskBerean: ((AmenMediaAttachment) -> Void)? = nil

    @State private var hasAppeared = false

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else if isCompact {
            compactBody
        } else {
            detailBody
        }
    }

    // MARK: Compact (feed cell)

    @ViewBuilder
    private var compactBody: some View {
        if attachments.count == 1, let single = attachments.first {
            if single.kind == .music {
                // onTap: no-op in compact feed mode; AmenMusicCardContainer handles mode transitions
                AmenMusicCardCompact(attachment: single, onTap: {})
                    .amenMediaVisibility(attachment: single)
            } else {
                AmenSmartMediaCardRouter(
                    attachment: single,
                    isCompact: true,
                    onRemove: nil,
                    onAskBerean: onAskBerean.map { cb in { cb(single) } }
                )
                .amenMediaVisibility(attachment: single)
            }
        } else {
            AmenAttachmentRail(attachments: attachments, onRemove: nil)
        }
    }

    // MARK: Detail (post detail view)

    @ViewBuilder
    private var detailBody: some View {
        if attachments.count == 1, let single = attachments.first {
            switch single.kind {
            case .music:
                AmenMusicCardContainer(attachment: single)
                    .amenMediaVisibility(attachment: single)

            case .video:
                // Tap-to-play only — AmenVideoAttachmentCard handles its own playback
                AmenSmartMediaCardRouter(
                    attachment: single,
                    isCompact: false,
                    onRemove: nil,
                    onAskBerean: onAskBerean.map { cb in { cb(single) } }
                )
                .amenMediaVisibility(attachment: single)

            default:
                AmenSmartMediaCardRouter(
                    attachment: single,
                    isCompact: false,
                    onRemove: nil,
                    onAskBerean: onAskBerean.map { cb in { cb(single) } }
                )
                .amenMediaVisibility(attachment: single)
            }
        } else {
            // Multiple attachments: vertical stack in detail, rail in compact
            VStack(spacing: 12) {
                ForEach(attachments) { attachment in
                    AmenSmartMediaCardRouter(
                        attachment: attachment,
                        isCompact: false,
                        onRemove: nil,
                        onAskBerean: onAskBerean.map { cb in { cb(attachment) } }
                    )
                    .amenMediaVisibility(attachment: attachment)
                }
            }
        }
    }
}

// MARK: - AmenMediaVisibilityModifier

/// Tracks the visible fraction of a media card in the scroll view.
/// Registers/unregisters the attachment with AmenMediaVisibilityCoordinator
/// and forwards frame updates for autoplay-on-scroll evaluation.
struct AmenMediaVisibilityModifier: ViewModifier {

    let attachment: AmenMediaAttachment

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: AmenMediaVisibilityKey.self,
                            value: [
                                AmenMediaVisibilityEntry(
                                    attachmentID: attachment.id,
                                    frame: proxy.frame(in: .global)
                                )
                            ]
                        )
                }
            )
            .onPreferenceChange(AmenMediaVisibilityKey.self) { entries in
                for entry in entries {
                    AmenMediaVisibilityCoordinator.shared.report(id: entry.attachmentID, frame: entry.frame)
                }
            }
            .onAppear {
                AmenMediaVisibilityCoordinator.shared.register(attachment: attachment)
            }
            .onDisappear {
                AmenMediaVisibilityCoordinator.shared.unregister(id: attachment.id)
            }
    }
}

// MARK: - AmenMediaVisibilityKey (PreferenceKey)

struct AmenMediaVisibilityEntry: Equatable {
    let attachmentID: String
    let frame: CGRect
}

private struct AmenMediaVisibilityKey: PreferenceKey {
    static let defaultValue: [AmenMediaVisibilityEntry] = []

    static func reduce(value: inout [AmenMediaVisibilityEntry], nextValue: () -> [AmenMediaVisibilityEntry]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View extension

extension View {
    /// Attaches the media visibility tracker to a media card view.
    func amenMediaVisibility(attachment: AmenMediaAttachment) -> some View {
        modifier(AmenMediaVisibilityModifier(attachment: attachment))
    }

    /// Convenience overload for call sites that only have an ID (non-playable cards).
    func amenMediaVisibility(attachmentID: String) -> some View {
        // Non-playable stub — no autoplay registration; only provides ID for preference tracking.
        modifier(AmenMediaVisibilityModifier(
            attachment: AmenMediaAttachment(
                id: attachmentID, kind: .link,
                sourceURL: nil, title: "", subtitle: nil,
                thumbnailURL: nil, accentHex: nil
            )
        ))
    }
}
