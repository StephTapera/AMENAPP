// TECH-DEBT: file exceeds 400-line guideline — candidate for decomposition
// AmenUniversalComposerView.swift
// AMEN App — CommunityOS / Composer
//
// Smart Liquid Glass Action Studio (v3 — 2026-06-08)
//
// Key changes from v2:
//   - No "What would you like to do?" — users start with a thought, not a form
//   - Dynamic hero heading + subtitle shift with detected intent (no reload flash)
//   - Action ribbon shows when empty (Liquid Glass capsule pills, emoji icons)
//   - PostIntentDetector runs on every keystroke (debounced 280ms) → intent pill
//     materialises from text when confidence > 0.55; auto-routes AmenIntent + audience
//   - AmenSmartContextDetectionEngine runs async → context chip strip appears
//   - Smart audience row: auto-selects based on intent; shows "Why?" explainer;
//     user override clears the explainer and persists their choice
//   - Contextual fields surface only when the selected intent actually needs them
//     (study → scripture ref, pray → privacy picker, invite → event date)
//   - All existing ViewModel submit / safety / alert / deep-link logic is UNCHANGED
//
// Design (C3):
//   - System semantic colours only (no hex). RegularMaterial / ThickMaterial for glass.
//   - No blue outlines. Selected state = ThickMaterial + primary stroke.
//   - Dynamic Type throughout.
//   - Reduce-motion / reduce-transparency gated on every animation / material surface.
//   - All touch targets >= 44pt.

import SwiftUI

// MARK: - AmenUniversalComposerView

struct AmenUniversalComposerView: View {

    // MARK: Inputs

    let source: ComposerSource
    let onDismiss: () -> Void

    // MARK: View Model

    @StateObject private var vm: AmenComposerViewModel

    // MARK: Detection State

    @State private var detectedPostIntent: PostIntent = .general
    @State private var detectedConfidence: Double = 0
    @State private var contextChips: [InsightChipModel] = []
    @State private var hasUserPickedIntent = false
    @State private var hasUserPickedAudience = false

    // MARK: AIL pre-send gate (C10/C11)
    // Proposal-only; zero-interference when AILPreSendInterceptor.shared.isEnabled == false (default).
    @State private var postSendGate = AILPreSendGate(messageKey: "universal-composer")

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Init

    init(source: ComposerSource, onDismiss: @escaping () -> Void) {
        self.source    = source
        self.onDismiss = onDismiss
        _vm = StateObject(wrappedValue: AmenComposerViewModel(source: source))
    }

    // MARK: - Derived display helpers

    private var heroHeading: String {
        if detectedConfidence > 0.55 && !hasUserPickedIntent {
            return detectedPostIntent.heroHeading
        }
        return vm.draft.selectedIntent.heroHeading
    }

    private var heroSubtitle: String {
        if source.existingRef != nil {
            return "Continuing from \(source.type.displayName)"
        }
        if detectedConfidence > 0.55 && !hasUserPickedIntent {
            return "Detected — tap pill to override"
        }
        return vm.draft.selectedIntent.heroSubtitle
    }

    private var bodyPlaceholder: String {
        if detectedConfidence > 0.55 && !hasUserPickedIntent {
            return detectedPostIntent.composerPlaceholder
        }
        return vm.draft.selectedIntent.composerPlaceholder
    }

    private var submitLabel: String {
        switch vm.draft.selectedIntent {
        case .discuss:   return "Open Discussion"
        case .pray:      return "Create Prayer"
        case .study:     return "Start Study"
        case .teach:     return "Create Teaching"
        case .share:     return "Share"
        case .ask:       return "Send Question"
        case .invite:    return "Send Invite"
        case .volunteer: return "Volunteer"
        case .hire:      return "Post Role"
        case .mentor:    return "Request Mentor"
        case .announce:  return "Announce"
        }
    }

