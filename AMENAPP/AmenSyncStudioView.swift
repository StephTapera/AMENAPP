// AmenSyncStudioView.swift
// AMEN Sync — Studio + Review + Publish
// White Liquid Glass. Full creation → distribution flow.

import SwiftUI
import PhotosUI

// MARK: - Main Studio View

struct AmenSyncStudioView: View {
    @ObservedObject var vm: AmenSyncViewModel
    let intent: SyncIntent
    @Environment(\.dismiss) private var dismiss

    @State private var activeTab: SyncStudioTab = .compose
    @State private var showPlatformPicker = false
    @State private var showCaptionAI = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    studioHeader

                    Divider()

                    // Tab bar
                    syncTabBar

                    Divider()

                    // Content
                    TabView(selection: $activeTab) {
                        composeTab
                            .tag(SyncStudioTab.compose)

                        platformsTab
                            .tag(SyncStudioTab.platforms)

                        captionsTab
                            .tag(SyncStudioTab.captions)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(Motion.adaptive(.easeInOut(duration: 0.25)), value: activeTab)
                }

                // Floating bottom action
                VStack {
                    Spacer()
                    syncBottomAction
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showModerationSheet) {
            SyncModerationSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $vm.showReviewScreen) {
            AmenSyncReviewView(vm: vm)
        }
        .sheet(isPresented: $showPlatformPicker) {
            SyncPlatformPickerSheet(selectedDestinations: $vm.selectedDestinations) {
                showPlatformPicker = false
            }
        }
        .onDisappear { vm.cleanup() }
        .task { vm.selectedDestinations = Set(SyncPlatform.allCases.filter { $0.canAutoPublish }) }
    }

    // MARK: - Header

    private var studioHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                    )
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                Image(systemName: intent.icon)
                    .font(.systemScaled(14))
                    .foregroundStyle(intent.color)
                Text(intent.displayName)
                    .font(.custom("OpenSans-Bold", size: 17))
            }

            Spacer()

            // Destination count badge
            Button {
                withAnimation {
                    activeTab = .platforms
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.systemScaled(12))
                    Text("\(vm.selectedPlatformCount) platforms")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                }
                .foregroundStyle(.teal)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.teal.opacity(0.1))
                        .overlay(Capsule().strokeBorder(Color.teal.opacity(0.25), lineWidth: 1))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Tab Bar

    private var syncTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SyncStudioTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.systemScaled(15))
                        Text(tab.label)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                    }
                    .foregroundStyle(activeTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if activeTab == tab {
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compose Tab

    private var composeTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Media grid
                syncAssetSection

                Divider()

                // Title + Caption
                captionSection

                Divider()

                // Scripture
                scriptureSection

                Divider()

                // Tags
                tagsSection

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var syncAssetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Media (\(vm.assets.count))")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()

                PhotosPicker(
                    selection: $vm.selectedPhotosItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos])
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.systemScaled(13, weight: .bold))
                        Text("Add")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                    )
                }
            }

            if vm.isUploading {
                VStack(spacing: 6) {
                    ProgressView(value: vm.uploadProgress)
                        .progressViewStyle(.linear)
                        .tint(.teal)
                    Text("Uploading... \(Int(vm.uploadProgress * 100))%")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if vm.assets.isEmpty {
                HStack(spacing: 16) {
                    ForEach(["photo.fill", "video.fill", "camera.fill"], id: \.self) { icon in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.07))
                            Image(systemName: icon)
                                .font(.systemScaled(20))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 80)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.assets) { asset in
                            SyncAssetThumbnail(asset: asset) {
                                vm.removeAsset(asset)
                            }
                        }
                    }
                }
            }
        }
    }

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Caption")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()
                Button {
                    vm.generateCaptionSuggestions()
                    showCaptionAI = true
                } label: {
                    HStack(spacing: 5) {
                        if vm.isGeneratingCaptions {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.systemScaled(12))
                        }
                        Text("AI Suggestions")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.teal.opacity(0.08))
                            .overlay(Capsule().strokeBorder(Color.teal.opacity(0.2), lineWidth: 1))
                    )
                }
            }

            TextEditor(text: $vm.caption)
                .font(.custom("OpenSans-Regular", size: 14))
                .frame(minHeight: 100)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                )

            // Caption length indicators per platform
            if !vm.caption.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(vm.selectedDestinations).sorted(by: { $0.displayName < $1.displayName })) { platform in
                            CaptionLengthChip(
                                platform: platform,
                                captionLength: vm.caption.count
                            )
                        }
                    }
                }
            }

            // AI suggestions
            if !vm.captionSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)

                    ForEach(vm.captionSuggestions.prefix(3)) { s in
                        Button {
                            vm.caption = s.text
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.teal)
                                Text(s.text)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.teal.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                Text("Scripture (optional)")
                    .font(.custom("OpenSans-Bold", size: 15))
            }
            TextField("e.g. Philippians 4:13", text: $vm.scriptureRef)
                .font(.custom("OpenSans-Regular", size: 14))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                )
        }
    }

    @State private var tagInput = ""

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.custom("OpenSans-Bold", size: 15))

            if !vm.tags.isEmpty {
                FlowLayout(items: vm.tags) { tag in
                    HStack(spacing: 5) {
                        Text("#\(tag)")
                            .font(.custom("OpenSans-Regular", size: 12))
                        Button {
                            vm.tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.systemScaled(9, weight: .bold))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }

            HStack(spacing: 10) {
                TextField("Add tag", text: $tagInput)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.07))
                    )
                    .submitLabel(.done)
                    .onSubmit {
                        let clean = tagInput
                            .lowercased()
                            .replacingOccurrences(of: "#", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty && !vm.tags.contains(clean) {
                            vm.tags.append(clean)
                        }
                        tagInput = ""
                    }
            }
        }
    }

    // MARK: - Platforms Tab

    private var platformsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Distribution Destinations")
                        .font(.custom("OpenSans-Bold", size: 18))
                    Text("AMEN Sync automatically adapts your content — size, crop, caption, and format — for each selected destination.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(.top, 16)

                ForEach(SyncPlatform.allCases) { platform in
                    SyncPlatformToggleRow(
                        platform: platform,
                        isSelected: vm.selectedDestinations.contains(platform)
                    ) {
                        vm.togglePlatform(platform)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Captions Tab

    private var captionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-Platform Captions")
                        .font(.custom("OpenSans-Bold", size: 18))
                    Text("Each platform gets an optimized caption. Edit any of them individually.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(.top, 16)

                if vm.variants.isEmpty {
                    CreationEmptyState(
                        icon: "text.bubble.fill",
                        title: "No Variants Yet",
                        message: "Tap 'Prepare Everywhere' to generate platform-specific captions.",
                        actionLabel: nil, action: nil
                    )
                } else {
                    ForEach(vm.variants.indices, id: \.self) { i in
                        VariantCaptionRow(
                            variant: $vm.variants[i],
                            onSave: { newCaption in
                                vm.updateVariantCaption(vm.variants[i].id, caption: newCaption)
                            }
                        )
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Bottom Action

    private var syncBottomAction: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 12) {
                if vm.isPreparing {
                    HStack(spacing: 12) {
                        ProgressView().scaleEffect(0.85)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preparing versions...")
                                .font(.custom("OpenSans-Bold", size: 14))
                            Text("Fitting content for \(vm.selectedPlatformCount) platforms")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                } else if vm.projectState == .ready || vm.projectState == .published {
                    Button {
                        vm.showReviewScreen = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.systemScaled(16))
                            Text("Review & Publish")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black)
                        )
                    }
                    .padding(.horizontal, 20)
                } else {
                    Button {
                        Task { await vm.startPrepare() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.systemScaled(16))
                            Text("Prepare Everywhere")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(vm.canPrepare ? Color.black : Color.gray.opacity(0.3))
                        )
                    }
                    .disabled(!vm.canPrepare)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }
}

// MARK: - Studio Tab Enum

enum SyncStudioTab: String, CaseIterable {
    case compose   = "Compose"
    case platforms = "Platforms"
    case captions  = "Captions"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .compose:   return "pencil"
        case .platforms: return "arrow.triangle.2.circlepath"
        case .captions:  return "text.bubble"
        }
    }
}

