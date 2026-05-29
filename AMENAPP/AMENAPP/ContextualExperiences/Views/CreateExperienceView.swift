import SwiftUI

// MARK: - CreateExperienceView

/// Multi-step wizard for creating a new ContextualExperience.
/// 5 steps: Type → Configure → Theme → Modules → Review
struct CreateExperienceView: View {

    let organization: Organization
    let orgType: OrganizationType

    @StateObject private var viewModel = CreateExperienceViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accentSwatches: [(label: String, hex: String)] = [
        ("Gold",   "#C9A84C"),
        ("Purple", "#5B2D8E"),
        ("Blue",   "#1A6DB5"),
        ("Black",  "#0A0A0A"),
        ("White",  "#F5F5F5")
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressCapsule
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let error = viewModel.error {
                    inlineError(error)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }

                navigationBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle(viewModel.currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .accessibilityLabel("Cancel experience creation")
                }
            }
        }
        .onChange(of: viewModel.savedExperienceId) { _, id in
            if id != nil { dismiss() }
        }
    }

    // MARK: - Progress capsule

    private var progressCapsule: some View {
        HStack(spacing: 6) {
            ForEach(CreateExperienceViewModel.CreateStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(
                        step == viewModel.currentStep
                            ? AmenTheme.Colors.buttonPrimary
                            : (stepIndex(step) < stepIndex(viewModel.currentStep)
                               ? AmenTheme.Colors.buttonPrimary.opacity(0.45)
                               : AmenTheme.Colors.surfaceChip)
                    )
                    .frame(height: 4)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78),
                        value: viewModel.currentStep
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(viewModel.currentStep.index) of 5")
        .accessibilityValue(viewModel.currentStep.title)
    }

    private func stepIndex(_ step: CreateExperienceViewModel.CreateStep) -> Int {
        step.index
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            switch viewModel.currentStep {
            case .type:
                typeStepView
            case .configure:
                configureStepView
            case .theme:
                themeStepView
            case .modules:
                modulesStepView
            case .review:
                reviewStepView
            }
        }
    }

    // MARK: - Step 1: Type picker

    private var typeStepView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(ExperienceType.allCases, id: \.self) { type in
                typeCard(type)
            }
        }
        .padding(16)
    }

    private func typeCard(_ type: ExperienceType) -> some View {
        let isSelected = viewModel.selectedType == type
        return Button {
            HapticManager.impact(style: .light)
            withAnimation(
                reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78)
            ) {
                viewModel.selectedType = type
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(
                        isSelected
                            ? AmenTheme.Colors.buttonPrimaryText
                            : AmenTheme.Colors.textPrimary
                    )
                Text(type.displayName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(
                        isSelected
                            ? AmenTheme.Colors.buttonPrimaryText
                            : AmenTheme.Colors.textPrimary
                    )
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AmenTheme.Colors.buttonPrimary : AmenTheme.Colors.surfaceChip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : AmenTheme.Colors.borderSoft,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(type.displayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Step 2: Configure

    private var configureStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            formField(label: "Title") {
                TextField("e.g. Easter Week 2026", text: $viewModel.title)
                    .font(AMENFont.regular(15))
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AmenTheme.Colors.surfaceInput)
                    )
                    .accessibilityLabel("Experience title")
            }

            formField(label: "Description") {
                TextField(
                    "Describe this experience...",
                    text: $viewModel.description,
                    axis: .vertical
                )
                .font(AMENFont.regular(15))
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                )
                .accessibilityLabel("Experience description")
            }

            formField(label: "Start Date") {
                DatePicker(
                    "Start Date",
                    selection: $viewModel.startDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .accessibilityLabel("Start date")
            }

            formField(label: "End Date") {
                DatePicker(
                    "End Date",
                    selection: $viewModel.endDate,
                    in: viewModel.startDate...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .accessibilityLabel("End date")
            }

            formField(label: "Visibility") {
                Picker("Visibility", selection: $viewModel.visibility) {
                    ForEach(ExperienceScope.allCases, id: \.self) { vis in
                        Text(vis.displayName).tag(vis)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Visibility: \(viewModel.visibility.displayName)")
            }
        }
        .padding(16)
    }

    // MARK: - Step 3: Theme

    private var themeStepView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Live preview
            ContextualExperienceFeedBanner(
                resolved: previewResolved,
                onTap: {},
                onDismiss: {}
            )

            formField(label: "Accent Color") {
                HStack(spacing: 12) {
                    ForEach(accentSwatches, id: \.hex) { swatch in
                        accentSwatchButton(swatch)
                    }
                    Spacer()
                }
            }

            formField(label: "Motion Intensity") {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { viewModel.theme.motionIntensity },
                            set: { v in
                                viewModel.theme = ExperienceThemeConfig(
                                    accentColorHex: viewModel.theme.accentColorHex,
                                    motionIntensity: v,
                                    glassOpacity: viewModel.theme.glassOpacity,
                                    backgroundStyle: viewModel.theme.backgroundStyle
                                )
                            }
                        ),
                        in: 0...1
                    )
                    .accessibilityLabel("Motion intensity")
                    .accessibilityValue(
                        String(format: "%.0f%%", viewModel.theme.motionIntensity * 100)
                    )
                    HStack {
                        Text("Subtle")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                        Spacer()
                        Text("Dynamic")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func accentSwatchButton(_ swatch: (label: String, hex: String)) -> some View {
        let isSelected = viewModel.theme.accentColorHex == swatch.hex
        return Button {
            HapticManager.impact(style: .light)
            viewModel.theme = ExperienceThemeConfig(
                accentColorHex: swatch.hex,
                motionIntensity: viewModel.theme.motionIntensity,
                glassOpacity: viewModel.theme.glassOpacity,
                backgroundStyle: viewModel.theme.backgroundStyle
            )
        } label: {
            Circle()
                .fill(Color(hex: swatch.hex))
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected
                                ? AmenTheme.Colors.buttonPrimary
                                : Color.clear,
                            lineWidth: 3
                        )
                        .padding(-4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(swatch.label) accent color")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select \(swatch.label)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var previewResolved: ResolvedExperience {
        ResolvedExperience(
            activeExperienceId: "preview",
            sourceLayer: .organization,
            themeTokens: viewModel.theme,
            allowedModules: Array(viewModel.selectedModules),
            activeBannerTitle: viewModel.title.isEmpty ? "Experience Preview" : viewModel.title,
            activeBannerSubtitle: viewModel.selectedType.displayName,
            navigationAction: nil,
            notificationBehavior: "normal",
            safetyBehavior: "standard",
            accessibilityAdjustments: [:],
            secondaryExperiences: [],
            debugMetadata: nil
        )
    }

    // MARK: - Step 4: Modules

    private var modulesStepView: some View {
        VStack(alignment: .leading, spacing: 0) {
            moduleToggles
            Divider().padding(.vertical, 12)
            safetyToggles
        }
        .padding(16)
    }

    private var moduleToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enabled Modules")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.bottom, 8)

            ForEach(ExperienceModuleType.allCases, id: \.self) { module in
                moduleToggleRow(module)
            }
        }
    }

    private func moduleToggleRow(_ module: ExperienceModuleType) -> some View {
        let isOn = viewModel.selectedModules.contains(module)
        return Button {
            HapticManager.impact(style: .light)
            if isOn {
                viewModel.selectedModules.remove(module)
            } else {
                viewModel.selectedModules.insert(module)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: module.icon)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(width: 20)
                Text(module.displayName)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isOn ? AmenTheme.Colors.buttonPrimary : AmenTheme.Colors.textSecondary
                    )
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.displayName)
        .accessibilityHint(isOn ? "Enabled, tap to disable" : "Disabled, tap to enable")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var safetyToggles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Safety Settings")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.bottom, 8)

            safetyToggleRow(
                label: "Youth Protection Mode",
                icon: "person.badge.shield.checkmark.fill",
                value: viewModel.safety.requiresYouthProtection,
                onChange: { v in
                    viewModel.safety = ExperienceSafetyConfig(
                        requiresYouthProtection: v,
                        moderationStrictness: viewModel.safety.moderationStrictness,
                        allowAnonymousPrayer: viewModel.safety.allowAnonymousPrayer,
                        requireApprovalToJoin: viewModel.safety.requireApprovalToJoin,
                        griefSensitiveMode: viewModel.safety.griefSensitiveMode
                    )
                }
            )

            safetyToggleRow(
                label: "Grief Sensitive Mode",
                icon: "heart.circle.fill",
                value: viewModel.safety.griefSensitiveMode,
                onChange: { v in
                    viewModel.safety = ExperienceSafetyConfig(
                        requiresYouthProtection: viewModel.safety.requiresYouthProtection,
                        moderationStrictness: viewModel.safety.moderationStrictness,
                        allowAnonymousPrayer: viewModel.safety.allowAnonymousPrayer,
                        requireApprovalToJoin: viewModel.safety.requireApprovalToJoin,
                        griefSensitiveMode: v
                    )
                }
            )

            safetyToggleRow(
                label: "Require Approval to Join",
                icon: "person.badge.plus.fill",
                value: viewModel.safety.requireApprovalToJoin,
                onChange: { v in
                    viewModel.safety = ExperienceSafetyConfig(
                        requiresYouthProtection: viewModel.safety.requiresYouthProtection,
                        moderationStrictness: viewModel.safety.moderationStrictness,
                        allowAnonymousPrayer: viewModel.safety.allowAnonymousPrayer,
                        requireApprovalToJoin: v,
                        griefSensitiveMode: viewModel.safety.griefSensitiveMode
                    )
                }
            )
        }
    }

    private func safetyToggleRow(
        label: String,
        icon: String,
        value: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .frame(width: 20)
            Text(label)
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: onChange))
                .labelsHidden()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value ? "On" : "Off")
        .accessibilityHint("Double-tap to toggle")
    }

    // MARK: - Step 5: Review

    private var reviewStepView: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCard

            VStack(spacing: 10) {
                Button {
                    HapticManager.impact(style: .light)
                    Task { await viewModel.save(orgId: organization.id ?? "", orgType: orgType) }
                } label: {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(AmenTheme.Colors.buttonPrimaryText)
                        }
                        Text(viewModel.isSaving ? "Saving..." : "Save as Draft")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AmenTheme.Colors.buttonPrimary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSaving)
                .accessibilityLabel("Save as draft")
                .accessibilityHint("Saves without publishing")
            }
        }
        .padding(16)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedType.icon)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text(viewModel.selectedType.displayName)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Text(viewModel.title.isEmpty ? "(no title)" : viewModel.title)
                .font(AMENFont.bold(18))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(viewModel.description.isEmpty ? "(no description)" : viewModel.description)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(3)
            Divider()
            reviewRow(
                label: "Dates",
                value: "\(viewModel.startDate.formatted(date: .abbreviated, time: .omitted)) – \(viewModel.endDate.formatted(date: .abbreviated, time: .omitted))"
            )
            reviewRow(label: "Visibility", value: viewModel.visibility.displayName)
            reviewRow(
                label: "Modules",
                value: viewModel.selectedModules.map(\.displayName).sorted().joined(separator: ", ")
            )
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.3))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private func reviewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Form field wrapper

    private func formField(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            content()
        }
    }

    // MARK: - Inline error

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmenTheme.Colors.statusError)
                .imageScale(.small)
            Text(message)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.statusError)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AmenTheme.Colors.statusError.opacity(0.10))
        )
    }

    // MARK: - Navigation bar (back/next)

    private var navigationBar: some View {
        HStack(spacing: 12) {
            if viewModel.currentStep != .type {
                Button {
                    HapticManager.impact(style: .light)
                    viewModel.back()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .imageScale(.small)
                        Text("Back")
                            .font(AMENFont.semiBold(15))
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go back to previous step")
            }

            if !viewModel.isLastStep {
                Button {
                    HapticManager.impact(style: .light)
                    viewModel.advance()
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(AMENFont.semiBold(15))
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                    .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                viewModel.canAdvance
                                    ? AmenTheme.Colors.buttonPrimary
                                    : AmenTheme.Colors.buttonPrimary.opacity(0.4)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canAdvance)
                .accessibilityLabel("Next step")
                .accessibilityHint(viewModel.canAdvance ? "Advances to the next step" : "Complete required fields first")
            }
        }
    }
}
