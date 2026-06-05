// AudienceSafetySimulatorView.swift
// AMENAPP — Camera OS
// Audience Safety Simulator: preview exactly what different audiences see before posting.
// Non-judgmental, purely informational. Helps creator make an informed choice.
//
// Design: Liquid Glass on dark/black camera context.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
//   iOS 26+:    .glassEffect() on controls

import SwiftUI

// MARK: - AudienceSafetySimulatorView

struct AudienceSafetySimulatorView: View {

    // MARK: Props

    var detectedItems: [CameraSensitiveItemType]
    var currentAudience: CameraAudiencePreset
    var onAudienceSelected: (CameraAudiencePreset) -> Void
    var onDismiss: () -> Void

    // MARK: Private state

    @State private var selectedAudience: CameraAudiencePreset

    // MARK: Layout constants

    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: - Init

    init(
        detectedItems: [CameraSensitiveItemType],
        currentAudience: CameraAudiencePreset,
        onAudienceSelected: @escaping (CameraAudiencePreset) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.detectedItems = detectedItems
        self.currentAudience = currentAudience
        self.onAudienceSelected = onAudienceSelected
        self.onDismiss = onDismiss
        _selectedAudience = State(initialValue: currentAudience)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main content
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                audienceList
                    .padding(.top, 16)

                confirmButton
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.92).ignoresSafeArea())

            // Dismiss — top-right
            dismissButton
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.black.opacity(0.88))
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audience Preview")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Tap an audience to see what they'd see")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 44)  // leave room for dismiss button
    }

    // MARK: - Audience list

    private var audienceList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(CameraAudiencePreset.allCases, id: \.rawValue) { audience in
                    AudienceRow(
                        audience: audience,
                        warnings: sensitiveItemWarnings(for: audience, items: detectedItems),
                        isSelected: selectedAudience == audience,
                        isCurrentAudience: currentAudience == audience,
                        accentColor: amberGold
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            selectedAudience = audience
                        }
                        onAudienceSelected(audience)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        Button {
            onAudienceSelected(selectedAudience)
            onDismiss()
        } label: {
            Text("Confirm Audience")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(amberGold)
                )
        }
        .accessibilityLabel("Confirm \(selectedAudience.displayName) as your audience")
        .accessibilityHint("Saves your audience selection and dismisses this screen")
    }

    // MARK: - Dismiss button

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(dismissButtonBackground)
        }
        .accessibilityLabel("Dismiss audience preview")
    }

    @ViewBuilder
    private var dismissButtonBackground: some View {
        if #available(iOS 26, *) {
            Circle().glassEffect()
        } else {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }

    // MARK: - Warning logic

    /// Returns human-readable warning strings for what this audience can see
    /// given the detected sensitive items. Empty array means no warnings.
    private func sensitiveItemWarnings(
        for audience: CameraAudiencePreset,
        items: [CameraSensitiveItemType]
    ) -> [AudienceWarning] {
        // privateOnly never surfaces sensitive items to others
        guard audience != .privateOnly else { return [] }

        var warnings: [AudienceWarning] = []

        for item in items {
            switch item {
            case .homeAddress:
                // Only public and friends audiences see home address warnings
                if audience == .public || audience == .friends {
                    warnings.append(AudienceWarning(text: "Home address visible", severity: .amber))
                }

            case .minorFace:
                switch audience {
                case .public:
                    warnings.append(AudienceWarning(text: "Minor face visible", severity: .red))
                case .friends, .church:
                    warnings.append(AudienceWarning(text: "Minor face visible", severity: .amber))
                case .family, .smallGroup, .orgMembers, .privateOnly:
                    // Protected contexts — no warning shown
                    break
                }

            case .medicalRecord:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "Medical record visible", severity: .red))
                } else if audience == .friends || audience == .church {
                    warnings.append(AudienceWarning(text: "Medical record visible", severity: .amber))
                }

            case .licensePlate:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "License plate visible", severity: .amber))
                }

            case .idDocument:
                if audience == .public || audience == .friends {
                    warnings.append(AudienceWarning(text: "ID document visible", severity: .red))
                } else if audience == .church || audience == .smallGroup || audience == .orgMembers {
                    warnings.append(AudienceWarning(text: "ID document visible", severity: .amber))
                }

            case .screenContent:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "Screen content visible", severity: .amber))
                }

            case .phoneNumber:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "Phone number visible", severity: .amber))
                } else if audience == .friends {
                    warnings.append(AudienceWarning(text: "Phone number visible", severity: .amber))
                }

            case .badge:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "Badge / credential visible", severity: .amber))
                }

            case .schoolSign, .schoolUniform:
                if audience == .public {
                    warnings.append(AudienceWarning(text: "School identifier visible", severity: .amber))
                }

            case .adultFace:
                // Adult faces in public-audience captures are informational only
                if audience == .public {
                    warnings.append(AudienceWarning(text: "Adult face visible", severity: .amber))
                }

            case .streetSign:
                // Street signs are low-risk; warn only for public + homeAddress co-occurrence
                if audience == .public && items.contains(.homeAddress) {
                    warnings.append(AudienceWarning(text: "Street location visible", severity: .amber))
                }

            case .busStop:
                // Bus stops are low-risk; only flag for public audience with minor co-occurrence
                if audience == .public && items.contains(.minorFace) {
                    warnings.append(AudienceWarning(text: "Bus stop near minor visible", severity: .amber))
                }
            }
        }

        // De-duplicate (same text can appear from multiple item types in theory)
        var seen = Set<String>()
        return warnings.filter { seen.insert($0.text).inserted }
    }

    /// Whether this audience provides safe protection for minor-related content.
    private func isProtectedAudienceForMinors(_ audience: CameraAudiencePreset) -> Bool {
        switch audience {
        case .privateOnly, .family, .smallGroup:
            return true
        default:
            return false
        }
    }
}

