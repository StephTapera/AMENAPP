// AegisWellbeingView.swift
// Aegis — Wellbeing Controls (C47–C50)
// Capabilities: hiddenPublicMetrics, antiRageAmplification, antiDoomscroll, memoryResurfacing

import SwiftUI

struct AegisWellbeingView: View {
    @StateObject private var service = AegisWellbeingService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showDatePicker = false
    @State private var newMuteDate = Date()

    private let flags = AegisFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hiddenMetricsCard
                    antiRageCard
                    scrollGuardCard
                    memoryControlsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wellbeing")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - C47 Hidden Metrics

    private var hiddenMetricsCard: some View {
        let enabled = flags.isEnabled(.hiddenPublicMetrics)
        return glassCard(capability: .hiddenPublicMetrics, enabled: enabled) {
            VStack(alignment: .leading, spacing: 10) {
                toggleRow(
                    title: "Hide public likes and view counts",
                    caption: "Research shows hidden metrics reduce anxiety and comparison.",
                    isOn: Binding(
                        get: { service.state.hiddenMetrics },
                        set: { val in
                            service.state.hiddenMetrics = val
                            Task { await service.saveState() }
                        }
                    ),
                    enabled: enabled
                )
            }
        }
    }

    // MARK: - C48 Anti-Rage Filter

    private var antiRageCard: some View {
        let enabled = flags.isEnabled(.antiRageAmplification)
        return glassCard(capability: .antiRageAmplification, enabled: enabled) {
            toggleRow(
                title: "Filter inflammatory content",
                caption: "Reduces outrage-driven posts in your feed.",
                isOn: Binding(
                    get: { service.state.antiRageEnabled },
                    set: { val in
                        service.state.antiRageEnabled = val
                        Task { await service.saveState() }
                    }
                ),
                enabled: enabled
            )
        }
    }

    // MARK: - C49 Scroll Guard

    private var scrollGuardCard: some View {
        let enabled = flags.isEnabled(.antiDoomscroll)
        return glassCard(capability: .antiDoomscroll, enabled: enabled) {
            VStack(alignment: .leading, spacing: 12) {
                toggleRow(
                    title: "Gentle reminders when you've been scrolling a while",
                    caption: "A nudge when your scroll session gets long.",
                    isOn: Binding(
                        get: { service.state.doomscrollGuardEnabled },
                        set: { val in
                            service.state.doomscrollGuardEnabled = val
                            Task { await service.saveState() }
                        }
                    ),
                    enabled: enabled
                )

                if service.state.doomscrollGuardEnabled && enabled {
                    Divider()
                        .padding(.leading, 4)

                    toggleRow(
                        title: "Extra quiet time reminder between 1–4am",
                        caption: nil,
                        isOn: Binding(
                            get: { service.state.lateNightFrictionEnabled },
                            set: { val in
                                service.state.lateNightFrictionEnabled = val
                                Task { await service.saveState() }
                            }
                        ),
                        enabled: enabled,
                        isSubToggle: true
                    )
                }
            }
        }
    }

    // MARK: - C50 Memory Controls

    private var memoryControlsCard: some View {
        let enabled = flags.isEnabled(.memoryResurfacing)
        return glassCard(capability: .memoryResurfacing, enabled: enabled) {
            VStack(alignment: .leading, spacing: 14) {
                toggleRow(
                    title: "Mute certain dates or people from 'On this day' memories",
                    caption: nil,
                    isOn: Binding(
                        get: { service.state.memoryControlsEnabled },
                        set: { val in
                            service.state.memoryControlsEnabled = val
                            Task { await service.saveState() }
                        }
                    ),
                    enabled: enabled
                )

                if service.state.memoryControlsEnabled && enabled {
                    Divider()

                    // Muted Dates Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Muted Dates")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)

                        if service.state.mutedDates.isEmpty {
                            Text("No dates muted yet.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(service.state.mutedDates, id: \.self) { dateStr in
                                HStack {
                                    Text(dateStr)
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Button {
                                        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                                            service.state.mutedDates.removeAll { $0 == dateStr }
                                            Task { await service.saveState() }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityLabel("Remove \(dateStr) from muted dates")
                                }
                            }
                        }

                        // Add date
                        if showDatePicker {
                            VStack(alignment: .leading, spacing: 8) {
                                DatePicker(
                                    "Select date to mute",
                                    selection: $newMuteDate,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()

                                Button {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "MM-dd"
                                    let str = formatter.string(from: newMuteDate)
                                    withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                                        if !service.state.mutedDates.contains(str) {
                                            service.muteDate(str)
                                        }
                                        showDatePicker = false
                                    }
                                } label: {
                                    Text("Add Date")
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(Color.amenGold)
                                }
                                .accessibilityLabel("Confirm muting selected date")
                            }
                            .padding(.top, 4)
                        } else {
                            Button {
                                withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                                    showDatePicker = true
                                }
                            } label: {
                                Label("Add a date", systemImage: "plus.circle")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(Color.amenGold)
                            }
                            .accessibilityLabel("Add a date to mute from memories")
                        }
                    }

                    Divider()

                    // Muted Users Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Muted People")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.secondary)

                        if service.state.mutedUserIds.isEmpty {
                            Text("No people muted from memories yet.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(service.state.mutedUserIds, id: \.self) { userId in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                    Text(userId)
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.8)) {
                                            service.state.mutedUserIds.removeAll { $0 == userId }
                                            Task { await service.saveState() }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityLabel("Remove person from muted memories")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reusable Toggle Row

    @ViewBuilder
    private func toggleRow(
        title: String,
        caption: String?,
        isOn: Binding<Bool>,
        enabled: Bool,
        isSubToggle: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(isSubToggle ? AMENFont.regular(14) : AMENFont.semiBold(15))
                        .foregroundStyle(enabled ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let caption {
                        Text(caption)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if enabled {
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                        .tint(Color.amenGold)
                        .accessibilityLabel(title)
                } else {
                    comingSoonBadge()
                }
            }
        }
    }

    // MARK: - Glass Card Container

    @ViewBuilder
    private func glassCard<Content: View>(
        capability: AegisCapability,
        enabled: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                capabilityBadge(capability)
                Spacer()
                if !enabled {
                    comingSoonBadge()
                }
            }
            .padding(.bottom, 10)

            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .opacity(enabled ? 1 : 0.6)
    }

    @ViewBuilder
    private func capabilityBadge(_ capability: AegisCapability) -> some View {
        Text(capability.displayName)
            .font(AMENFont.semiBold(11))
            .foregroundStyle(Color.amenPurple)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.amenPurple.opacity(0.12))
            )
    }

    @ViewBuilder
    private func comingSoonBadge() -> some View {
        Text("Coming soon")
            .font(AMENFont.regular(11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(.systemFill))
            )
            .accessibilityLabel("Coming soon")
    }
}

#if DEBUG
#Preview {
    AegisWellbeingView()
}
#endif
