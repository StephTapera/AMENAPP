// FindChurch2VisitPlannerView.swift
// AMENAPP — Find Church 2.0 — Visit Planner (Wave 4 UI)
//
// Design rules enforced:
//   • .ultraThinMaterial only — no nested materials
//   • Luminous border: Color.white.opacity(0.45) strokeBorder 0.5 pt
//   • @Environment(\.accessibilityReduceMotion) guards all animations
//   • Dynamic Type text styles throughout — no fixed sizes
//   • All tap targets ≥ 44×44 pt
//   • Feature-gated: returns EmptyView when findChurch2VisitPlannerEnabled == false
//
// Depends on:
//   FindChurch2Contracts.swift  — ChurchObject, StructuredServiceTime,
//                                 AvailabilityStatus, SeekerProfile
//   FirstVisitCompanionModels.swift — VisitPlan, VisitPlanStatus
//   AMENFeatureFlags.swift      — findChurch2VisitPlannerEnabled

import SwiftUI

// MARK: - FindChurch2VisitPlannerView

struct FindChurch2VisitPlannerView: View {

    // MARK: Interface

    let church: ChurchObject
    let availability: AvailabilityStatus
    let comfortPrefs: [SeekerProfile.ComfortChip]

    // MARK: State

    @State private var selectedTime: StructuredServiceTime?
    @State private var isPlanning: Bool = false
    @State private var isPlanned: Bool = false
    @State private var planError: String?
    @State private var showSuggestTimesSheet: Bool = false

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Feature gate

    @ObservedObject private var flags = AMENFeatureFlags.shared

    // MARK: Body

    var body: some View {
        if !flags.findChurch2VisitPlannerEnabled {
            EmptyView()
        } else {
            plannerContent
        }
    }

    // MARK: - Planner Content

    @ViewBuilder
    private var plannerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                churchHeader

                Divider()
                    .padding(.horizontal, 4)

                serviceTimesSection

                WhatToExpectSection(church: church, comfortPrefs: comfortPrefs)

                visitCTA

                if let errorMessage = planError {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                // Bottom breathing room
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .sheet(isPresented: $showSuggestTimesSheet) {
            SuggestTimesSheet(churchName: church.name)
        }
    }

    // MARK: - Church Header

    private var churchHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(church.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(church.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Service Times Section

    @ViewBuilder
    private var serviceTimesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Times")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            if church.serviceTimes.isEmpty {
                // No times — crowdsource prompt
                emptyServiceTimesPrompt
            } else {
                // Scrollable list of selectable service time rows
                VStack(spacing: 8) {
                    ForEach(church.serviceTimes) { serviceTime in
                        ServiceTimeRow(
                            serviceTime: serviceTime,
                            isSelected: selectedTime?.id == serviceTime.id,
                            reduceMotion: reduceMotion,
                            reduceTransparency: reduceTransparency
                        ) {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82)) {
                                if selectedTime?.id == serviceTime.id {
                                    selectedTime = nil
                                } else {
                                    selectedTime = serviceTime
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyServiceTimesPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service times unknown — help us fill this in")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showSuggestTimesSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.plus")
                        .accessibilityHidden(true)
                    Text("Suggest times")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 16)
                .background {
                    if reduceTransparency {
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground))
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Suggest service times for \(church.name)")
        }
    }

    // MARK: - Visit CTA

    @ViewBuilder
    private var visitCTA: some View {
        if isPlanned {
            alreadyPlannedState
        } else {
            planVisitButton
        }
    }

    private var planVisitButton: some View {
        Button {
            Task { await performPlanVisit() }
        } label: {
            ZStack {
                // Gold fill CTA
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.70, blue: 0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    }

                HStack(spacing: 8) {
                    if isPlanning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(0.85)
                            .accessibilityLabel("Planning your visit")
                    } else {
                        Image(systemName: "calendar.badge.plus")
                            .accessibilityHidden(true)
                    }
                    Text(isPlanning ? "Planning…" : "I'm going this Sunday")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .disabled(isPlanning)
        .opacity(isPlanning ? 0.7 : 1)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: isPlanning)
        .accessibilityLabel(isPlanning ? "Planning your visit" : "I'm going this Sunday")
        .accessibilityHint("Tap to commit to visiting \(church.name)")
    }

    private var alreadyPlannedState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.20, green: 0.65, blue: 0.35))
                    .accessibilityHidden(true)
                Text("You're going!")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.65, blue: 0.35))
            }
            .accessibilityLabel("You're going to \(church.name)")

            Button {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                    isPlanned = false
                }
            } label: {
                Text("Need to cancel?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .underline()
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel visit to \(church.name)")
        }
    }

    // MARK: - Actions

    private func performPlanVisit() async {
        guard !isPlanning else { return }
        planError = nil

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
            isPlanning = true
        }

        defer {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                isPlanning = false
            }
        }

        do {
            _ = try await FindChurch2VisitPlannerService.shared.planVisit(
                to: church,
                serviceTime: selectedTime,
                comfortPrefs: comfortPrefs
            )
            withAnimation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.80)) {
                isPlanned = true
            }
        } catch {
            planError = "Couldn't save your plan. Please try again."
        }
    }
}