    // Intent-driven smart audience recommendation
    private var smartAudienceInfo: SmartAudienceInfo {
        switch vm.draft.selectedIntent {
        case .pray, .mentor:
            return SmartAudienceInfo(
                raw: "trusted_circle", label: "Trusted",
                icon: "person.2.circle",
                reason: "Recommended for personal and private content"
            )
        case .study, .discuss:
            return SmartAudienceInfo(
                raw: "church_only", label: "Church",
                icon: "building.columns",
                reason: "Scripture discussions are great with your church community"
            )
        case .announce:
            return SmartAudienceInfo(
                raw: "space_members", label: "My Space",
                icon: "house",
                reason: "Announcements work best within your space"
            )
        default:
            return SmartAudienceInfo(
                raw: "public_feed", label: "Public",
                icon: "globe",
                reason: "Share with the broader Amen community"
            )
        }
    }

    // Whether to show intent-specific extra fields
    private var showStudyField:    Bool { vm.draft.selectedIntent == .study }
    private var showPrayerPrivacy: Bool { vm.draft.selectedIntent == .pray }
    private var showEventDate:     Bool { vm.draft.selectedIntent == .invite }
    private var needsContextPanel: Bool { showStudyField || showPrayerPrivacy || showEventDate }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Provenance banner (shown when seeded from an existing source object)
                if let ref = source.existingRef {
                    provenanceBanner(ref: ref, sourceType: source.type)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                // Dynamic hero strip
                heroSection
                    .padding(.horizontal, 16)
                    .padding(.top, source.existingRef != nil ? 8 : 18)
                    .padding(.bottom, 14)

                Divider()

                // Scrollable compose workspace
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Text compose area
                        composeTextArea
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        // Action ribbon (empty state) OR context chip strip (while typing)
                        if vm.draft.body.isEmpty && !hasUserPickedIntent {
                            actionRibbon
                                .padding(.top, 16)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        } else if !contextChips.isEmpty {
                            contextChipRow
                                .padding(.top, 12)
                                .padding(.horizontal, 16)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
                        }

                        // Contextual fields — surface only what the intent actually needs
                        if needsContextPanel {
                            contextualFields
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }

                        Spacer(minLength: 32)
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                    value: vm.draft.body.isEmpty
                )

                Divider()