// MARK: - AudienceWarning model

private struct AudienceWarning: Equatable {
    enum Severity { case amber, red }
    let text: String
    let severity: Severity
}

// MARK: - AudienceRow

private struct AudienceRow: View {

    let audience: CameraAudiencePreset
    let warnings: [AudienceWarning]
    let isSelected: Bool
    let isCurrentAudience: Bool
    let accentColor: Color
    let onTap: () -> Void

    private var isProtectedForMinors: Bool {
        switch audience {
        case .privateOnly, .family, .smallGroup:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Audience icon
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: audience.systemIcon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isSelected ? accentColor : .white)
                }
                .accessibilityHidden(true)

                // Name + chips
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(audience.displayName)
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(.white)

                        Spacer()

                        // Current audience indicator
                        if isCurrentAudience {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(accentColor)
                                .accessibilityLabel("Currently selected audience")
                        }
                    }

                    // Warning chips
                    if !warnings.isEmpty {
                        FlexibleChipRow(warnings: warnings)
                    }

                    // Protected badge — shown for audiences safe for minors/private content
                    if isProtectedForMinors && !warnings.isEmpty {
                        ProtectedBadge()
                    } else if isProtectedForMinors && warnings.isEmpty {
                        // Even with no items, show Protected as reassurance
                        ProtectedBadge()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this audience")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Row background

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .glassEffect(
                        .regular.tint(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.40), lineWidth: 1.0)
                }
            }
        } else {
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .glassEffect()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                }
            }
        }
    }

    // MARK: Accessibility label

    private var accessibilityLabel: String {
        var parts = [audience.displayName]
        if isCurrentAudience { parts.append("current audience") }
        if isProtectedForMinors { parts.append("protected") }
        if warnings.isEmpty {
            parts.append("no warnings")
        } else {
            parts.append(contentsOf: warnings.map { $0.text })
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - FlexibleChipRow

/// Wrapping row of warning chips.
private struct FlexibleChipRow: View {

    let warnings: [AudienceWarning]

    var body: some View {
        // Use a simple HStack with wrapping via flexible width.
        // For >3 chips, truncate and show a count.
        let displayed = Array(warnings.prefix(3))
        let overflow = warnings.count - displayed.count

        HStack(spacing: 6) {
            ForEach(displayed.indices, id: \.self) { index in
                WarningChip(warning: displayed[index])
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(warnings.map { $0.text }.joined(separator: ", "))
    }
}

// MARK: - WarningChip

private struct WarningChip: View {

    let warning: AudienceWarning

    private var chipColor: Color {
        switch warning.severity {
        case .amber: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .red:   return Color(red: 1.0, green: 0.27, blue: 0.27)
        }
    }

    var body: some View {
        Text(warning.text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(chipColor)
            )
            .accessibilityLabel(warning.text)
    }
}

// MARK: - ProtectedBadge

private struct ProtectedBadge: View {

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                .accessibilityHidden(true)

            Text("Protected")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.18))
        )
        .accessibilityLabel("Protected audience")
    }
}

// MARK: - Preview

#Preview("Audience Safety Simulator") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AudienceSafetySimulatorView(
                detectedItems: [.minorFace, .homeAddress],
                currentAudience: .friends,
                onAudienceSelected: { audience in
                    print("Selected: \(audience.displayName)")
                },
                onDismiss: {
                    print("Dismissed")
                }
            )
        }
}

#Preview("Audience Safety Simulator — No Detections") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AudienceSafetySimulatorView(
                detectedItems: [],
                currentAudience: .public,
                onAudienceSelected: { _ in },
                onDismiss: {}
            )
        }
}
