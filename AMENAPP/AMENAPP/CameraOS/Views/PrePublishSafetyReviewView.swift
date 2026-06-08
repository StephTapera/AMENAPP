// PrePublishSafetyReviewView.swift
// AMENAPP — Camera OS
// Pre-publish safety scan results. Shows detected items, risk level, redaction options.
// Tone: "Here's the safest way to post this" — never "You can't post this."
// Severe/Critical: block publish until resolved or user acknowledges risk.
//
// Design: Liquid Glass on dark/black camera context.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
//   iOS 26+:    .amenGlassEffect() on controls

import SwiftUI
import AVKit

// MARK: - PrePublishSafetyReviewView

struct PrePublishSafetyReviewView: View {

    // MARK: Props

    let intent: CameraIntent
    let attachment: WitnessDraftAttachment
    var scanResult: CameraPrePublishScanResult
    let onApprove: (WitnessDraftAttachment, CameraPrePublishScanResult) -> Void
    let onCancel: () -> Void

    // MARK: State

    @State private var localScanResult: CameraPrePublishScanResult
    @State private var isRedacting = false
    @State private var showLocationDelayPicker = false
    @State private var locationDelay: CameraLocationDelayOption = .none
    @State private var selectedAudience: CameraAudiencePreset
    @State private var showAudienceSelector = false
    @State private var showRedactedConfirmation = false

    // MARK: Constants

    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    // MARK: Init

