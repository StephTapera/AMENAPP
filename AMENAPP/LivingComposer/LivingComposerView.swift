import SwiftUI
import PhotosUI

// The Living Composer — an adaptive, context-aware posting interface.
// The UI shifts based on environment, intent, and AI intelligence.
struct LivingComposerView: View {
    @StateObject private var vm = LivingComposerViewModel()
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Context bar — shows where/what the post is for
                contextBar

                Divider()

                ScrollView {
                    VStack(spacing: 16) {
                        // Safety flags (non-blocking)
                        if !vm.activeSafetyFlags.isEmpty {
                            safetyFlagBanner
                        }

                        // Media analysis result
                        if let analysis = vm.mediaAnalysis, analysis.detectedType != .general {
                            mediaAnalysisBanner(analysis)
                        }

                        // Main text area
                        textArea

                        // Attached images
                        if !vm.selectedImages.isEmpty {
                            imagePreviewStrip
                        }

                        // AI suggestions
                        if !vm.intelligenceResult.suggestions.isEmpty {
                            suggestionsRow
                        }

                        // Audience selector
                        audienceRouteSelector

                        Spacer(minLength: 80)
                    }
                    .padding()
                }

                // Bottom toolbar
                bottomToolbar
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $vm.showIntentPicker) { intentPickerSheet }
            .sheet(isPresented: $vm.showAudienceSelector) { audienceSelectorSheet }
            .sheet(isPresented: $vm.showAIAssist) {
                BereanChatView(
                    initialMode: .askBerean,
                    initialQuery: vm.draftText.isEmpty ? nil : "Help me refine this post: \(vm.draftText)"
                )
            }
            .onChange(of: vm.selectedPhotoItems) { vm.loadSelectedPhotos() }
            .onChange(of: vm.draftText) { vm.onDraftChanged(vm.draftText) }
            .onChange(of: vm.postSuccess) { _, success in if success { dismiss() } }
            .onAppear { vm.onAppear(); textFocused = true }
        }
    }

    // MARK: - Context Bar

    private var contextBar: some View {
        HStack(spacing: 10) {
            // Mode pill
            Menu {
                ForEach(ComposerMode.allCases, id: \.self) { mode in
                    Button {
                        vm.setMode(mode)
                    } label: {
                        Label(mode.displayName, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: vm.composerMode.systemImage)
                        .font(.caption.weight(.semibold))
                    Text(vm.composerMode.displayName)
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AmenTheme.Colors.amenGold.opacity(0.12), in: Capsule())
                .foregroundStyle(AmenTheme.Colors.amenGold)
            }

            // Context label
            if vm.currentContext != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(vm.currentContext.displayName)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Intent button
            Button {
                vm.showIntentPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: vm.selectedIntent.composerIcon)
                        .font(.caption)
                    Text(vm.selectedIntent.composerDisplayName)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Text Area

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if vm.draftText.isEmpty {
                Text(vm.isAnalyzing ? "Thinking..." : vm.uiHint.textPlaceholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .animation(.easeInOut(duration: 0.2), value: vm.isAnalyzing)
            }
            TextEditor(text: $vm.draftText)
                .focused($textFocused)
                .frame(minHeight: vm.composerMode == .reflective ? 140 : 100)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Image Preview Strip

    private var imagePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.selectedImages.indices, id: \.self) { idx in
                    Image(uiImage: vm.selectedImages[idx])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Safety Banner

    private var safetyFlagBanner: some View {
        VStack(spacing: 8) {
            ForEach(vm.activeSafetyFlags) { flag in
                HStack(spacing: 8) {
                    Image(systemName: flag.severity == .block ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(flag.severity == .block ? .red : .orange)
                    Text(flag.message)
                        .font(.caption)
                    Spacer()
                }
                .padding(10)
                .background((flag.severity == .block ? Color.red : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Media Analysis Banner

    private func mediaAnalysisBanner(_ analysis: MediaAnalysisResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected: \(analysis.detectedType.rawValue.capitalized.replacingOccurrences(of: "_", with: " "))")
                    .font(.caption.weight(.semibold))
                if let text = analysis.extractedText?.prefix(60) {
                    Text("\"\(text)\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Suggestions Row

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.intelligenceResult.suggestions.prefix(4)) { suggestion in
                    Button {
                        vm.applySuggestion(suggestion)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: suggestionIcon(suggestion.type))
                                .font(.caption2)
                            Text(suggestion.text.prefix(30))
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func suggestionIcon(_ type: SmartSuggestionType) -> String {
        switch type {
        case .captionAssist:   return "sparkles"
        case .eventTag:        return "tag"
        case .audienceHint:    return "person.2"
        case .ocrExtract:      return "text.viewfinder"
        case .recapCreate:     return "doc.text"
        case .privacyAlert:    return "lock.shield"
        case .safetyWarning:   return "exclamationmark.shield"
        case .scriptureRef:    return "book"
        }
    }

    // MARK: - Audience Route Selector

    private var audienceRouteSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Post to")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Edit") { vm.showAudienceSelector = true }
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SmartAudienceRouter.shared.availableRoutes.prefix(5)) { route in
                        Button {
                            SmartAudienceRouter.shared.toggleRoute(id: route.id)
                        } label: {
                            HStack(spacing: 4) {
                                if SmartAudienceRouter.shared.selectedRouteIds.contains(route.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AmenTheme.Colors.amenGold)
                                }
                                Text(route.label)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                SmartAudienceRouter.shared.selectedRouteIds.contains(route.id)
                                    ? AnyShapeStyle(AmenTheme.Colors.amenGold.opacity(0.15)) : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule()
                            )
                            .foregroundStyle(SmartAudienceRouter.shared.selectedRouteIds.contains(route.id) ? AmenTheme.Colors.amenGold : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                PhotosPicker(selection: $vm.selectedPhotoItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Button {
                    vm.showAIAssist = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(.purple)
                }

                if vm.uiHint.showEventTools {
                    Button {
                        // Open event tagging
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Char count hint
                if vm.draftText.count > 200 {
                    Text("\(500 - vm.draftText.count)")
                        .font(.caption2)
                        .foregroundStyle(vm.draftText.count > 450 ? .red : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar Buttons

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
                vm.reset()
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await vm.publish() }
            } label: {
                Text("Post")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(vm.canPost && !vm.hasBlockingFlag ? AmenTheme.Colors.amenGold : .secondary.opacity(0.3))
                    .foregroundStyle(vm.canPost && !vm.hasBlockingFlag ? AmenTheme.Colors.amenBlack : .secondary)
                    .clipShape(Capsule())
            }
            .disabled(!vm.canPost || vm.hasBlockingFlag)
        }
    }

    // MARK: - Intent Picker Sheet

    private var intentPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(PostIntent.allCases, id: \.rawValue) { intent in
                    Button {
                        vm.setIntent(intent)
                    } label: {
                        HStack {
                            Image(systemName: intent.composerIcon)
                                .frame(width: 24)
                                .foregroundStyle(AmenTheme.Colors.amenBlue)
                            Text(intent.composerDisplayName)
                            Spacer()
                            if vm.selectedIntent == intent {
                                Image(systemName: "checkmark").foregroundStyle(AmenTheme.Colors.amenBlue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("What are you trying to do?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { vm.showIntentPicker = false }
                }
            }
        }
    }

    // MARK: - Audience Selector Sheet

    private var audienceSelectorSheet: some View {
        NavigationStack {
            List(SmartAudienceRouter.shared.availableRoutes) { route in
                Button {
                    SmartAudienceRouter.shared.toggleRoute(id: route.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.label).font(.subheadline)
                            if let sub = route.subtitle {
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if SmartAudienceRouter.shared.selectedRouteIds.contains(route.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AmenTheme.Colors.amenBlue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Post Destinations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { vm.showAudienceSelector = false }
                }
            }
        }
    }
}
