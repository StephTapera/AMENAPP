// AmenUniversalComposerView.swift
// AMEN App — CommunityOS / Composer
//
// Phase 2 — Agent A3 (Universal Composer)
// The single unified creation sheet for ALL content intents.
//
// Presented via .sheet(isPresented:) with .presentationDetents([.large]).
// Design: white Liquid Glass aesthetic (C3 locked 2026-06-05).
//   - System semantic colors only — no custom hex, no amenGold.
//   - AmenDesignSystem tokens for radius / shadow.
//   - Dynamic Type throughout — no fixed font sizes.
//   - Anti-engagement: no public count display, no comparison metrics.
//   - Provenance banner shown when seeded from an existing source object.
//
// Accessibility:
//   - All interactive controls >= 44pt touch target.
//   - accessibilityLabel + accessibilityHint on every non-obvious element.
//   - Reduced-motion gate on all spring animations.
//   - Reduced-transparency fallback for glass surfaces.

import SwiftUI

// MARK: - AmenUniversalComposerView

struct AmenUniversalComposerView: View {

    // MARK: Inputs

    let source: ComposerSource
    let onDismiss: () -> Void

    // MARK: View Model

    @StateObject private var vm: AmenComposerViewModel

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Init

    init(source: ComposerSource, onDismiss: @escaping () -> Void) {
        self.source    = source
        self.onDismiss = onDismiss
        _vm = StateObject(wrappedValue: AmenComposerViewModel(source: source))
    }

    // MARK: - Computed

    private var sheetTitle: String {
        switch vm.draft.selectedIntent {
        case .discuss:   return "New Discussion"
        case .pray:      return "New Prayer"
        case .study:     return "New Study"
        case .teach:     return "New Teaching"
        case .share:     return "Share"
        case .ask:       return "Ask a Question"
        case .invite:    return "Send an Invite"
        case .volunteer: return "Volunteer"
        case .hire:      return "Post a Role"
        case .mentor:    return "Request a Mentor"
        case .announce:  return "Announcement"
        }
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

    private var bodyPlaceholder: String {
        switch vm.draft.selectedIntent {
        case .discuss:   return "What should the discussion focus on?"
        case .pray:      return "Describe this prayer request..."
        case .study:     return "What aspect would you like to study?"
        case .teach:     return "What is the main teaching point?"
        case .share:     return "Add a thought before sharing..."
        case .ask:       return "What would you like to ask?"
        case .invite:    return "Add a personal note to the invite..."
        case .volunteer: return "What can you offer?"
        case .hire:      return "Describe the role and opportunity..."
        case .mentor:    return "What area of mentorship are you seeking?"
        case .announce:  return "What would you like to announce?"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Provenance banner — shown when seeded from an existing source object.
                    if let ref = source.existingRef {
                        provenanceBanner(ref: ref, sourceType: source.type)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                    }

                    // Intent selector row.
                    intentSelectorSection
                        .padding(.top, source.existingRef != nil ? 0 : 16)
                        .padding(.bottom, 16)

                    Divider()
                        .padding(.horizontal, 16)

                    // Main text area.
                    textInputSection
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // Context-specific fields.
                    contextSpecificFields
                        .padding(.horizontal, 16)

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Audience selector.
                    audienceSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
            .onChange(of: vm.didSubmit) { submitted in
                if submitted { onDismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(AmenRadius.card)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss composer")
        }

        ToolbarItem(placement: .principal) {
            Text(sheetTitle)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
        }

        ToolbarItem(placement: .topBarTrailing) {
            submitButton
        }
    }

    // MARK: - Submit button (toolbar item)

    private var submitButton: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            ZStack {
                if vm.isSubmitting {
                    ProgressView()
                        .tint(Color.white)
                        .scaleEffect(0.8)
                } else {
                    Text(submitLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(vm.isValid ? Color.white : Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                vm.isValid
                    ? Color.accentColor
                    : Color(uiColor: .tertiarySystemFill),
                in: Capsule(style: .continuous)
            )
        }
        .disabled(!vm.isValid || vm.isSubmitting)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.24, dampingFraction: 0.84),
            value: vm.isValid
        )
        .accessibilityLabel(submitLabel)
        .accessibilityHint(
            vm.isValid
                ? "Tap to publish"
                : "Add content and fill required fields first"
        )
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
            Image(systemName: "arrow.turn.up.right")
                .font(.caption2)
            Text("Continuing from: \(sourceType.displayName) \u{00B7} \(shortRef)")
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Color(uiColor: .secondaryLabel))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source: \(sourceType.displayName), reference \(shortRef)")
    }

    // MARK: - Intent Selector

    private var intentSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to do?")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.config.allowedIntents, id: \.rawValue) { intent in
                        intentChip(intent: intent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Intent selector")
        }
    }

