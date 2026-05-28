//
//  YourFeedView.swift
//  AMENAPP
//
//  "Your Feed" — the Liquid Glass feed stewardship control center.
//  Replaces the plain HeyFeedControlsSheet with a full-featured surface:
//    • Feed mode selection with spiritual framing
//    • Three-state topic chips (boost / neutral / suppress)
//    • Active NL adjustments with time-remaining badges
//    • Session mode carousel
//    • Full Hey Feed NL input (inline, no separate sheet)
//    • Debate tolerance + content sensitivity + pacing
//    • Seasonal faith calendar intelligence strip
//
//  Entry points: PostFeedActions sheet, SettingsView, PostsSearchView
//

import SwiftUI
import FirebaseAuth

// MARK: - Entry Point

struct YourFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var prefsSvc    = HeyFeedPreferencesService.shared
    @ObservedObject private var nlSvc       = HeyFeedNLPreferencesService.shared
    @ObservedObject private var sessionSvc  = HeyFeedSessionModeService.shared
    @ObservedObject private var contextPrefs = ContextLabelPreferenceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Section expansion state
    @State private var modeExpanded         = true
    @State private var topicsExpanded       = true
    @State private var tuningExpanded       = true
    @State private var sessionExpanded      = false
    @State private var advancedExpanded     = false
    @State private var contextLabelsExpanded = false
    @State private var showResetLabelsConfirmation = false

    // NL inline input
    @State private var nlInputText          = ""
    @State private var nlParsedIntent: HeyFeedParsedIntent?
    @State private var nlIsSubmitting       = false
    @State private var nlShowSuccess        = false
    @State private var nlParseTask: Task<Void, Never>?
    @State private var nlSelectedDuration: HeyFeedDuration = .threeDays
    @FocusState private var nlInputFocused: Bool

    // Seasonal data
    @State private var seasonalContext: FeedSeasonalContext = .current()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerHero
                            .padding(.bottom, 24)


                        // Seasonal strip (if seasonally relevant)
                        if seasonalContext.isSeasonallyActive {
                            seasonalStrip
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        }

                        // Feed Mode
                        collapsibleSection(
                            title: "Feed Mode",
                            icon: "wand.and.stars",
                            isExpanded: $modeExpanded
                        ) {
                            feedModeSection
                        }

                        sectionDivider

                        // Topic Controls
                        collapsibleSection(
                            title: "Topics",
                            icon: "tag.fill",
                            badge: activePinnedTopicsCount > 0 ? "\(activePinnedTopicsCount) boosted" : nil,
                            isExpanded: $topicsExpanded
                        ) {
                            topicsSection
                        }

                        sectionDivider

                        // Hey Feed NL Tuning
                        collapsibleSection(
                            title: "Feed Tuning",
                            icon: "slider.horizontal.below.rectangle",
                            badge: activeAdjustmentsCount > 0 ? "\(activeAdjustmentsCount) active" : nil,
                            isExpanded: $tuningExpanded
                        ) {
                            tuningSection
                        }

                        sectionDivider

                        // Session Mode
                        collapsibleSection(
                            title: "Session Mode",
                            icon: sessionSvc.isActive ? sessionSvc.activeMode.icon : "moon.stars",
                            badge: sessionSvc.isActive ? sessionSvc.timeRemainingLabel : nil,
                            isExpanded: $sessionExpanded
                        ) {
                            sessionModeSection
                        }

                        sectionDivider

                        // Advanced (Debate, Sensitivity, Pacing)
                        collapsibleSection(
                            title: "Advanced",
                            icon: "gearshape",
                            isExpanded: $advancedExpanded
                        ) {
                            advancedSection
                        }

                        sectionDivider

                        collapsibleSection(
                            title: "Context Labels",
                            icon: "text.bubble",
                            badge: contextPrefs.contextualLabelsDisabled ? "off" : nil,
                            isExpanded: $contextLabelsExpanded
                        ) {
                            contextLabelsSection
                        }

                        Spacer(minLength: 48)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(24)
        .presentationBackground(.regularMaterial)
        .alert("Reset hidden labels?", isPresented: $showResetLabelsConfirmation) {
            Button("Reset", role: .destructive) {
                Task { await contextPrefs.resetHiddenLabels() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all previously hidden topic labels to your feed. Your other feed preferences won't be affected.")
        }
        .onAppear {
            nlSvc.startListening()
            sessionExpanded = sessionSvc.isActive
            AmenWellbeingService.shared.onSessionStart()
        }
    }

    // MARK: - Header Hero

    private var headerHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Feed")
                        .font(AMENFont.bold(22))
                        .foregroundStyle(.primary)
                    Text("Steward what you see")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if activeAdjustmentsCount > 0 || sessionSvc.isActive {
                    adjustmentBadge
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var adjustmentBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("Tuned")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        )
    }

    // MARK: - Seasonal Strip

    private var seasonalStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: seasonalContext.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(seasonalContext.color)
                .frame(width: 32, height: 32)
                .background(seasonalContext.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(seasonalContext.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                Text(seasonalContext.suggestion)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))) {
                    _ = prefsSvc.preferences.pinnedTopics.insert(seasonalContext.suggestedTopic)
                }
                Task { await prefsSvc.savePreferences() }
            } label: {
                Text("Boost")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(seasonalContext.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(seasonalContext.color.opacity(0.10))
                            .overlay(Capsule().strokeBorder(seasonalContext.color.opacity(0.25), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Boost \(seasonalContext.title)")
            .accessibilityHint("Pins \(seasonalContext.title) to your feed preferences")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(seasonalContext.color.opacity(0.20), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Feed Mode Section

    private var feedModeSection: some View {
        VStack(spacing: 8) {
            ForEach(FeedMode.allCases, id: \.self) { mode in
                feedModeRow(mode)
            }

            Divider().padding(.vertical, 4)

            SacredFeedModeBar()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var contextLabelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { !contextPrefs.contextualLabelsDisabled },
                set: { newValue in
                    Task { await contextPrefs.setDisabled(!newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show Context Labels")
                        .font(AMENFont.semiBold(14))
                    Text("Quiet explanations for why select posts appear in your feed.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            if !contextPrefs.mutedContextTopicIds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muted topics")
                        .font(AMENFont.semiBold(13))
                    ForEach(contextPrefs.mutedContextTopicIds.sorted(), id: \.self) { topicId in
                        contextPreferenceRow(title: TopicNormalizationService.shared.displayName(for: topicId)) {
                            Task { await contextPrefs.unmute(topicId: topicId) }
                        }
                    }
                }
            }

            if !contextPrefs.mutedContextTypes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Muted label types")
                        .font(AMENFont.semiBold(13))
                    ForEach(contextPrefs.mutedContextTypes.sorted(), id: \.self) { typeRawValue in
                        let title = AmenFeedContextType(rawValue: typeRawValue)?.displayPrefix ?? typeRawValue
                        contextPreferenceRow(title: title) {
                            Task { await contextPrefs.unmute(typeRawValue: typeRawValue) }
                        }
                    }
                }
            }

            Button("Reset hidden labels") {
                showResetLabelsConfirmation = true
            }
            .font(AMENFont.semiBold(13))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func contextPreferenceRow(title: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AMENFont.regular(12))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button("Remove", action: onRemove)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func feedModeRow(_ mode: FeedMode) -> some View {
        let isSelected = prefsSvc.preferences.mode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await prefsSvc.setMode(mode) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isSelected ? Color.primary : Color(.systemGray5))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.75)), value: isSelected)
    }

    // MARK: - Topics Section

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap to boost. Long-press to suppress.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            YourFeedTopicFlowView(
                topics: FeedTopic.allCases,
                pinnedTopics: prefsSvc.preferences.pinnedTopics,
                blockedTopics: prefsSvc.preferences.blockedTopics
            ) { topic, action in
                Task {
                    switch action {
                    case .pin:      await prefsSvc.toggleTopicPin(topic)
                    case .suppress: await prefsSvc.blockTopic(topic)
                    case .unblock:  await prefsSvc.unblockTopic(topic)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Feed Tuning Section (NL + Active Preferences)

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            nlInputBlock
                .padding(.horizontal, 16)

            if !nlSvc.activePreferences.filter({ !$0.isExpired }).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active adjustments")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    ForEach(nlSvc.activePreferences.filter { !$0.isExpired }) { pref in
                        YourFeedActiveAdjustmentRow(preference: pref) {
                            Task { try? await nlSvc.removePreference(id: pref.id) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            quickChipsBlock
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    private var nlInputBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("e.g. more testimonies this week…", text: $nlInputText, axis: .vertical)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1...3)
                    .focused($nlInputFocused)
                    .onChange(of: nlInputText) { _, newValue in scheduleNLParse(newValue) }
                    .submitLabel(.done)
                    .onSubmit { submitNLIfReady() }

                if !nlInputText.isEmpty {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                            nlInputText = ""
                            nlParsedIntent = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(nlInputFocused ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
                    )
            )

            if !nlInputText.isEmpty {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("For:")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                            ForEach(HeyFeedDuration.allCases, id: \.self) { dur in
                                Button {
                                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) {
                                        nlSelectedDuration = dur
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text(dur.label.capitalized)
                                        .font(AMENFont.semiBold(11))
                                        .foregroundStyle(nlSelectedDuration == dur ? .primary : .secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule().fill(
                                                nlSelectedDuration == dur
                                                    ? Color(.systemGray4)
                                                    : Color.clear
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Button { submitNLIfReady() } label: {
                        HStack(spacing: 4) {
                            if nlIsSubmitting {
                                ProgressView().scaleEffect(0.75)
                            } else if nlShowSuccess {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(nlShowSuccess ? "Applied" : "Apply")
                                .font(AMENFont.semiBold(13))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(nlShowSuccess ? Color.green : Color.primary))
                    }
                    .buttonStyle(.plain)
                    .disabled(nlIsSubmitting || nlInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.opacity)

                if let intent = nlParsedIntent, !intent.targets.isEmpty {
                    nlIntentPreview(intent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78)), value: !nlInputText.isEmpty)
        .animation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.78)), value: nlParsedIntent != nil)
    }

    private func nlIntentPreview(_ intent: HeyFeedParsedIntent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Understood as")
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.secondary)
                Spacer()
                if intent.requiresConfirmation {
                    Text("Low confidence")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.orange)
                }
            }
            ForEach(intent.targets) { target in
                HStack(spacing: 6) {
                    Image(systemName: nlActionIcon(intent.action))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(nlActionColor(intent.action))
                    Text("\(intent.action.verbLabel) \(target.label) · \(intent.duration.label)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var quickChipsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick adjustments")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)

            AMENFlowLayout(spacing: 8) {
                ForEach(Self.quickChips, id: \.label) { chip in
                    Button {
                        nlInputText = chip.command
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        nlInputFocused = false
                        scheduleNLParse(chip.command)
                    } label: {
                        Text(chip.label)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.thinMaterial)
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Session Mode Section

    private var sessionModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessionSvc.isActive {
                HStack(spacing: 8) {
                    Image(systemName: sessionSvc.activeMode.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(sessionSvc.activeMode.label)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.primary)
                    Text(sessionSvc.timeRemainingLabel)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        sessionSvc.clearMode()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text("Clear")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            } else {
                Text("Set a temporary vibe for this session or longer.")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HeyFeedSessionMode.allCases.filter { $0 != .none }, id: \.id) { mode in
                        YourFeedSessionModeChip(
                            mode: mode,
                            isActive: sessionSvc.activeMode == mode
                        ) {
                            if sessionSvc.activeMode == mode {
                                sessionSvc.clearMode()
                            } else {
                                sessionSvc.setMode(mode)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(spacing: 16) {
            yFAdvancedPicker(
                label: "Debate Tolerance",
                icon: "bubble.left.and.bubble.right",
                options: DebateLevel.allCases,
                selected: prefsSvc.preferences.debateLevel,
                displayName: { $0.displayName },
                description: { $0.description }
            ) { level in Task { await prefsSvc.setDebateLevel(level) } }

            Divider().padding(.horizontal, 16)

            yFAdvancedPicker(
                label: "Content Safety",
                icon: "shield",
                options: SensitivityFilter.allCases,
                selected: prefsSvc.preferences.sensitivityFilter,
                displayName: { $0.displayName },
                description: { $0.description }
            ) { filter in Task { await prefsSvc.setSensitivityFilter(filter) } }

            Divider().padding(.horizontal, 16)

            yFAdvancedPicker(
                label: "Refresh Pacing",
                icon: "arrow.clockwise",
                options: RefreshPacing.allCases,
                selected: prefsSvc.preferences.refreshPacing,
                displayName: { $0.displayName },
                description: { $0.description }
            ) { pacing in Task { await prefsSvc.setRefreshPacing(pacing) } }

            if activeAdjustmentsCount > 0 || sessionSvc.isActive {
                Divider().padding(.horizontal, 16)

                Button {
                    Task {
                        try? await nlSvc.removeAll()
                        sessionSvc.clearMode()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reset all feed tuning")
                            .font(AMENFont.regular(14))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4).padding(.bottom, 12)
        }
    }

    private func yFAdvancedPicker<T: Equatable & Hashable>(
        label: String,
        icon: String,
        options: [T],
        selected: T,
        displayName: @escaping (T) -> String,
        description: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selected == option
                    Button {
                        onSelect(option)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(option))
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(.primary)
                                Text(description(option))
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.primary.opacity(0.07) : Color(.systemGray6))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Collapsible Section Shell

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        badge: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.80))) {
                    isExpanded.wrappedValue.toggle()
                }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)

                    if let badge {
                        Text(badge)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded.wrappedValue ? "Double tap to collapse" : "Double tap to expand")
            .accessibilityAddTraits(.isButton)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, 16)
    }

    // MARK: - Computed Helpers

    private var activePinnedTopicsCount: Int {
        prefsSvc.preferences.pinnedTopics.count
    }

    private var activeAdjustmentsCount: Int {
        nlSvc.activePreferences.filter { !$0.isExpired }.count
    }

    private func nlActionIcon(_ action: HeyFeedNLAction) -> String {
        switch action {
        case .increase: return "arrow.up"
        case .decrease: return "arrow.down"
        case .mute:     return "eye.slash"
        case .explore:  return "sparkles"
        case .balance:  return "arrow.2.circlepath"
        }
    }

    private func nlActionColor(_ action: HeyFeedNLAction) -> Color {
        switch action {
        case .increase: return .green
        case .decrease: return .orange
        case .mute:     return .red
        case .explore:  return .blue
        case .balance:  return .secondary
        }
    }

    // MARK: - NL Parse / Submit

    private func scheduleNLParse(_ text: String) {
        nlParseTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { nlParsedIntent = nil; return }
        nlParseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            nlParsedIntent = HeyFeedNLParser.shared.parse(trimmed)
            if let detected = nlParsedIntent?.duration {
                nlSelectedDuration = detected
            }
        }
    }

    private func submitNLIfReady() {
        let trimmed = nlInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !nlIsSubmitting else { return }
        let intent = nlParsedIntent ?? HeyFeedNLParser.shared.parse(trimmed)
        guard !intent.targets.isEmpty else {
            ToastManager.shared.info("We didn't understand that — try \"show more prayer\" or \"less news\"")
            return
        }
        let finalIntent = HeyFeedParsedIntent(
            action: intent.action,
            targets: intent.targets,
            duration: nlSelectedDuration,
            strength: intent.strength,
            confidence: intent.confidence,
            originalText: intent.originalText,
            requiresConfirmation: false,
            parserVersion: intent.parserVersion
        )
        nlIsSubmitting = true
        Task { @MainActor in
            try? await nlSvc.applyIntent(finalIntent)
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                nlIsSubmitting = false
                nlShowSuccess  = true
                nlInputText    = ""
                nlParsedIntent = nil
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { nlShowSuccess = false }
        }
    }

    // MARK: - Static Data

    private static let quickChips: [(label: String, command: String)] = [
        (label: "More testimonies",    command: "show me more testimonies"),
        (label: "More prayer",         command: "more prayer requests"),
        (label: "Less debate",         command: "less controversial debate"),
        (label: "More Bible teaching", command: "more bible teaching this week"),
        (label: "More encouragement",  command: "more encouraging content"),
        (label: "People I follow",     command: "more from people I follow"),
        (label: "Less repetitive",     command: "less repetitive content"),
        (label: "More local",          command: "more local churches near me"),
    ]
}

// MARK: - FeedMode icon extension

extension FeedMode {
    var icon: String {
        switch self {
        case .balanced:         return "equal.circle"
        case .friendsFirst:     return "person.2.fill"
        case .localCommunity:   return "mappin.circle.fill"
        case .ideasLearning:    return "lightbulb.fill"
        case .quiet:            return "moon.stars"
        }
    }
}

// MARK: - Three-State Topic Flow View

struct YourFeedTopicFlowView: View {
    let topics: [FeedTopic]
    let pinnedTopics: Set<FeedTopic>
    let blockedTopics: Set<FeedTopic>

    enum TopicAction { case pin, suppress, unblock }
    let onAction: (FeedTopic, TopicAction) -> Void

    var body: some View {
        AMENFlowLayout(spacing: 8) {
            ForEach(topics, id: \.self) { topic in
                YourFeedTopicChip(
                    topic: topic,
                    chipState: chipState(for: topic)
                ) {
                    onAction(topic, primaryAction(for: topic))
                } onLongPress: {
                    onAction(topic, suppressAction(for: topic))
                }
            }
        }
    }

    private func chipState(for topic: FeedTopic) -> YourFeedTopicChip.ChipState {
        if pinnedTopics.contains(topic)  { return .boosted }
        if blockedTopics.contains(topic) { return .suppressed }
        return .neutral
    }

    private func primaryAction(for topic: FeedTopic) -> TopicAction {
        if blockedTopics.contains(topic) { return .unblock }
        return .pin
    }

    private func suppressAction(for topic: FeedTopic) -> TopicAction {
        if blockedTopics.contains(topic) { return .unblock }
        return .suppress
    }
}

// MARK: - Three-State Topic Chip

struct YourFeedTopicChip: View {
    let topic: FeedTopic
    let chipState: ChipState
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false

    enum ChipState { case neutral, boosted, suppressed }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: leadingIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chipForeground)
            Text(topic.displayName)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(chipForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(chipFill)
                .overlay(Capsule().strokeBorder(chipStroke, lineWidth: 0.5))
        )
        .scaleEffect(pressing ? 0.94 : 1.0)
        .animation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.7)), value: pressing)
        .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75)), value: chipState)
        .accessibilityLabel(chipAccessibilityLabel)
        .accessibilityHint(chipState == .suppressed ? "Double tap to unblock" : "Double tap to boost, long press to suppress")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in pressing = true }
                .onEnded { _ in
                    pressing = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
        )
        .onTapGesture { onTap() }
    }

    private var chipAccessibilityLabel: String {
        switch chipState {
        case .neutral:    return topic.displayName
        case .boosted:    return "\(topic.displayName), boosted"
        case .suppressed: return "\(topic.displayName), suppressed"
        }
    }

    private var leadingIcon: String {
        switch chipState {
        case .neutral:    return topic.icon
        case .boosted:    return "arrow.up"
        case .suppressed: return "eye.slash"
        }
    }

    private var chipForeground: Color {
        switch chipState {
        case .neutral:    return .primary
        case .boosted:    return .white
        case .suppressed: return .secondary
        }
    }

    private var chipFill: Color {
        switch chipState {
        case .neutral:    return Color(.systemGray5)
        case .boosted:    return Color.primary
        case .suppressed: return Color.primary.opacity(0.05)
        }
    }

    private var chipStroke: Color {
        switch chipState {
        case .neutral:    return Color.clear
        case .boosted:    return Color.clear
        case .suppressed: return Color.primary.opacity(0.12)
        }
    }
}