// MARK: - Caption Length Chip

struct CaptionLengthChip: View {
    let platform: SyncPlatform
    let captionLength: Int

    var isTooLong: Bool { captionLength > platform.maxCaptionLength }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: platform.icon)
                .font(.systemScaled(10))
            Text("\(captionLength)/\(platform.maxCaptionLength)")
                .font(.custom("OpenSans-SemiBold", size: 10))
        }
        .foregroundStyle(isTooLong ? .red : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isTooLong ? Color.red.opacity(0.08) : Color.gray.opacity(0.08))
        )
    }
}

// MARK: - Platform Toggle Row

struct SyncPlatformToggleRow: View {
    let platform: SyncPlatform
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(platform.iconColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: platform.icon)
                        .font(.systemScaled(18))
                        .foregroundStyle(platform.iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.displayName)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                    Text("\(platform.targetPixelWidth)px · \(aspectRatioLabel(platform.targetAspectRatio))")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(22))
                    .foregroundStyle(isSelected ? .teal : Color.secondary.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.teal.opacity(0.04) : Color.gray.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.teal.opacity(0.2) : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)), value: isSelected)
    }

    private func aspectRatioLabel(_ ratio: CGFloat) -> String {
        if abs(ratio - 1.0) < 0.01 { return "1:1" }
        if abs(ratio - 9.0/16.0) < 0.01 { return "9:16" }
        if abs(ratio - 16.0/9.0) < 0.01 { return "16:9" }
        if abs(ratio - 4.0/5.0) < 0.01 { return "4:5" }
        return "Custom"
    }
}