// MARK: - ServiceTimeRow

private struct ServiceTimeRow: View {

    let serviceTime: StructuredServiceTime
    let isSelected: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let action: () -> Void

    private var dayName: String {
        let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard serviceTime.dayOfWeek >= 1 && serviceTime.dayOfWeek <= 7 else { return "Day" }
        return days[serviceTime.dayOfWeek]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Day + time
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(dayName)
                            .font(.subheadline.weight(.semibold))
                        Text(serviceTime.displayTime)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let type = serviceTime.serviceType {
                        Text(type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Accessibility badges
                HStack(spacing: 6) {
                    if serviceTime.isAccessibleASL {
                        accessibilityBadge(symbol: "hands.sparkles", label: "ASL available")
                    }
                    if serviceTime.isAccessibleWheelchair {
                        accessibilityBadge(symbol: "figure.roll", label: "Wheelchair accessible")
                    }
                }

                // Selection checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(red: 0.85, green: 0.70, blue: 0.20) : .secondary)
                    .font(.body)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.85, green: 0.70, blue: 0.20).opacity(0.10))
                            }
                        }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color(red: 0.85, green: 0.70, blue: 0.20).opacity(0.60)
                            : Color.white.opacity(0.45),
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            }
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dayName), \(serviceTime.displayTime)\(serviceTime.serviceType.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Selected. Tap to deselect." : "Tap to select this service time.")
    }

    private func accessibilityBadge(symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }
}

// MARK: - WhatToExpectSection

struct WhatToExpectSection: View {

    let church: ChurchObject
    let comfortPrefs: [SeekerProfile.ComfortChip]

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What to expect")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                // Parking
                expectRow(
                    icon: "car.fill",
                    label: "Parking",
                    value: church.accessibility.parkingNotes ?? "Not provided"
                )

                rowDivider

                // Entrance
                expectRow(
                    icon: "door.left.hand.open",
                    label: "Entrance",
                    value: church.accessibility.entranceNotes ?? "Not provided"
                )

                rowDivider

                // Childcare
                expectRow(
                    icon: "figure.2.and.child.holdinghands",
                    label: "Childcare",
                    value: church.accessibility.hasChildcare ? "Available" : "Not provided",
                    isBadge: church.accessibility.hasChildcare
                )

                rowDivider

                // ASL
                expectRow(
                    icon: "hands.sparkles",
                    label: "ASL Interpretation",
                    value: church.accessibility.hasASL ? "Available" : "Not provided",
                    isBadge: church.accessibility.hasASL
                )

                rowDivider

                // Worship style
                expectRow(
                    icon: "music.note",
                    label: "Worship style",
                    value: church.beliefs?.worshipStyle?.capitalized ?? "Not provided"
                )

                rowDivider