// MARK: - Session Mode Chip

struct YourFeedSessionModeChip: View {
    let mode: HeyFeedSessionMode
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .secondary)
                Text(mode.label)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(isActive ? .white : .primary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? Color.primary : Color(.systemGray5))
                    .overlay(
                        Capsule()
                            .strokeBorder(isActive ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75)), value: isActive)
        .accessibilityLabel(isActive ? "\(mode.label), active" : mode.label)
        .accessibilityHint(isActive ? "Double tap to clear session mode" : "Double tap to activate \(mode.label) session mode")
    }
}

// MARK: - Active Adjustment Row

struct YourFeedActiveAdjustmentRow: View {
    let preference: HeyFeedNLPreference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: actionIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(actionColor)
                .frame(width: 18)

            Text(preference.targetLabel)
                .font(AMENFont.regular(13))
                .foregroundStyle(.primary)

            Spacer()

            Text(preference.timeRemainingLabel)
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(preference.targetLabel) adjustment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var actionIcon: String {
        switch preference.action {
        case .increase: return "arrow.up"
        case .decrease: return "arrow.down"
        case .mute:     return "eye.slash"
        case .explore:  return "sparkles"
        case .balance:  return "arrow.2.circlepath"
        }
    }

    private var actionColor: Color {
        switch preference.action {
        case .increase: return .green
        case .decrease: return .orange
        case .mute:     return .red
        case .explore:  return .blue
        case .balance:  return .secondary
        }
    }
}

