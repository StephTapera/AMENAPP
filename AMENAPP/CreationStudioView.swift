// CreationStudioView.swift
// AMEN Creator — Main Creation Studio
// White background, Liquid Glass, AI-assisted editing

import SwiftUI
import PhotosUI

// MARK: - Creation Studio Entry

struct CreationStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SceneBuilderViewModel()

    // Entry parameters
    var initialTemplate: CreationTemplate?
    var draftId: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    CreationStudioHeader(
                        title: vm.selectedTemplate?.name ?? "New Creation",
                        subtitle: headerSubtitle,
                        onBack: { dismiss() },
                        trailingAction: vm.canPublish ? { vm.showPublishView = true } : nil,
                        trailingLabel: vm.canPublish ? "Publish" : nil
                    )

                    Divider()

                    // State-driven main content
                    ZStack {
                        switch vm.studioState {
                        case .idle:
                            idleContent
                        case .selectingTemplate:
                            idleContent
                        case .generatingPlan, .refining:
                            generatingContent
                        case .editingTimeline, .safetyReview, .previewing:
                            editorContent
                        case .published:
                            publishedContent
                        case .error(let msg):
                            errorContent(msg)
                        default:
                            editorContent
                        }
                    }
                    .animation(Motion.adaptive(.easeInOut(duration: 0.3)), value: vm.studioState)
                }

                // Floating refinement bar — only in editing state
                if case .editingTimeline = vm.studioState {
                    VStack(spacing: 0) {
                        Spacer()
                        CreationPromptBar(vm: vm)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $vm.showTemplateSheet) {
            TemplatePickerView(vm: vm)
        }
        .sheet(isPresented: $vm.showPublishView) {
            CreationPublishView(vm: vm)
        }
        .sheet(isPresented: $vm.showSafetySheet) {
            CreationSafetySheet(vm: vm)
        }
        .task {
            // Load initial state
            if let id = draftId { await vm.loadDraft(id) }
            if let t = initialTemplate { vm.selectedTemplate = t }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Header Subtitle

    private var headerSubtitle: String? {
        switch vm.studioState {
        case .generatingPlan: return "Building your plan..."
        case .refining:       return "Applying refinement..."
        case .safetyReview:   return "Checking content..."
        case .editingTimeline:
            return "\(vm.timelineSegments.count) segments · \(Int(vm.totalDuration))s"
        default: return nil
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Media section
                AssetGridView(vm: vm)
                    .padding(.top, 20)

                Divider().padding(.horizontal, 20)

                // Template section
                templateSection

                Divider().padding(.horizontal, 20)

                // Scripture input
                scriptureSection

                Divider().padding(.horizontal, 20)

                // Generate CTA
                generateSection

                Spacer(minLength: 100)
            }
        }
    }

    // MARK: - Template Section

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Template")
                    .font(.custom("OpenSans-Bold", size: 15))
                Spacer()
                Button("Browse All") {
                    vm.showTemplateSheet = true
                }
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            if let template = vm.selectedTemplate {
                // Selected template card
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(template.category.color.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: template.iconName)
                            .font(.systemScaled(22))
                            .foregroundStyle(template.category.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                            .font(.custom("OpenSans-Bold", size: 15))
                        Text(template.description)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        vm.selectedTemplate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(20))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
            } else {
                // Quick template row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CreationTemplate.systemTemplates.prefix(4)) { template in
                            QuickTemplateChip(template: template) {
                                vm.applyTemplate(template)
                            }
                        }

                        Button {
                            vm.showTemplateSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("More")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(11, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Scripture Section

    @State private var scriptureInput = ""

    private var scriptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                Text("Scripture (optional)")
                    .font(.custom("OpenSans-Bold", size: 15))
            }
            .padding(.horizontal, 20)

            TextField("e.g. Philippians 4:13", text: $scriptureInput)
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
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        VStack(spacing: 16) {
            if vm.selectedAssets.isEmpty && vm.selectedTemplate == nil {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(28))
                        .foregroundStyle(.secondary)
                    Text("Add media or choose a template to begin")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            } else {
                GlassCreationButton(
                    label: "Generate Scene Plan",
                    icon: "sparkles",
                    style: .primary
                ) {
                    vm.generatePlan()
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Generating Content

    private var generatingContent: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.04))
                            .frame(width: 80 + CGFloat(i * 20), height: 80 + CGFloat(i * 20))
                            .scaleEffect(generatingScale(index: i))
                            .animation(
                                .easeInOut(duration: 1.2)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                value: isGenerating
                            )
                    }

                    Image(systemName: "sparkles")
                        .font(.systemScaled(32))
                        .foregroundStyle(.primary)
                }
                .frame(height: 130)
                .onAppear { isGenerating = true }

                VStack(spacing: 8) {
                    Text(vm.isRefining ? "Applying refinement..." : "Building your scene plan")
                        .font(.custom("OpenSans-Bold", size: 20))

                    Text(vm.isRefining
                         ? "Adjusting segments to match your request"
                         : "Analyzing your media and creating a structured timeline"
                    )
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @State private var isGenerating = false

    private func generatingScale(index: Int) -> CGFloat {
        isGenerating ? 1.0 + CGFloat(index) * 0.05 : 1.0
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        VStack(spacing: 0) {
            // Tab bar
            editorTabBar

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    switch vm.activeTab {
                    case .timeline:
                        VStack(spacing: 20) {
                            // Safety banner
                            CreationSafetyBanner(status: vm.safetyStatus)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                            // Scene plan summary
                            if let plan = vm.scenePlan {
                                scenePlanSummary(plan)
                            }

                            // Refinement chips
                            refinementChipsRow

                            // Timeline
                            CreationTimelineView(vm: vm)
                                .padding(.top, 4)

                            Spacer(minLength: 120)
                        }

                    case .captions:
                        captionsTab

                    case .overlays:
                        overlaysTab

                    case .music:
                        musicTab
                    }
                }
            }
        }
    }

    private var editorTabBar: some View {
        HStack(spacing: 0) {
            ForEach(CreationStudioTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.adaptive(.easeInOut(duration: 0.2))) {
                        vm.activeTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.systemScaled(16))
                        Text(tab.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                    }
                    .foregroundStyle(vm.activeTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if vm.activeTab == tab {
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 2)
                                .matchedGeometryEffect(
                                    id: "tabIndicator",
                                    in: editorTabNS
                                )
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    @Namespace private var editorTabNS

    private func scenePlanSummary(_ plan: ScenePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = plan.titleSuggestion {
                        Text(title)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        ToneBadge(tone: plan.tone)
                        DurationBadge(seconds: plan.targetDuration)
                    }
                }
                Spacer()

                // Re-generate button
                Button {
                    vm.generatePlan()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.systemScaled(12))
                        Text("Regenerate")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    private var refinementChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CreationRefinementChip.suggestions.prefix(6)) { chip in
                    CreationRefinementChipView(chip: chip) {
                        vm.applyRefinementChip(chip)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private var captionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Captions")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if vm.timelineSegments.filter({ $0.captionText != nil }).isEmpty {
                CreationEmptyState(
                    icon: "text.bubble.fill",
                    title: "No Captions Yet",
                    message: "Captions will be suggested after your plan is generated. You can also edit each segment directly.",
                    actionLabel: nil, action: nil
                )
            } else {
                ForEach(vm.timelineSegments) { segment in
                    if let caption = segment.captionText {
                        CaptionRowItem(segment: segment, caption: caption) { updated in
                            vm.updateSegmentCaption(segment.id, caption: updated)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            Spacer(minLength: 120)
        }
    }

    private var overlaysTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text Overlays")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            ForEach(vm.timelineSegments.filter { $0.text != nil || $0.kind == .scriptureOverlay || $0.kind == .titleCard }) { segment in
                OverlayRowItem(segment: segment) { updated in
                    vm.updateSegmentOverlayText(segment.id, text: updated)
                }
                .padding(.horizontal, 20)
            }

            if vm.timelineSegments.filter({ $0.text != nil }).isEmpty {
                CreationEmptyState(
                    icon: "rectangle.on.rectangle.fill",
                    title: "No Overlays",
                    message: "Scripture, quote, and title overlays will appear here after your plan is generated.",
                    actionLabel: nil, action: nil
                )
            }

            Spacer(minLength: 120)
        }
    }

    private var musicTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Music")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if let suggestion = vm.scenePlan?.musicSuggestion {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 50, height: 50)
                            Image(systemName: "waveform")
                                .font(.systemScaled(22))
                                .foregroundStyle(.purple)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Suggested Mood: \(suggestion.mood.capitalized)")
                                .font(.custom("OpenSans-Bold", size: 15))
                            Text("Tempo: \(suggestion.tempo)")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(suggestion.usageNotes)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.05))
                )
                .padding(.horizontal, 20)
            } else {
                CreationEmptyState(
                    icon: "waveform",
                    title: "No Music Suggestion",
                    message: "Generate a scene plan to get a music mood suggestion for your content.",
                    actionLabel: nil, action: nil
                )
            }

            Spacer(minLength: 100)
        }
    }

    // MARK: - Published Content

    private var publishedContent: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(48))
                        .foregroundStyle(.green)
                }
                VStack(spacing: 8) {
                    Text("Published!")
                        .font(.custom("OpenSans-Bold", size: 24))
                    Text("Your creation is live on AMEN")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                }
            }

            GlassCreationButton(label: "Done", icon: nil, style: .primary) {
                dismiss()
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Error Content

    private func errorContent(_ message: String) -> some View {
        CreationEmptyState(
            icon: "exclamationmark.triangle.fill",
            title: "Something went wrong",
            message: message,
            actionLabel: "Try Again"
        ) {
            vm.generatePlan()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Caption Row

struct CaptionRowItem: View {
    let segment: CreationTimelineSegment
    let caption: String
    let onSave: (String) -> Void

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SegmentKindPill(kind: segment.kind)
                Spacer()
                Button { editing = true; draft = caption } label: {
                    Text("Edit")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(caption)
                .font(.custom("OpenSans-Regular", size: 13))
                .lineSpacing(2)
                .lineLimit(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
        .sheet(isPresented: $editing) {
            CaptionEditSheet(initialText: draft, segmentKind: segment.kind) { onSave($0) }
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Overlay Row

struct OverlayRowItem: View {
    let segment: CreationTimelineSegment
    let onSave: (String) -> Void

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SegmentKindPill(kind: segment.kind)
                Spacer()
                Button { editing = true; draft = segment.text ?? "" } label: {
                    Text("Edit")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(segment.text ?? "No overlay text")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(segment.text != nil ? .primary : .secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.05))
        )
        .sheet(isPresented: $editing) {
            CaptionEditSheet(initialText: draft, segmentKind: segment.kind) { onSave($0) }
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Quick Template Chip

struct QuickTemplateChip: View {
    let template: CreationTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                Image(systemName: template.iconName)
                    .font(.systemScaled(12))
                    .foregroundStyle(template.category.color)
                Text(template.name)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(template.category.color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