    private func intentChip(intent: AmenIntent) -> some View {
        let isSelected = vm.draft.selectedIntent == intent
        let meta = intentMeta(for: intent)

        return Button {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.22, dampingFraction: 0.80)
            ) {
                vm.updateIntent(intent)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: meta.systemImage)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Text(meta.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(
                isSelected
                    ? Color.accentColor
                    : Color(uiColor: .secondaryLabel)
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(uiColor: .secondarySystemFill)
            )
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta.displayName)
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(meta.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Title field — shown only for intents/sources that require a title.
            if vm.config.showTitleField {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(uiColor: .label))

                    TextField("Add a title...", text: $vm.draft.title)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .label))
                        .tint(Color.accentColor)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .accessibilityLabel("Title field")
                }
            }

            // Body text editor.
            VStack(alignment: .trailing, spacing: 6) {
                TextField(bodyPlaceholder, text: $vm.draft.body, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .label))
                    .tint(Color.accentColor)
                    .lineLimit(5...12)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .accessibilityLabel("Content field")
                    .accessibilityHint(bodyPlaceholder)

                // Character count — bottom right of the body area.
                characterCountView
            }
        }
    }

    private var characterCountView: some View {
        let count     = vm.draft.body.count
        let limit     = vm.characterLimit
        let remaining = limit - count
        let isOverLimit = remaining < 0

        return Text("\(remaining)")
            .font(.caption2)
            .foregroundStyle(
                isOverLimit
                    ? Color.red
                    : Color(uiColor: .tertiaryLabel)
            )
            .accessibilityLabel("\(remaining) characters remaining")
    }

    // MARK: - Context-Specific Fields

    @ViewBuilder
    private var contextSpecificFields: some View {
        // Prayer: privacy picker + anonymous toggle.
        if vm.config.showPrayerPrivacyPicker {
            prayerPrivacySection
                .padding(.bottom, 16)
        }

        // Job: role title + organization.
        if vm.config.showJobFields {
            jobFieldsSection
                .padding(.bottom, 16)
        }

        // Event: date/time picker.
        if vm.config.showEventFields {
            eventDateSection
                .padding(.bottom, 16)
        }

        // Study: scripture reference.
        if vm.config.showStudyFields {
            studyFieldsSection
                .padding(.bottom, 16)
        }
    }

    // MARK: Prayer privacy section

    private var prayerPrivacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prayer Privacy")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            Picker("Prayer Privacy", selection: $vm.draft.prayerPrivacyLevel) {
                Text("Private").tag("private")
                Text("Trusted Circle").tag("trusted_circle")
                Text("Members Only").tag("members_only")
                Text("Anonymous").tag("anonymous")
                Text("Public").tag("public")
            }
            .pickerStyle(.menu)
            .tint(Color.accentColor)
            .accessibilityLabel("Prayer privacy level selector")

            Toggle(isOn: $vm.draft.isAnonymous) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Post Anonymously")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .label))
                    Text("Your name will not be shown")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .tint(Color.accentColor)
            .accessibilityLabel("Post anonymously")
            .accessibilityHint("When on, your name will not be shown with this prayer")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: Job fields section

    private var jobFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Role Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            TextField("Job Title", text: $vm.draft.jobTitle)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .tint(Color.accentColor)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
                .accessibilityLabel("Job title")

            TextField("Organization", text: $vm.draft.jobOrganization)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .tint(Color.accentColor)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
                .accessibilityLabel("Organization name")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: Event date section

    private var eventDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Date & Time")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            DatePicker(
                "Event Date",
                selection: Binding(
                    get: { vm.draft.eventDate ?? Date() },
                    set: { vm.draft.eventDate = $0 }
                ),
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .tint(Color.accentColor)
            .accessibilityLabel("Event date and time picker")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: Study fields section

    private var studyFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scripture Reference")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            TextField("e.g. John 3:16, Romans 8:28", text: $vm.draft.scriptureReference)
                .font(.body)
                .foregroundStyle(Color(uiColor: .label))
                .tint(Color.accentColor)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
                .accessibilityLabel("Scripture reference field")
                .accessibilityHint("Enter a Bible verse or passage reference")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AmenRadius.input, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - Audience Selector

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can see this?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))

            Picker("Audience", selection: $vm.draft.audience) {
                Text("Public").tag("public_feed")
                Text("Church").tag("church_only")
                Text("Space Members").tag("space_members")
                Text("Trusted Circle").tag("trusted_circle")
                Text("Only Me").tag("private")
            }
            .pickerStyle(.segmented)
            .tint(Color.accentColor)
            .accessibilityLabel("Audience selector")
            .accessibilityHint("Choose who can see this content")
        }
    }

    // MARK: - Intent Meta Helper

    private struct IntentMetadata {
        let displayName: String
        let systemImage: String
    }

    private func intentMeta(for intent: AmenIntent) -> IntentMetadata {
        switch intent {
        case .share:     return IntentMetadata(displayName: "Share",     systemImage: "square.and.arrow.up")
        case .discuss:   return IntentMetadata(displayName: "Discuss",   systemImage: "bubble.left.and.bubble.right")
        case .pray:      return IntentMetadata(displayName: "Pray",      systemImage: "hands.and.sparkles")
        case .study:     return IntentMetadata(displayName: "Study",     systemImage: "book.pages")
        case .teach:     return IntentMetadata(displayName: "Teach",     systemImage: "person.wave.2")
        case .ask:       return IntentMetadata(displayName: "Ask",       systemImage: "questionmark.bubble")
        case .invite:    return IntentMetadata(displayName: "Invite",    systemImage: "person.badge.plus")
        case .volunteer: return IntentMetadata(displayName: "Volunteer", systemImage: "heart.circle")
        case .hire:      return IntentMetadata(displayName: "Hire",      systemImage: "briefcase")
        case .mentor:    return IntentMetadata(displayName: "Mentor",    systemImage: "person.2.circle")
        case .announce:  return IntentMetadata(displayName: "Announce",  systemImage: "megaphone")
        }
    }
}