// MARK: - Seasonal Context Model

struct FeedSeasonalContext {
    let title: String
    let suggestion: String
    let icon: String
    let color: Color
    let suggestedTopic: FeedTopic
    var isSeasonallyActive: Bool

    static func current() -> FeedSeasonalContext {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let day   = cal.component(.day, from: now)

        // Advent (Dec 1–24)
        if month == 12 && day <= 24 {
            return FeedSeasonalContext(
                title: "Season of Advent",
                suggestion: "Boost reflective, waiting, and hope content.",
                icon: "star.fill",
                color: Color(red: 0.55, green: 0.20, blue: 0.65),
                suggestedTopic: .faith,
                isSeasonallyActive: true
            )
        }
        // Christmas (Dec 25–31)
        if month == 12 {
            return FeedSeasonalContext(
                title: "Christmas Season",
                suggestion: "More testimonies, nativity reflections, and joy.",
                icon: "gift.fill",
                color: Color(red: 0.75, green: 0.15, blue: 0.10),
                suggestedTopic: .faith,
                isSeasonallyActive: true
            )
        }
        // Lent (March)
        if month == 3 {
            return FeedSeasonalContext(
                title: "Lenten Season",
                suggestion: "Boost fasting, sacrifice, and renewal content.",
                icon: "flame.fill",
                color: Color(red: 0.60, green: 0.25, blue: 0.10),
                suggestedTopic: .faith,
                isSeasonallyActive: true
            )
        }
        // Easter (April, first half)
        if month == 4 && day <= 20 {
            return FeedSeasonalContext(
                title: "Easter Season",
                suggestion: "More resurrection hope and testimony content.",
                icon: "cross.fill",
                color: Color(red: 0.85, green: 0.60, blue: 0.15),
                suggestedTopic: .faith,
                isSeasonallyActive: true
            )
        }
        // Back to school (August)
        if month == 8 {
            return FeedSeasonalContext(
                title: "New Season",
                suggestion: "Focus: faith in daily life, practical guidance.",
                icon: "book.fill",
                color: Color(red: 0.20, green: 0.52, blue: 0.80),
                suggestedTopic: .faith,
                isSeasonallyActive: true
            )
        }
        return FeedSeasonalContext(
            title: "",
            suggestion: "",
            icon: "calendar",
            color: .secondary,
            suggestedTopic: .faith,
            isSeasonallyActive: false
        )
    }
}