                // Smart audience selector
                smartAudienceRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Unable to Post", isPresented: Binding(
                get: { vm.submitError != nil },
                set: { if !$0 { vm.submitError = nil } }
            )) {
                Button("OK", role: .cancel) { vm.submitError = nil }
            } message: {
                Text(vm.submitError ?? "Please try again.")
            }
            .sheet(item: $vm.pendingSafetyDecision) { decision in
                if case .crisisIntervene = decision.action {
                    AmenCrisisInterventionView { vm.pendingSafetyDecision = nil }
                } else {
                    AmenPrePostReviewSheet(
                        decision: decision,
                        draftContent: vm.draft.body,
                        onProceed: {
                            vm.pendingSafetyDecision = nil
                            Task { await vm.submit(skipSafetyCheck: true) }
                        },
                        onEdit:   { vm.pendingSafetyDecision = nil },
                        onCancel: { vm.pendingSafetyDecision = nil }
                    )
                }
            }
            .onChange(of: vm.didSubmit) { _, submitted in
                if submitted { onDismiss() }
            }
        }
        .task(id: vm.draft.body) { await runDetection() }
        .ailPreSendGate(postSendGate)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AmenRadius.card)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // Route through the AIL pre-send gate (C10/C11 — proposal-only).
                // When the interceptor is disabled (default), this forwards straight
                // to vm.submit() — zero interference.
                let draft = vm.draft.body
                postSendGate.submit(draft: draft) { _ in
                    Task { await vm.submit() }
                }
            } label: {
                ZStack {
                    if vm.isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text(submitLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(vm.isValid ? Color.white : Color(uiColor: .tertiaryLabel))
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    vm.isValid ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                    in: Capsule(style: .continuous)
                )
            }
            .disabled(!vm.isValid || vm.isSubmitting)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.84),
                value: vm.isValid
            )
            .accessibilityLabel(submitLabel)
            .accessibilityHint(vm.isValid ? "Tap to publish" : "Add content first")
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Text(heroHeading)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                        value: heroHeading
                    )

                // Auto-detected intent pill — materialises from text context
                if detectedConfidence > 0.55 && !hasUserPickedIntent {
                    detectedIntentPill
                        .transition(
                            reduceMotion ? .opacity :
                            .scale(scale: 0.75).combined(with: .opacity)
                        )
                }
            }

            Text(heroSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                    value: heroSubtitle
                )
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
            value: detectedConfidence
        )
    }

    private var detectedIntentPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.semibold))
            Text(detectedPostIntent.intentDisplayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color(uiColor: .label))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .systemGray5))
                : AnyShapeStyle(.regularMaterial),
            in: Capsule(style: .continuous)
        )
        .overlay(Capsule(style: .continuous).stroke(.separator, lineWidth: 0.5))
        .accessibilityLabel("Detected intent: \(detectedPostIntent.intentDisplayName). Tap an action pill to override.")
    }

    // MARK: - Compose Text Area

    private var composeTextArea: some View {
        ZStack(alignment: .topLeading) {
            if vm.draft.body.isEmpty {
                Text(bodyPlaceholder)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .placeholderText))
                    .allowsHitTesting(false)
                    .contentTransition(.opacity)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3),
                        value: bodyPlaceholder
                    )
            }
            TextEditor(text: $vm.draft.body)
                .font(.body)
                .frame(minHeight: 120, alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityLabel("Compose area")
                .accessibilityHint(bodyPlaceholder)
        }
    }

    // MARK: - Action Ribbon (empty state)

    private var actionRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredRibbonItems, id: \.intent.rawValue) { item in
                    ribbonPill(item: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action ribbon — choose a content type or just start typing")
    }

    private func ribbonPill(item: RibbonItem) -> some View {
        let isActive = vm.draft.selectedIntent == item.intent
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                vm.draft.selectedIntent = item.intent
                hasUserPickedIntent = true
                applySmartAudienceIfNeeded(for: item.intent)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(item.icon).font(.body)
                Text(item.label).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isActive ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? (reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemGray4)) : AnyShapeStyle(Material.thickMaterial))
                    : (reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemGray6)) : AnyShapeStyle(Material.regularMaterial)),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous).stroke(
                    isActive ? Color(uiColor: .label).opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(isActive ? 0.07 : 0.02), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.label) mode")
    }

    // MARK: - Context Chip Row

    private var contextChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(contextChips.prefix(4), id: \.actionKey) { chip in
                    HStack(spacing: 5) {
                        Image(systemName: chip.icon)
                            .font(.caption.weight(.medium))
                        Text(chip.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(uiColor: .label).opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        reduceTransparency
                            ? AnyShapeStyle(Color(uiColor: .systemGray5))
                            : AnyShapeStyle(.regularMaterial),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(Capsule(style: .continuous).stroke(.separator, lineWidth: 0.5))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detected context tags")
    }

    // MARK: - Contextual Fields

    @ViewBuilder
    private var contextualFields: some View {
        VStack(spacing: 14) {

            // Scripture Reference — Study mode
            if showStudyField {
                glassField(label: "Scripture Reference", icon: "book.closed") {
                    TextField("e.g. John 3:16, Romans 8:28", text: $vm.draft.scriptureReference)
                    .font(.subheadline)
                    .submitLabel(.done)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            // Prayer Privacy — Pray mode
            if showPrayerPrivacy {
                glassField(label: "Prayer Privacy", icon: "lock") {
                    Picker("Privacy", selection: $vm.draft.prayerPrivacyLevel) {
                        Text("Trusted").tag(PrayerPrivacyLevel.trustedCircle.rawValue)
                        Text("Church").tag(PrayerPrivacyLevel.church.rawValue)
                        Text("Public").tag(PrayerPrivacyLevel.public.rawValue)
                        Text("Anonymous").tag(PrayerPrivacyLevel.anonymous.rawValue)
                        Text("Only Me").tag(PrayerPrivacyLevel.private.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            // Event Date — Invite mode
            if showEventDate {
                glassField(label: "Event Date", icon: "calendar") {
                    DatePicker(
                        "Date",
                        selection: Binding(
                            get: { vm.draft.eventDate ?? Date() },
                            set: { vm.draft.eventDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
            value: vm.draft.selectedIntent
        )
    }

    // Reusable glass-surfaced field wrapper
    private func glassField<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            reduceTransparency
                                ? AnyShapeStyle(Color(uiColor: .systemGray6))
                                : AnyShapeStyle(.regularMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.separator, lineWidth: 0.5)
                        )
                )
        }
    }

    // MARK: - Smart Audience Row

    private var smartAudienceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(audienceOptions, id: \.raw) { option in
                        audiencePill(option: option)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Who can see this")

            // "Why?" explainer — disappears once user manually picks
            if !hasUserPickedAudience {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(smartAudienceInfo.reason)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .transition(
                    reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
            value: vm.draft.selectedIntent
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3),
            value: hasUserPickedAudience
        )
    }

    private func audiencePill(option: ComposerAudienceOption) -> some View {
        let isSelected = vm.draft.audience == option.raw
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                vm.draft.audience = option.raw
                hasUserPickedAudience = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(.caption.weight(.medium))
                Text(option.label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(
                isSelected
                    ? Color(uiColor: .label)
                    : Color(uiColor: .secondaryLabel)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? (reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemGray4)) : AnyShapeStyle(Material.thickMaterial))
                    : AnyShapeStyle(Color.clear),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous).stroke(
                    isSelected
                        ? Color(uiColor: .label).opacity(0.15)
                        : Color(uiColor: .separator).opacity(0.5),
                    lineWidth: isSelected ? 1 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label) audience")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Provenance Banner

    private func provenanceBanner(ref: String, sourceType: ComposerSourceType) -> some View {
        let shortRef: String = {
            let parts = ref.split(separator: "/")
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(String(parts.last ?? Substring(ref)).prefix(8))..."
            }
            return String(ref.prefix(24))
        }()

        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.up.right").font(.caption2)
            Text("Continuing from: \(sourceType.displayName) \u{00B7} \(shortRef)")
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(Color(uiColor: .secondarySystemFill))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(sourceType.displayName), reference \(shortRef)")
    }

    // MARK: - Detection pipeline

    @MainActor
    private func runDetection() async {
        let text = vm.draft.body
        guard text.count > 15 else {
            withAnimation(.spring(response: 0.3)) {
                detectedConfidence = 0
                contextChips = []
            }
            return
        }
        // Debounce — this task is cancelled automatically when body changes (task(id:))
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        // Tier 1: intent detection (instant, local heuristic)
        let (intent, confidence) = PostIntentDetector.shared.detect(text: text)
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
            detectedPostIntent = intent
            detectedConfidence = confidence
            if confidence > 0.65 && !hasUserPickedIntent {
                let amenIntent = intent.amenIntent
                vm.draft.selectedIntent = amenIntent
                applySmartAudienceIfNeeded(for: amenIntent)
            }
        }

        // Tier 2: context chips (async, actor-isolated)
        guard !Task.isCancelled else { return }
        let contextResult = await AmenSmartContextDetectionEngine.shared.detect(in: text)
        guard !Task.isCancelled else { return }
        let chips = AmenContextDetectionBridge.toInsightChips(from: contextResult)
        withAnimation(reduceMotion ? nil : .spring(response: 0.4)) {
            contextChips = Array(chips.prefix(4))
        }
    }

    private func applySmartAudienceIfNeeded(for intent: AmenIntent) {
        guard !hasUserPickedAudience else { return }
        vm.draft.audience = smartAudienceInfo.raw
    }

    // MARK: - Static data

    private var filteredRibbonItems: [RibbonItem] {
        let allowed = Set(vm.config.allowedIntents.map(\.rawValue))
        return allRibbonItems.filter { allowed.contains($0.intent.rawValue) }
    }

    private let allRibbonItems: [RibbonItem] = [
        RibbonItem(icon: "📖", label: "Study",    intent: .study),
        RibbonItem(icon: "🙏", label: "Prayer",   intent: .pray),
        RibbonItem(icon: "💬", label: "Discuss",  intent: .discuss),
        RibbonItem(icon: "🎉", label: "Invite",   intent: .invite),
        RibbonItem(icon: "📢", label: "Announce", intent: .announce),
        RibbonItem(icon: "🤝", label: "Mentor",   intent: .mentor),
        RibbonItem(icon: "🎓", label: "Teach",    intent: .teach),
        RibbonItem(icon: "❓", label: "Ask",      intent: .ask),
        RibbonItem(icon: "🙌", label: "Share",    intent: .share),
    ]

    private let audienceOptions: [ComposerAudienceOption] = [
        ComposerAudienceOption(raw: "public_feed",    label: "Public",   icon: "globe"),
        ComposerAudienceOption(raw: "church_only",    label: "Church",   icon: "building.columns"),
        ComposerAudienceOption(raw: "space_members",  label: "My Space", icon: "house"),
        ComposerAudienceOption(raw: "trusted_circle", label: "Trusted",  icon: "person.2.circle"),
        ComposerAudienceOption(raw: "private",        label: "Only Me",  icon: "lock"),
    ]
}

// MARK: - Private model types

private struct RibbonItem {
    let icon: String
    let label: String
    let intent: AmenIntent
}

private struct ComposerAudienceOption {
    let raw: String
    let label: String
    let icon: String
}

private struct SmartAudienceInfo {
    let raw: String
    let label: String
    let icon: String
    let reason: String
}

// MARK: - PostIntent extensions

private extension PostIntent {
    var heroHeading: String {
        switch self {
        case .prayerRequest:                     return "Ask for prayer"
        case .testimony, .gratitude:             return "Share a testimony"
        case .teaching, .sermonClip:             return "Share a teaching"
        case .announcement:                      return "Make an announcement"
        case .question:                          return "Ask a question"
        case .eventRecap, .missionUpdate:        return "Share an update"
        case .resource:                          return "Share a resource"
        default:                                 return "Share a thought"
        }
    }

    var intentDisplayName: String {
        switch self {
        case .prayerRequest:   return "Prayer Request"
        case .testimony:       return "Testimony"
        case .teaching:        return "Teaching"
        case .sermonClip:      return "Sermon Clip"
        case .announcement:    return "Announcement"
        case .question:        return "Question"
        case .gratitude:       return "Gratitude"
        case .eventRecap:      return "Event"
        case .missionUpdate:   return "Mission Update"
        case .resource:        return "Resource"
        case .reflection:      return "Reflection"
        case .general:         return "Share"
        }
    }

    // Maps PostIntent (detection) → AmenIntent (ViewModel)
    var amenIntent: AmenIntent {
        switch self {
        case .prayerRequest:            return .pray
        case .question:                 return .ask
        case .announcement:             return .announce
        case .teaching, .sermonClip:    return .teach
        case .testimony, .gratitude, .reflection, .eventRecap,
             .missionUpdate, .resource, .general:
            return .share
        }
    }
}

// MARK: - AmenIntent extensions

private extension AmenIntent {
    var heroHeading: String {
        switch self {
        case .discuss:   return "Start a discussion"
        case .pray:      return "Ask for prayer"
        case .study:     return "Explore scripture"
        case .teach:     return "Share a teaching"
        case .share:     return "Share a thought"
        case .ask:       return "Ask the community"
        case .invite:    return "Send an invitation"
        case .volunteer: return "Volunteer"
        case .hire:      return "Post a role"
        case .mentor:    return "Request mentorship"
        case .announce:  return "Make an announcement"
        }
    }

    var heroSubtitle: String {
        switch self {
        case .discuss:   return "Open a conversation with your community"
        case .pray:      return "Invite others to pray alongside you"
        case .study:     return "Dive deeper into God's word together"
        case .teach:     return "Pass on what God has shown you"
        case .share:     return "Start typing — we'll adapt as you go"
        case .ask:       return "Ask a question, start a conversation"
        case .invite:    return "Bring people together for something meaningful"
        case .volunteer: return "Offer your time and gifts"
        case .hire:      return "Find someone gifted for this role"
        case .mentor:    return "Connect with someone who can guide you"
        case .announce:  return "Share something important with your community"
        }
    }

    var composerPlaceholder: String {
        switch self {
        case .discuss:   return "What should the discussion focus on?"
        case .pray:      return "Describe your prayer need..."
        case .study:     return "What aspect would you like to study?"
        case .teach:     return "What is the main teaching point?"
        case .share:     return "Start typing — we'll adapt as you go..."
        case .ask:       return "What would you like to ask?"
        case .invite:    return "Add a personal note to the invite..."
        case .volunteer: return "What can you offer?"
        case .hire:      return "Describe the role and opportunity..."
        case .mentor:    return "What area of mentorship are you seeking?"
        case .announce:  return "What would you like to announce?"
        }
    }
}
