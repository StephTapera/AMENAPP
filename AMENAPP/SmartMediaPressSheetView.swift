// SmartMediaPressSheetView.swift
// AMEN App — Context-aware action sheet for long-pressed post media.
// Adapts actions per media type, account type, and social context.
// iOS-only sheet with presentationDetents.

import SwiftUI

// MARK: - Models

struct MediaPressContext {
    let item: CarouselMediaItem
    let postIntent: String          // "sermonClip", "testimony", "eventRecap", etc.
    let accountType: String         // "personal", "church", "business"
    let isOfficialAccount: Bool
    let hasMutualsContext: Bool     // true if viewer has mutuals who attend this church
}

struct MediaSmartAction: Identifiable {
    let id = UUID()
    let icon: String                // SF Symbol
    let label: String
    let description: String
    let isDestructive: Bool
    let action: () -> Void
}

// MARK: - SmartMediaPressSheetView

struct SmartMediaPressSheetView: View {
    let context: MediaPressContext
    @Binding var isPresented: Bool
    let onAction: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Sheet background
                Color(white: 0.97).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────────────────────
                    sheetHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // ── Actions list ──────────────────────────────────────────
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(resolvedActions) { smartAction in
                                actionRow(smartAction)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }

                    // ── Dismiss button ────────────────────────────────────────
                    dismissButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        HStack(spacing: 14) {
            // Media type icon in glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
                    .frame(width: 48, height: 48)

                Image(systemName: context.item.type == .video ? "play.rectangle.fill" : "photo.fill")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.70))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.black)

                Text(headerSubtitle)
                    .font(.systemScaled(13, weight: .regular))
                    .foregroundStyle(.black.opacity(0.50))
            }

            Spacer()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: - Action Row

    private func actionRow(_ smartAction: MediaSmartAction) -> some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))) {
                smartAction.action()
                onAction(smartAction.label)
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.55)))
                        .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .frame(width: 40, height: 40)

                    Image(systemName: smartAction.icon)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(smartAction.isDestructive ? Color.red.opacity(0.75) : Color.black.opacity(0.70))
                }

                // Label + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(smartAction.label)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(smartAction.isDestructive ? Color.red.opacity(0.85) : Color.black)

                    Text(smartAction.description)
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.black.opacity(0.45))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.25))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))) {
                dismiss()
            }
        } label: {
            Text("Done")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header Strings

    private var headerTitle: String {
        switch context.item.type {
        case .photo: return "Photo Actions"
        case .video: return "Video Actions"
        }
    }

    private var headerSubtitle: String {
        let accountLabel: String
        switch context.accountType {
        case "church":    accountLabel = "Church"
        case "business":  accountLabel = "Business"
        default:          accountLabel = "Personal"
        }
        return "\(accountLabel) · \(context.postIntent.isEmpty ? "Post" : context.postIntent)"
    }

    // MARK: - Resolved Actions

    private var resolvedActions: [MediaSmartAction] {
        switch context.item.type {
        case .photo:
            return photoActions
        case .video:
            return videoActions
        }
    }

    // MARK: - Photo Actions

    private var photoActions: [MediaSmartAction] {
        let accountType = context.accountType

        if accountType == "personal" {
            return personalPhotoActions
        } else {
            return churchBusinessPhotoActions
        }
    }

    private var personalPhotoActions: [MediaSmartAction] {
        [
            MediaSmartAction(
                icon: "photo.fill",
                label: "Save to Memory",
                description: "Keep this in your personal archive",
                isDestructive: false,
                action: { onAction("saveToMemory") }
            ),
            MediaSmartAction(
                icon: "star.fill",
                label: "Save to Testimony",
                description: "Connect this moment to your faith journey",
                isDestructive: false,
                action: { onAction("saveToTestimony") }
            ),
            MediaSmartAction(
                icon: "sparkles",
                label: "Ask Berean",
                description: "Ask about context or scripture related to this",
                isDestructive: false,
                action: { onAction("askBerean") }
            ),
            MediaSmartAction(
                icon: "square.and.arrow.up",
                label: "Share Safely",
                description: "Share with source attribution preserved",
                isDestructive: false,
                action: { onAction("shareSafely") }
            ),
            MediaSmartAction(
                icon: "checkmark.seal",
                label: "Verify Original",
                description: "Review authenticity signals",
                isDestructive: false,
                action: { onAction("verifyOriginal") }
            ),
            MediaSmartAction(
                icon: "exclamationmark.triangle",
                label: "Report Misleading",
                description: "Flag this content for review",
                isDestructive: true,
                action: { onAction("reportMisleading") }
            )
        ]
    }

    private var churchBusinessPhotoActions: [MediaSmartAction] {
        var actions: [MediaSmartAction] = [
            MediaSmartAction(
                icon: "building.2.fill",
                label: "Church Info",
                description: "Service times, address, what to expect",
                isDestructive: false,
                action: { onAction("churchInfo") }
            ),
            MediaSmartAction(
                icon: "mappin.circle.fill",
                label: "Plan Visit",
                description: "Get directions, parking, check-in info",
                isDestructive: false,
                action: { onAction("planVisit") }
            )
        ]

        if context.hasMutualsContext {
            actions.append(
                MediaSmartAction(
                    icon: "person.2.fill",
                    label: "Mutuals Here",
                    description: "See who from your network attends",
                    isDestructive: false,
                    action: { onAction("mutualsHere") }
                )
            )
        }

        actions.append(contentsOf: [
            MediaSmartAction(
                icon: "book.fill",
                label: "Save to Notes",
                description: "Save this to your Church Notes",
                isDestructive: false,
                action: { onAction("saveToNotes") }
            ),
            MediaSmartAction(
                icon: "square.and.arrow.up",
                label: "Share Safely",
                description: "Share with source attribution preserved",
                isDestructive: false,
                action: { onAction("shareSafely") }
            ),
            MediaSmartAction(
                icon: "checkmark.seal",
                label: "Verify Source",
                description: "Review source authenticity signals",
                isDestructive: false,
                action: { onAction("verifySource") }
            )
        ])

        return actions
    }

    // MARK: - Video Actions

    private var videoActions: [MediaSmartAction] {
        var actions: [MediaSmartAction] = [
            MediaSmartAction(
                icon: "captions.bubble.fill",
                label: "Play with Transcript",
                description: "Watch with live captions",
                isDestructive: false,
                action: { onAction("playWithTranscript") }
            ),
            MediaSmartAction(
                icon: "text.alignleft",
                label: "View Transcript",
                description: "Read the full spoken text",
                isDestructive: false,
                action: { onAction("viewTranscript") }
            ),
            MediaSmartAction(
                icon: "sparkles",
                label: "Summarize Clip",
                description: "Get AI key points and themes",
                isDestructive: false,
                action: { onAction("summarizeClip") }
            ),
            MediaSmartAction(
                icon: "bolt.fill",
                label: "Jump to Key Moment",
                description: "Skip to the strongest part",
                isDestructive: false,
                action: { onAction("jumpToKeyMoment") }
            ),
            MediaSmartAction(
                icon: "book.fill",
                label: "Detect Verse",
                description: "Find scripture references in this clip",
                isDestructive: false,
                action: { onAction("detectVerse") }
            ),
            MediaSmartAction(
                icon: "square.and.pencil",
                label: "Create Church Note",
                description: "Turn this clip into personal notes",
                isDestructive: false,
                action: { onAction("createChurchNote") }
            ),
            MediaSmartAction(
                icon: "list.bullet",
                label: "Extract Key Points",
                description: "Structured takeaways",
                isDestructive: false,
                action: { onAction("extractKeyPoints") }
            ),
            MediaSmartAction(
                icon: "square.and.arrow.up",
                label: "Safe Share",
                description: "Share with source integrity",
                isDestructive: false,
                action: { onAction("safeShare") }
            )
        ]

        // Church admin moderation action
        if context.accountType == "church" || context.accountType == "business" {
            actions.append(
                MediaSmartAction(
                    icon: "shield.fill",
                    label: "Moderate Replies",
                    description: "Manage who can reply to this clip",
                    isDestructive: false,
                    action: { onAction("moderateReplies") }
                )
            )
        }

        // Official account extras
        if context.isOfficialAccount {
            actions.append(contentsOf: [
                MediaSmartAction(
                    icon: "clock.fill",
                    label: "Service Time",
                    description: "Show upcoming service schedule",
                    isDestructive: false,
                    action: { onAction("serviceTime") }
                ),
                MediaSmartAction(
                    icon: "location.fill",
                    label: "Directions",
                    description: "Get directions to this location",
                    isDestructive: false,
                    action: { onAction("directions") }
                )
            ])
        }

        return actions
    }
}