    init(
        intent: CameraIntent,
        attachment: WitnessDraftAttachment,
        scanResult: CameraPrePublishScanResult,
        onApprove: @escaping (WitnessDraftAttachment, CameraPrePublishScanResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.intent = intent
        self.attachment = attachment
        self.scanResult = scanResult
        self.onApprove = onApprove
        self.onCancel = onCancel
        _localScanResult = State(initialValue: scanResult)
        _selectedAudience = State(initialValue: scanResult.recommendedAudience ?? .friends)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.94).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    mediaPreviewSection
                    riskLevelBanner
                    if !localScanResult.detectedItems.isEmpty {
                        detectedItemsSection
                    }
                    if localScanResult.hasAutoRedactableItems {
                        removeInfoButton
                    }
                    audienceSelectorSection
                    if localScanResult.sceneType == .church || localScanResult.sceneType == .home {
                        locationDelaySection
                    }
                    if localScanResult.riskLevel >= .medium {
                        pauseAndReflectCard
                    }
                    // Bottom padding to clear the action bar
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            bottomActionBar
        }
        .sheet(isPresented: $showAudienceSelector) {
            AudienceSafetySimulatorView(
                detectedItems: localScanResult.detectedItems,
                currentAudience: selectedAudience,
                onAudienceSelected: { selectedAudience = $0 },
                onDismiss: { showAudienceSelector = false }
            )
        }
        .overlay(alignment: .top) {
            if showRedactedConfirmation {
                redactedConfirmationToast
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 16)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75),
            value: showRedactedConfirmation
        )
    }

    // MARK: - Media Preview

    @ViewBuilder
    private var mediaPreviewSection: some View {
        ZStack(alignment: .bottomLeading) {
            if attachment.isVideo, let fileURL = attachment.finalFileURL {
                VideoPlayer(player: AVPlayer(url: fileURL))
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                let uiImage: UIImage = {
                    if let path = attachment.finalFileURL?.path {
                        return UIImage(contentsOfFile: path) ?? UIImage()
                    }
                    return UIImage()
                }()
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Intent badge — bottom-left overlay
            intentBadge
                .padding(10)
        }
        .frame(maxWidth: .infinity)
    }

    private var intentBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: intent.systemIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Text(intent.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(intentBadgeBackground)
        .accessibilityLabel("Intent: \(intent.displayName)")
    }

    @ViewBuilder
    private var intentBadgeBackground: some View {
        if #available(iOS 26, *) {
            Capsule().amenGlassEffect()
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Risk Level Banner

    private var riskLevelBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: riskIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(riskColor)

            Text(bannerMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(riskBannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(localScanResult.riskLevel.displayName) risk level. \(bannerMessage)")
    }

    @ViewBuilder
    private var riskBannerBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .amenGlassEffect()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(riskColor.opacity(0.45), lineWidth: 0.8)
            }
        }
    }

    private var riskIcon: String {
        switch localScanResult.riskLevel {
        case .low:      return "checkmark.shield.fill"
        case .medium:   return "exclamationmark.triangle.fill"
        case .high:     return "shield.fill"
        case .severe:   return "lock.fill"
        case .critical: return "lock.fill"
        }
    }

    private var riskColor: Color {
        switch localScanResult.riskLevel {
        case .low:      return Color.green
        case .medium:   return amberGold
        case .high:     return Color.orange
        case .severe:   return Color.red
        case .critical: return Color(red: 0.7, green: 0.0, blue: 0.0)
        }
    }

    private var bannerMessage: String {
        if let nudge = localScanResult.nudgeMessage, !nudge.isEmpty {
            return nudge
        }
        switch localScanResult.riskLevel {
        case .low:      return "Looks good! Ready to post."
        case .medium:   return "A few things to consider before posting."
        case .high:     return "Review before posting — sensitive content detected."
        case .severe:   return "This post requires review before it can go public."
        case .critical: return "This post requires review before it can go public."
        }
    }

    // MARK: - Detected Items Section

    private var detectedItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected Items")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(localScanResult.detectedItems, id: \.rawValue) { item in
                        detectedItemChip(item)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detectedItemChip(_ item: CameraSensitiveItemType) -> some View {
        let suggestion = localScanResult.redactionSuggestions.first(where: { $0.itemType == item })
        let canAutoRedact = item.autoRedactable
        let isAlreadyRedacted = suggestion?.isRedacted ?? false

        HStack(spacing: 6) {
            Image(systemName: sensitiveItemIcon(item))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAlreadyRedacted ? .white.opacity(0.5) : .white)

            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAlreadyRedacted ? .white.opacity(0.5) : .white)
                .strikethrough(isAlreadyRedacted, color: .white.opacity(0.5))

            if canAutoRedact && !isAlreadyRedacted {
                Button {
                    redactSingleItem(item)
                } label: {
                    Text("Auto-remove")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(amberGold, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Auto-remove \(item.displayName)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(detectedItemChipBackground(isRedacted: isAlreadyRedacted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isAlreadyRedacted
                ? "\(item.displayName), removed"
                : canAutoRedact
                    ? "\(item.displayName), auto-remove available"
                    : item.displayName
        )
    }

    @ViewBuilder
    private func detectedItemChipBackground(isRedacted: Bool) -> some View {
        if #available(iOS 26, *) {
            Capsule().amenGlassEffect()
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(.white.opacity(isRedacted ? 0.10 : 0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Remove Sensitive Info Button

    private var removeInfoButton: some View {
        Button {
            redactAllAutoRedactable()
        } label: {
            HStack(spacing: 8) {
                if isRedacting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.black)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isRedacting ? "Removing…" : "Remove Sensitive Information")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isRedacting ? amberGold.opacity(0.6) : amberGold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isRedacting)
        .buttonStyle(.plain)
        .accessibilityLabel("Remove all automatically removable sensitive information")
        .accessibilityHint("Blurs identified sensitive regions in your media")
    }

    // MARK: - Audience Selector

    private var audienceSelectorSection: some View {
        Button {
            showAudienceSelector = true
        } label: {
            HStack(spacing: 10) {
                Text("Who can see this?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: selectedAudience.systemIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(amberGold)
                    Text(selectedAudience.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(audiencePillBackground)
            }
            .padding(14)
            .background(audienceSectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audience: \(selectedAudience.displayName). Tap to change.")
        .accessibilityHint("Opens audience privacy simulator")
    }

    @ViewBuilder
    private var audiencePillBackground: some View {
        if #available(iOS 26, *) {
            Capsule().amenGlassEffect()
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    private var audienceSectionBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).amenGlassEffect()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Location Delay Section

    @ViewBuilder
    private var locationDelaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Share after you leave?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                Toggle("", isOn: $showLocationDelayPicker)
                    .labelsHidden()
                    .tint(amberGold)
                    .accessibilityLabel("Delay location sharing until after you leave")
            }

            if showLocationDelayPicker {
                LocationDelayPickerView(selectedDelay: $locationDelay)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(locationDelayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75),
            value: showLocationDelayPicker
        )
    }

    @ViewBuilder
    private var locationDelayBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).amenGlassEffect()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Pause & Reflect Card

    private var pauseAndReflectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(amberGold)
                Text("Take a moment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Would you still want this visible in 5 years?")
                .font(.system(size: 13, weight: .regular).italic())
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(reflectCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Take a moment. Would you still want this visible in 5 years?")
    }

    @ViewBuilder
    private var reflectCardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .amenGlassEffect()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(amberGold.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            if localScanResult.blocksPublish {
                // Blocked: Get Help + Cancel only
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let url = URL(string: "https://amenapp.com/help/content-safety") {
                        openURL(url)
                    }
                } label: {
                    Text("Get Help")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(amberGold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(getHelpButtonBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Get help with this content")

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(cancelButtonBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and go back")

            } else {
                // Normal: Post + Cancel
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 100)
                        .frame(height: 52)
                        .background(cancelButtonBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and go back")

                Button {
                    onApprove(attachment, localScanResult)
                } label: {
                    Text("Post")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(amberGold, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Post this content")
                .accessibilityHint("Approves the scan result and submits the post")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .padding(.top, 12)
        .background(actionBarBackground)
    }

    @ViewBuilder
    private var getHelpButtonBackground: some View {
        if #available(iOS 26, *) {
            Capsule().amenGlassEffect()
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(amberGold.opacity(0.55), lineWidth: 1.2)
            }
        }
    }

    @ViewBuilder
    private var cancelButtonBackground: some View {
        if #available(iOS 26, *) {
            Capsule().amenGlassEffect()
        } else {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    private var actionBarBackground: some View {
        if #available(iOS 26, *) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.black.opacity(0.35)))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Redacted Confirmation Toast

    private var redactedConfirmationToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
            Text("Sensitive information removed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(amberGold, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .accessibilityLabel("Sensitive information removed")
    }

    // MARK: - Redaction Logic

    private func redactAllAutoRedactable() {
        guard !isRedacting else { return }
        isRedacting = true

        Task {
            // Mark all auto-redactable suggestions as redacted
            var updatedSuggestions = localScanResult.redactionSuggestions
            for i in updatedSuggestions.indices where updatedSuggestions[i].autoRedactable {
                updatedSuggestions[i].isRedacted = true
            }
            localScanResult = CameraPrePublishScanResult(
                riskLevel: localScanResult.riskLevel,
                detectedItems: localScanResult.detectedItems,
                redactionSuggestions: updatedSuggestions,
                safetyProfile: localScanResult.safetyProfile,
                requiresHumanReview: localScanResult.requiresHumanReview,
                blocksPublish: localScanResult.blocksPublish,
                nudgeMessage: localScanResult.nudgeMessage,
                recommendedAudience: localScanResult.recommendedAudience,
                sceneType: localScanResult.sceneType,
                containsMinor: localScanResult.containsMinor
            )
            isRedacting = false
            showRedactedConfirmation = true
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showRedactedConfirmation = false
        }
    }

    private func redactSingleItem(_ item: CameraSensitiveItemType) {
        var updatedSuggestions = localScanResult.redactionSuggestions
        for i in updatedSuggestions.indices where updatedSuggestions[i].itemType == item {
            updatedSuggestions[i].isRedacted = true
        }
        localScanResult = CameraPrePublishScanResult(
            riskLevel: localScanResult.riskLevel,
            detectedItems: localScanResult.detectedItems,
            redactionSuggestions: updatedSuggestions,
            safetyProfile: localScanResult.safetyProfile,
            requiresHumanReview: localScanResult.requiresHumanReview,
            blocksPublish: localScanResult.blocksPublish,
            nudgeMessage: localScanResult.nudgeMessage,
            recommendedAudience: localScanResult.recommendedAudience,
            sceneType: localScanResult.sceneType,
            containsMinor: localScanResult.containsMinor
        )
    }

    // MARK: - SF Symbol mapping

    private func sensitiveItemIcon(_ item: CameraSensitiveItemType) -> String {
        switch item {
        case .minorFace:      return "person.fill.badge.minus"
        case .adultFace:      return "person.fill"
        case .homeAddress:    return "house.fill"
        case .streetSign:     return "signpost.right.fill"
        case .schoolSign:     return "building.columns.fill"
        case .schoolUniform:  return "figure.child"
        case .busStop:        return "bus.fill"
        case .licensePlate:   return "car.fill"
        case .idDocument:     return "creditcard.fill"
        case .badge:          return "person.crop.rectangle.badge.plus"
        case .medicalRecord:  return "cross.case.fill"
        case .screenContent:  return "display"
        case .phoneNumber:    return "phone.fill"
        }
    }
}

// MARK: - CameraAudiencePreset convenience description

private extension CameraAudiencePreset {
    var audienceDescription: String {
        switch self {
        case .public:     return "Publicly visible to all AMEN users"
        case .friends:    return "Visible to your confirmed connections"
        case .family:     return "Visible to your linked family members"
        case .church:     return "Visible to your church community"
        case .smallGroup: return "Visible to your small group only"
        case .orgMembers: return "Visible to your organization members"
        case .privateOnly: return "Only visible to you — not shared"
        }
    }
}

// MARK: - CameraContextRiskLevel display helper

private extension CameraContextRiskLevel {
    var displayName: String {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .severe:   return "Severe"
        case .critical: return "Critical"
        }
    }
}
