import SwiftUI

enum AmenMessagingAttachmentAction: String, CaseIterable, Identifiable {
    case camera
    case photos
    case stickers
    case voice
    case files
    case poll
    case sendLater
    case prayerRequest
    case saveToNotes
    case saveToSelah
    case addToChurchNotes
    case shareWithGroup
    case askBerean
    case startReflection
    case createReminder
    case shareSafely

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .photos: return "Photos"
        case .stickers: return "Stickers"
        case .voice: return "Voice Note"
        case .files: return "Files"
        case .poll: return "Poll"
        case .sendLater: return "Send Later"
        case .prayerRequest: return "Prayer Request"
        case .saveToNotes: return "Save to Notes"
        case .saveToSelah: return "Save to Selah"
        case .addToChurchNotes: return "Add to Church Notes"
        case .shareWithGroup: return "Share with Group"
        case .askBerean: return "Ask Berean"
        case .startReflection: return "Start Reflection"
        case .createReminder: return "Create Reminder"
        case .shareSafely: return "Share Safely"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .photos: return "photo.on.rectangle"
        case .stickers: return "face.smiling"
        case .voice: return "waveform"
        case .files: return "doc.fill"
        case .poll: return "chart.bar.fill"
        case .sendLater: return "clock.badge.checkmark"
        case .prayerRequest: return "hands.sparkles"
        case .saveToNotes: return "square.and.pencil"
        case .saveToSelah: return "bookmark.fill"
        case .addToChurchNotes: return "note.text"
        case .shareWithGroup: return "person.3.fill"
        case .askBerean: return "sparkles"
        case .startReflection: return "brain.head.profile"
        case .createReminder: return "bell.fill"
        case .shareSafely: return "lock.shield"
        }
    }
}

enum AmenMessagingAttachmentAvailability: Equatable {
    case enabled
    case unavailable(String)

    var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

struct AmenMessagingAttachmentMenuItem: Identifiable, Equatable {
    let action: AmenMessagingAttachmentAction
    let subtitle: String?
    let availability: AmenMessagingAttachmentAvailability

    var id: String { action.rawValue }
}

struct AmenMessagingPrivateActionBackendAvailability: Equatable {
    var saveMessageToNotes: Bool
    var createMessageReminder: Bool
    var createSelahReflectionFromMessage: Bool

    static let phase1ProductionContracts = AmenMessagingPrivateActionBackendAvailability(
        saveMessageToNotes: true,
        createMessageReminder: true,
        createSelahReflectionFromMessage: true
    )
}

enum AmenMessagingAttachmentMenuPresentationMode: Equatable {
    case legacyTray
    case liquidGlassMenu