                // Dress
                expectRow(
                    icon: "tshirt",
                    label: "Dress",
                    value: "Come as you are"
                )
            }
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 44)
    }

    private func expectRow(icon: String,
                           label: String,
                           value: String,
                           isBadge: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if isBadge {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.20, green: 0.55, blue: 0.35))
                    }
                    .accessibilityLabel("\(label): \(value)")
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(value == "Not provided" ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("\(label): \(value)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }
}

// MARK: - SuggestTimesSheet

private struct SuggestTimesSheet: View {

    let churchName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Suggest service times for \(churchName) to help others planning a visit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // TODO(gate: HUMAN-MACHINE) — wave5: CF-backed suggestion form; submitServiceTimeSuggestion callable not yet deployed
                Text("Service time suggestions are coming soon.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Suggest Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Close suggest times sheet")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Visit Planner — With Times") {
    let church = ChurchObject(
        id: "preview-1",
        placeId: nil,
        ein: nil,
        name: "Grace Fellowship Church",
        normalizedName: "grace fellowship church",
        address: "123 Main St, Phoenix, AZ 85001",
        normalizedAddress: "123 main st phoenix az 85001",
        city: "Phoenix",
        state: "AZ",
        zipCode: "85001",
        country: "US",
        coordinate: .init(latitude: 33.4484, longitude: -112.0740),
        phoneNumber: "(602) 555-0100",
        email: nil,
        website: "https://gracefellowship.example.com",
        photoURL: nil,
        logoURL: nil,
        denomination: "Southern Baptist Convention",
        denominationFamily: "Baptist",
        denominationIsFlexible: false,
        denominationLineage: ["Protestant", "Evangelical", "Baptist", "SBC"],
        beliefs: BeliefSchema(
            baptismView: "believer's baptism",
            communionView: "memorial",
            governance: "congregational",
            worshipStyle: "contemporary",
            spiritualGifts: nil,
            womenInMinistry: nil,
            scriptureView: "inerrancy",
            customTags: []
        ),
        serviceTimes: [
            StructuredServiceTime(
                dayOfWeek: 1,
                startHour: 9,
                startMinute: 0,
                durationMinutes: 75,
                serviceType: "First Service",
                isAccessibleASL: true,
                isAccessibleWheelchair: true
            ),
            StructuredServiceTime(
                dayOfWeek: 1,
                startHour: 11,
                startMinute: 0,
                durationMinutes: 75,
                serviceType: "Main Service",
                isAccessibleASL: false,
                isAccessibleWheelchair: true
            )
        ],
        mediaLinks: MediaLinks(),
        accessibility: AccessibilityInfo(
            hasASL: true,
            isWheelchairAccessible: true,
            languages: ["en"],
            hasChildcare: true,
            parkingNotes: "Free parking in front and side lots",
            entranceNotes: "Main entrance on Main St, accessible ramp on south side"
        ),
        claimState: .verified,
        verificationTier: .domain,
        claimedBy: nil,
        claimedAt: nil,
        childSafetyPolicy: ChildSafetyPolicy(
            hasFormalPolicy: true,
            backgroundChecksRequired: true,
            policyURL: nil
        ),
        staffCount: 12,
        ministryTags: ["youth", "women", "worship"],
        gatheringIds: [],
        availabilityCache: nil,
        availabilityCachedAt: nil,
        pendingServiceTimeSuggestions: 0,
        amenMemberCount: 42,
        visitCount: 180,
        friendSavedCount: 3,
        source: .googlePlaces,
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false
    )

    FindChurch2VisitPlannerView(
        church: church,
        availability: .compute(from: church.serviceTimes),
        comfortPrefs: [.showParking, .showWhatToExpect, .needChildcare]
    )
}

#Preview("Visit Planner — No Times") {
    let church = ChurchObject(
        id: "preview-2",
        placeId: nil,
        ein: nil,
        name: "New Life Community Church",
        normalizedName: "new life community church",
        address: "456 Oak Ave, Tempe, AZ 85281",
        normalizedAddress: "456 oak ave tempe az 85281",
        city: "Tempe",
        state: "AZ",
        zipCode: "85281",
        country: "US",
        coordinate: .init(latitude: 33.4255, longitude: -111.9400),
        phoneNumber: nil,
        email: nil,
        website: nil,
        photoURL: nil,
        logoURL: nil,
        denomination: nil,
        denominationFamily: nil,
        denominationIsFlexible: true,
        denominationLineage: [],
        beliefs: nil,
        serviceTimes: [],
        mediaLinks: MediaLinks(),
        accessibility: AccessibilityInfo(),
        claimState: .unclaimed,
        verificationTier: .none,
        claimedBy: nil,
        claimedAt: nil,
        childSafetyPolicy: ChildSafetyPolicy(),
        staffCount: nil,
        ministryTags: [],
        gatheringIds: [],
        availabilityCache: nil,
        availabilityCachedAt: nil,
        pendingServiceTimeSuggestions: 0,
        amenMemberCount: 5,
        visitCount: 12,
        friendSavedCount: 0,
        source: .userSubmitted,
        createdAt: Date(),
        updatedAt: Date(),
        isDeleted: false
    )

    FindChurch2VisitPlannerView(
        church: church,
        availability: .unknown,
        comfortPrefs: []
    )
}
#endif