// MARK: - Preview

#if DEBUG
struct SmartMediaPressSheetView_Previews: PreviewProvider {
    @State static var isPresented = true

    static var previews: some View {
        Group {
            // Photo + church context
            Text("Photo Church Context")
                .sheet(isPresented: .constant(true)) {
                    SmartMediaPressSheetView(
                        context: MediaPressContext(
                            item: CarouselMediaItem(
                                id: "prev1",
                                type: .photo,
                                thumbnailURL: nil,
                                videoURL: nil,
                                trustLabel: "Verified original",
                                contextTag: "Church event"
                            ),
                            postIntent: "eventRecap",
                            accountType: "church",
                            isOfficialAccount: true,
                            hasMutualsContext: true
                        ),
                        isPresented: .constant(true),
                        onAction: { action in
                            print("Action: \(action)")
                        }
                    )
                }
                .previewDisplayName("Photo · Church")

            // Video context
            Text("Video Context")
                .sheet(isPresented: .constant(true)) {
                    SmartMediaPressSheetView(
                        context: MediaPressContext(
                            item: CarouselMediaItem(
                                id: "prev2",
                                type: .video,
                                thumbnailURL: nil,
                                videoURL: nil,
                                trustLabel: nil,
                                contextTag: "Sermon clip"
                            ),
                            postIntent: "sermonClip",
                            accountType: "personal",
                            isOfficialAccount: false,
                            hasMutualsContext: false
                        ),
                        isPresented: .constant(true),
                        onAction: { action in
                            print("Action: \(action)")
                        }
                    )
                }
                .previewDisplayName("Video · Personal")
        }
    }
}
#endif