// MARK: - Variant Caption Row

struct VariantCaptionRow: View {
    @Binding var variant: AmenSyncVariant
    let onSave: (String) -> Void

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: variant.platform.icon)
                    .font(.systemScaled(14))
                    .foregroundStyle(variant.platform.iconColor)
                Text(variant.platform.displayName)
                    .font(.custom("OpenSans-Bold", size: 14))
                Spacer()
                Button {
                    draft = variant.caption
                    editing = true
                } label: {
                    Text("Edit")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(variant.caption)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .lineSpacing(2)

            // AI badge
            if variant.aiCaption {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.systemScaled(10))
                    Text("AI-generated · Tap Edit to modify")
                        .font(.custom("OpenSans-Regular", size: 11))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
        .sheet(isPresented: $editing) {
            CaptionEditSheet(
                initialText: draft,
                segmentKind: .mainClip
            ) { updated in
                variant.caption = updated
                onSave(updated)
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Sync Asset Thumbnail

struct SyncAssetThumbnail: View {
    let asset: AmenSyncProjectAsset
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let urlStr = asset.remoteURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    }
                } else {
                    Color.gray.opacity(0.1)
                    Image(systemName: asset.type == .video ? "video.fill" : "photo.fill")
                        .font(.systemScaled(22))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(18))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .padding(4)
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout<T: Hashable, Content: View>: View {
    let items: [T]
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        // Simple wrapping layout using conditional stacks
        VStack(alignment: .leading, spacing: 8) {
            let rows = makeRows()
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(rows[i], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }

    private func makeRows() -> [[T]] {
        var rows: [[T]] = [[]]
        for item in items {
            rows[rows.count - 1].append(item)
            if rows[rows.count - 1].count >= 4 {
                rows.append([])
            }
        }
        return rows.filter { !$0.isEmpty }
    }
}

// MARK: - Moderation Sheet

struct SyncModerationSheet: View {
    @ObservedObject var vm: AmenSyncViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.systemScaled(36))
                        .foregroundStyle(.orange)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Content Review")
                        .font(.custom("OpenSans-Bold", size: 22))
                    Text("Our AI flagged something in your content. Review the suggestions below before publishing.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                GlassCreationButton(label: "Review My Content", icon: "pencil") {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Platform Picker Sheet

struct SyncPlatformPickerSheet: View {
    @Binding var selectedDestinations: Set<SyncPlatform>
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SyncPlatform.allCases) { platform in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if selectedDestinations.contains(platform) {
                            selectedDestinations.remove(platform)
                        } else {
                            selectedDestinations.insert(platform)
                            NotificationCenter.default.post(
                                name: Notification.Name("amenSelectSyncPlatform"),
                                object: nil,
                                userInfo: ["platform": platform.displayName]
                            )
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(platform.iconColor.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: platform.icon)
                                    .font(.systemScaled(16))
                                    .foregroundStyle(platform.iconColor)
                            }
                            Text(platform.displayName)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedDestinations.contains(platform) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(20))
                                    .foregroundStyle(.teal)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Platforms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss(); dismiss() }
                        .font(.custom("OpenSans-Bold", size: 15))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