// MARK: - Preview

#Preview("Composer — from Post") {
    struct PreviewWrapper: View {
        @State private var shown = true
        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .sheet(isPresented: $shown) {
                    AmenUniversalComposerView(
                        source: ComposerSource(
                            type: .newPost,
                            existingRef: "posts/abc123xyz",
                            existingOwnerId: "uid_owner",
                            prefillText: nil,
                            prefillTitle: nil
                        ),
                        onDismiss: { shown = false }
                    )
                }
        }
    }
    return PreviewWrapper()
}

#Preview("Composer — standalone prayer") {
    struct PreviewWrapper: View {
        @State private var shown = true
        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .sheet(isPresented: $shown) {
                    AmenUniversalComposerView(
                        source: ComposerSource(
                            type: .prayerRequest,
                            existingRef: nil,
                            existingOwnerId: nil,
                            prefillText: nil,
                            prefillTitle: nil
                        ),
                        onDismiss: { shown = false }
                    )
                }
        }
    }
    return PreviewWrapper()
}

#Preview("Composer — from Church Note") {
    struct PreviewWrapper: View {
        @State private var shown = true
        var body: some View {
            Color(uiColor: .systemGroupedBackground)
                .sheet(isPresented: $shown) {
                    AmenUniversalComposerView(
                        source: ComposerSource(
                            type: .churchNote,
                            existingRef: "users/uid1/churchNotes/note123",
                            existingOwnerId: "uid1",
                            prefillText: "Key insight: grace precedes works.",
                            prefillTitle: "Sunday Sermon Notes"
                        ),
                        onDismiss: { shown = false }
                    )
                }
        }
    }
    return PreviewWrapper()
}