    static func resolve(liquidGlassMenuEnabled: Bool) -> AmenMessagingAttachmentMenuPresentationMode {
        liquidGlassMenuEnabled ? .liquidGlassMenu : .legacyTray
    }
}

@MainActor
struct AmenMessagingAttachmentActionRouter {
    static func menuItems(
        flags: AMENFeatureFlags,
        selectedMessage: AppMessage?,
        hasDraftText: Bool,
        scheduleReplyEnabled: Bool,
        hasGroupShareTarget: Bool,
        cameraAvailable: Bool = true,
        privateActionBackendAvailability: AmenMessagingPrivateActionBackendAvailability = AmenMessagingPrivateActionBackendAvailability(
            saveMessageToNotes: true,
            createMessageReminder: true,
            createSelahReflectionFromMessage: true
        )
    ) -> [AmenMessagingAttachmentMenuItem] {
        let hasSelectedMessage = selectedMessage != nil
        let crossSurfaceEnabled = flags.messagingCrossSurfaceActionsEnabled
        var items: [AmenMessagingAttachmentMenuItem] = [
            .init(action: .camera, subtitle: nil, availability: cameraAvailable ? .enabled : .unavailable("Camera is not available on this device.")),
            .init(action: .photos, subtitle: nil, availability: .enabled),
            .init(action: .voice, subtitle: nil, availability: .enabled),
            .init(action: .files, subtitle: nil, availability: .enabled),
            .init(action: .poll, subtitle: nil, availability: .enabled),
            .init(action: .sendLater, subtitle: hasDraftText ? nil : "Write a message first", availability: scheduleReplyEnabled && hasDraftText ? .enabled : .unavailable("Write a message before scheduling.")),
            .init(action: .askBerean, subtitle: "Adds an @Berean prompt", availability: .enabled)
        ]

        guard flags.messagingAttachmentMenuSmartActionsEnabled else {
            return items
        }

        items.append(contentsOf: [
            .init(action: .stickers, subtitle: nil, availability: .unavailable("Sticker support is not available in Amen Messaging yet.")),
            .init(action: .saveToNotes, subtitle: nil, availability: privateActionAvailability(
                hasSelectedMessage: hasSelectedMessage,
                crossSurfaceEnabled: crossSurfaceEnabled,
                backendAvailable: privateActionBackendAvailability.saveMessageToNotes,
                backendUnavailableReason: "Private Notes saving is not deployed yet."
            )),
            .init(action: .saveToSelah, subtitle: nil, availability: flags.messagingCrossSurfaceActionsEnabled && flags.selahMediaOSEnabled && selectedMessage != nil ? .enabled : .unavailable(selectedMessage == nil ? "Select a message first." : "Selah saves are off for messaging.")),
            .init(action: .addToChurchNotes, subtitle: nil, availability: flags.messagingCrossSurfaceActionsEnabled && selectedMessage != nil ? .enabled : .unavailable(selectedMessage == nil ? "Select a message first." : "Church Notes saves are off for messaging.")),
            .init(action: .prayerRequest, subtitle: nil, availability: .unavailable("Prayer request review is not wired for this chat yet.")),
            .init(action: .shareWithGroup, subtitle: nil, availability: hasGroupShareTarget ? .enabled : .unavailable("No group share target is selected.")),
            .init(action: .startReflection, subtitle: nil, availability: privateActionAvailability(
                hasSelectedMessage: hasSelectedMessage,
                crossSurfaceEnabled: crossSurfaceEnabled,
                backendAvailable: privateActionBackendAvailability.createSelahReflectionFromMessage,
                backendUnavailableReason: "Selah reflection handoff is not deployed yet."
            )),
            .init(action: .createReminder, subtitle: nil, availability: privateActionAvailability(
                hasSelectedMessage: hasSelectedMessage,
                crossSurfaceEnabled: crossSurfaceEnabled,
                backendAvailable: privateActionBackendAvailability.createMessageReminder,
                backendUnavailableReason: "Message reminders are not deployed yet."
            )),
            .init(action: .shareSafely, subtitle: nil, availability: .unavailable("Share safety review is not wired for the attachment menu yet."))
        ])

        return items
    }

    private static func privateActionAvailability(
        hasSelectedMessage: Bool,
        crossSurfaceEnabled: Bool,
        backendAvailable: Bool,
        backendUnavailableReason: String
    ) -> AmenMessagingAttachmentAvailability {
        guard hasSelectedMessage else { return .unavailable("Select a message first.") }
        guard crossSurfaceEnabled else { return .unavailable("Cross-surface actions are off for messaging.") }
        guard backendAvailable else { return .unavailable(backendUnavailableReason) }
        return .enabled
    }
}

struct AmenAttachmentMenu: View {
    let items: [AmenMessagingAttachmentMenuItem]
    let onSelect: (AmenMessagingAttachmentAction) -> Void
    let onUnavailable: (AmenMessagingAttachmentMenuItem) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onDismiss) {
                Color.black.opacity(reduceTransparency ? 0.18 : 0.08)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        AmenAttachmentMenuRow(item: item) {
                            if item.availability.isEnabled {
                                onSelect(item.action)
                            } else {
                                onUnavailable(item)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 430)
            .background(menuBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(accessibilityContrast == .increased ? 0.28 : 0.12), lineWidth: accessibilityContrast == .increased ? 1.4 : 0.8)
            )
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 70)
            .offset(y: max(dragOffset, 0))
            .transition(Self.transition(reduceMotion: reduceMotion))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragOffset) { value, state, _ in
                        state = max(value.translation.height, 0)
                    }
                    .onEnded { value in
                        if value.translation.height > 48 { onDismiss() }
                    }
            )
        }
    }

    private var menuBackground: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.systemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    static func usesBloomAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        usesBloomAnimation(reduceMotion: reduceMotion)
            ? .scale(scale: 0.88, anchor: .bottomLeading).combined(with: .opacity)
            : .opacity.combined(with: .move(edge: .bottom))
    }
}

struct AmenAttachmentMenuRow: View {
    let item: AmenMessagingAttachmentMenuItem
    let onTap: () -> Void

    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: item.action.systemImage)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(item.availability.isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.secondarySystemBackground)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.action.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(item.availability.isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if let subtitle = item.subtitle ?? item.availability.reason {
                        Text(subtitle)
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 54)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(item.availability.isEnabled ? 0.72 : 0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(accessibilityContrast == .increased ? 0.18 : 0.07), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.availability.isEnabled ? item.action.title : "\(item.action.title), unavailable")
        .accessibilityHint(item.availability.reason ?? "Opens \(item.action.title)")
    }
}
