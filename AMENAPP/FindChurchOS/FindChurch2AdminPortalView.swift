// FindChurch2AdminPortalView.swift
// AMENAPP — Find Church 2.0, Wave 5
//
// In-app admin portal for verified church claimants. Allows editing of
// profile fields, service times, beliefs schema, and review of crowd-sourced
// service-time suggestions.
//
// Access gate: church.claimState == .verified && current user == church.claimedBy
// Feature gate: findChurch2_claimPortal
//   (AMENFeatureFlags.shared.findChurch2ClaimPortalEnabled)
//
// Design rules:
//   - Glass: .ultraThinMaterial only — no nested glass
//   - Luminous border: Color.white.opacity(0.45) at 0.5pt
//   - reduceMotion guard on ALL animations
//   - Dynamic Type only — no fixed font sizes
//   - All tap targets ≥ 44×44pt
//   - No force-unwrap
//   - Async/await throughout

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - FindChurch2AdminPortalView

struct FindChurch2AdminPortalView: View {

    // Passed in from caller. We keep a mutable working copy in @State.
    let church: ChurchObject

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Editable profile state

    @State private var serviceTimes: [StructuredServiceTime]
    @State private var ministryTags: [String]
    @State private var website: String
    @State private var phone: String

    // Beliefs
    @State private var baptismView: String
    @State private var worshipStyle: String
    @State private var governance: String
    @State private var womenInMinistry: String
    @State private var communionView: String
    @State private var spiritualGifts: String
    @State private var scriptureView: String

    // UI state
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil
    @State private var saveSuccessToast: Bool = false

    // MARK: - Init

    init(church: ChurchObject) {
        self.church = church

        _serviceTimes  = State(initialValue: church.serviceTimes)
        _ministryTags  = State(initialValue: church.ministryTags)
        _website       = State(initialValue: church.website ?? "")
        _phone         = State(initialValue: church.phoneNumber ?? "")

        let b = church.beliefs
        _baptismView      = State(initialValue: b?.baptismView ?? "")
        _worshipStyle     = State(initialValue: b?.worshipStyle ?? "")
        _governance       = State(initialValue: b?.governance ?? "")
        _womenInMinistry  = State(initialValue: b?.womenInMinistry ?? "")
        _communionView    = State(initialValue: b?.communionView ?? "")
        _spiritualGifts   = State(initialValue: b?.spiritualGifts ?? "")
        _scriptureView    = State(initialValue: b?.scriptureView ?? "")
    }

    // MARK: - Access guard

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var isAuthorized: Bool {
        AMENFeatureFlags.shared.findChurch2ClaimPortalEnabled &&
        church.claimState == .verified &&
        church.claimedBy == currentUid
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            if isAuthorized {
                portalContent
                    .navigationTitle("Church Admin Portal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                                .accessibilityLabel("Close admin portal")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Button("Save") {
                                    Task { await saveProfile() }
                                }
                                .fontWeight(.semibold)
                                .accessibilityLabel("Save all changes to church profile")
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        if saveSuccessToast {
                            toastBanner
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .move(edge: .top).combined(with: .opacity)
                                )
                        }
                    }
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75),
                        value: saveSuccessToast
                    )
            } else {
                unauthorizedView
                    .navigationTitle("Admin Portal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
            }
        }
    }

    // MARK: - Portal content

    private var portalContent: some View {
        List {
            profileSection
            beliefsSection
            suggestionsSection
            announcementsSection
            premiumUpsellSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Section 1: Profile

    @ViewBuilder private var profileSection: some View {
        Section {
            // Service times
            ForEach($serviceTimes) { $time in
                ServiceTimeRow(serviceTime: $time)
            }
            .onDelete { indexSet in
                serviceTimes.remove(atOffsets: indexSet)
            }

            Button {
                let newTime = StructuredServiceTime(
                    dayOfWeek: 1,
                    startHour: 10,
                    startMinute: 0
                )
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
                    serviceTimes.append(newTime)
                }
            } label: {
                Label("Add service time", systemImage: "plus.circle.fill")
                    .font(.system(.subheadline))
                    .foregroundStyle(.tint)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a new service time")

        } header: {
            Text("Service Times")
        } footer: {
            Text("Tap a row to edit. Swipe left to remove.")
                .font(.system(.caption))
        }

        Section {
            // Ministry tags chip grid
            MinistryTagsEditor(tags: $ministryTags)
        } header: {
            Text("Ministry Focus")
        }

        Section {
            LabeledContent("Website") {
                TextField("https://yourchurch.org", text: $website)
                    .font(.system(.subheadline))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Church website URL")

            LabeledContent("Phone") {
                TextField("(555) 000-0000", text: $phone)
                    .font(.system(.subheadline))
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Church phone number")

            // Logo update hint — not an upload
            HStack(spacing: 10) {
                Image(systemName: "photo.circle")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Church logo")
                        .font(.system(.subheadline))
                    Text("Contact support to update your logo")
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Church logo — contact support to update")

        } header: {
            Text("Contact & Links")
        }
    }

    // MARK: - Section 2: Beliefs

    private var beliefsSection: some View {
        Section {
            beliefPicker(
                label: "Baptism",
                selection: $baptismView,
                options: ["", "Believer's baptism", "Infant baptism", "No preference"],
                accessibilityLabel: "Baptism view"
            )
            beliefPicker(
                label: "Worship style",
                selection: $worshipStyle,
                options: ["", "Traditional", "Contemporary", "Blended", "Liturgical"],
                accessibilityLabel: "Worship style"
            )
            beliefPicker(
                label: "Governance",
                selection: $governance,
                options: ["", "Congregational", "Episcopal", "Presbyterian"],
                accessibilityLabel: "Church governance model"
            )
            beliefPicker(
                label: "Women in ministry",
                selection: $womenInMinistry,
                options: ["", "Egalitarian", "Complementarian", "Varies"],
                accessibilityLabel: "Women in ministry view"
            )
            beliefPicker(
                label: "Communion",
                selection: $communionView,
                options: ["", "Memorial", "Real presence", "Transubstantiation"],
                accessibilityLabel: "Communion view"
            )
            beliefPicker(
                label: "Spiritual gifts",
                selection: $spiritualGifts,
                options: ["", "Cessationist", "Continuationist", "Open"],
                accessibilityLabel: "Spiritual gifts view"
            )
            beliefPicker(
                label: "Scripture",
                selection: $scriptureView,
                options: ["", "Inerrancy", "Infallibility", "Inspired"],
                accessibilityLabel: "Scripture view"
            )

        } header: {
            Text("Beliefs")
        } footer: {
            Text("Beliefs are set by verified claimants only and help seekers find a good theological fit.")
                .font(.system(.caption))
        }
    }

    @ViewBuilder
    private func beliefPicker(
        label: String,
        selection: Binding<String>,
        options: [String],
        accessibilityLabel: String
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option.isEmpty ? "Not specified" : option)
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
        .font(.system(.subheadline))
        .frame(minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Section 3: Suggestions queue

    private var suggestionsSection: some View {
        Section {
            ForEach(stubbedSuggestions, id: \.id) { suggestion in
                FC2SuggestionRow(suggestion: suggestion)
            }
        } header: {
            Text("Service Time Suggestions")
        } footer: {
            Text("These are crowd-sourced suggestions from your congregation. Approving a suggestion adds it to your official service times.")
                .font(.system(.caption))
        }
    }

    private var stubbedSuggestions: [ServiceTimeSuggestion] {
        [
            ServiceTimeSuggestion(
                id: "stub-1",
                proposedDayOfWeek: 1,
                proposedStartHour: 8,
                proposedStartMinute: 0,
                serviceType: "Early Service",
                submittedBy: "Member",
                submittedAt: Date().addingTimeInterval(-86400)
            ),
            ServiceTimeSuggestion(
                id: "stub-2",
                proposedDayOfWeek: 4,
                proposedStartHour: 19,
                proposedStartMinute: 0,
                serviceType: "Midweek Study",
                submittedBy: "Member",
                submittedAt: Date().addingTimeInterval(-172800)
            ),
            ServiceTimeSuggestion(
                id: "stub-3",
                proposedDayOfWeek: 1,
                proposedStartHour: 17,
                proposedStartMinute: 30,
                serviceType: "Evening Service",
                submittedBy: "Member",
                submittedAt: Date().addingTimeInterval(-259200)
            )
        ]
    }

    // MARK: - Section 4: Announcements (stub)

    private var announcementsSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "megaphone.fill")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Coming soon — post announcements to your congregation")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Announcements — post updates to your congregation; coming in a future release")
        } header: {
            Text("Announcements")
        }
    }

    // MARK: - Section 5: Premium upsell (scaffold, not tappable)

    private var premiumUpsellSection: some View {
        Section {
            ZStack {
                // Content beneath dimming overlay
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(.title3))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analytics Dashboard")
                                .font(.system(.subheadline).weight(.semibold))
                            Text("See how seekers are finding your profile")
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)

                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(.title3))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Promoted Placement")
                                .font(.system(.subheadline).weight(.semibold))
                            Text("Appear at the top of nearby search results")
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)

                    HStack(spacing: 10) {
                        Image(systemName: "person.wave.2.fill")
                            .font(.system(.title3))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Visitor Funnels")
                                .font(.system(.subheadline).weight(.semibold))
                            Text("Track first-time visitor engagement")
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .padding(.vertical, 4)

                // Semi-transparent "coming soon" overlay — not tappable
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.55))
                    .overlay(
                        Text("Coming Soon")
                            .font(.system(.caption).weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                    )
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Amen Church Pro features: analytics, promoted placement, and visitor funnels — available in Amen Church Pro subscription")

        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Amen Church Pro")
                    .textCase(nil)
                    .font(.system(.subheadline).weight(.semibold))
                Text("Analytics · Promoted placement · Visitor funnels")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    // MARK: - Toast banner

    private var toastBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.subheadline))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Profile saved")
                .font(.system(.subheadline).weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                )
        )
        .padding(.top, 8)
        .accessibilityLabel("Profile saved successfully")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Save profile

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        let updatedBeliefs = BeliefSchema(
            baptismView:     baptismView.isEmpty ? nil : baptismView,
            communionView:   communionView.isEmpty ? nil : communionView,
            governance:      governance.isEmpty ? nil : governance,
            worshipStyle:    worshipStyle.isEmpty ? nil : worshipStyle,
            spiritualGifts:  spiritualGifts.isEmpty ? nil : spiritualGifts,
            womenInMinistry: womenInMinistry.isEmpty ? nil : womenInMinistry,
            scriptureView:   scriptureView.isEmpty ? nil : scriptureView,
            customTags:      church.beliefs?.customTags ?? []
        )

        // Build a partial update dictionary from mutable fields only.
        // We use Firestore.Encoder for the complex nested types.
        do {
            let db = Firestore.firestore()
            let docRef = db.collection("churches").document(church.id)

            let encoder = Firestore.Encoder()

            let encodedServiceTimes = try serviceTimes.map { try encoder.encode($0) }
            let encodedBeliefs = try encoder.encode(updatedBeliefs)

            let updateData: [String: Any] = [
                "serviceTimes":  encodedServiceTimes,
                "ministryTags":  ministryTags,
                "website":       website.trimmingCharacters(in: .whitespaces),
                "phoneNumber":   phone.trimmingCharacters(in: .whitespaces),
                "beliefs":       encodedBeliefs,
                "updatedAt":     Timestamp(date: Date())
            ]

            try await docRef.setData(updateData, merge: true)

            saveError = nil
            saveSuccessToast = true

            // Auto-dismiss the toast after 2.5 s
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            saveSuccessToast = false

        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Unauthorized view

    private var unauthorizedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Access Restricted")
                .font(.system(.title2).weight(.semibold))
            Text("This portal is only accessible to verified church representatives.")
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Access restricted. This portal is only accessible to verified church representatives.")
    }
}

// MARK: - ServiceTimeRow

/// Inline editable row for a single StructuredServiceTime.
/// Because all StructuredServiceTime fields are `let`, we shadow them in
/// local @State and write a new value back to the binding on any change.
private struct ServiceTimeRow: View {

    @Binding var serviceTime: StructuredServiceTime

    @State private var selectedDay: Int
    @State private var selectedHour: Int
    @State private var selectedMinute: Int

    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let dayNumbers = [1, 2, 3, 4, 5, 6, 7]

    init(serviceTime: Binding<StructuredServiceTime>) {
        _serviceTime    = serviceTime
        _selectedDay    = State(initialValue: serviceTime.wrappedValue.dayOfWeek)
        _selectedHour   = State(initialValue: serviceTime.wrappedValue.startHour)
        _selectedMinute = State(initialValue: serviceTime.wrappedValue.startMinute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Day", selection: $selectedDay) {
                    ForEach(Array(zip(days, dayNumbers)), id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 80, minHeight: 44)
                .accessibilityLabel("Day of week for this service time")
                .onChange(of: selectedDay) { _ in commitChange() }

                Picker("Hour", selection: $selectedHour) {
                    ForEach(0..<24, id: \.self) { h in
                        let h12 = h % 12 == 0 ? 12 : h % 12
                        let ampm = h < 12 ? "AM" : "PM"
                        Text(String(format: "%d %@", h12, ampm)).tag(h)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityLabel("Hour for this service time")
                .onChange(of: selectedHour) { _ in commitChange() }

                Picker("Minute", selection: $selectedMinute) {
                    Text(":00").tag(0)
                    Text(":15").tag(15)
                    Text(":30").tag(30)
                    Text(":45").tag(45)
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityLabel("Minute for this service time")
                .onChange(of: selectedMinute) { _ in commitChange() }
            }

            if let type = serviceTime.serviceType, !type.isEmpty {
                Text(type)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func commitChange() {
        serviceTime = StructuredServiceTime(
            id: serviceTime.id,
            dayOfWeek: selectedDay,
            startHour: selectedHour,
            startMinute: selectedMinute,
            durationMinutes: serviceTime.durationMinutes,
            timezone: serviceTime.timezone,
            serviceType: serviceTime.serviceType,
            isRecurring: serviceTime.isRecurring,
            languages: serviceTime.languages,
            isAccessibleASL: serviceTime.isAccessibleASL,
            isAccessibleWheelchair: serviceTime.isAccessibleWheelchair
        )
    }
}

// MARK: - MinistryTagsEditor

/// Chip grid for toggling ministry tags on/off.
private struct MinistryTagsEditor: View {

    @Binding var tags: [String]

    private let allTags = [
        "youth", "women", "men", "recovery", "worship",
        "prayer", "Spanish", "families", "seniors",
        "college", "missions", "discipleship", "care"
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        FC2AdminFlowLayout(spacing: 8) {
            ForEach(allTags, id: \.self) { tag in
                tagChip(tag)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tagChip(_ tag: String) -> some View {
        let isOn = tags.contains(tag)

        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                if isOn {
                    tags.removeAll { $0 == tag }
                } else {
                    tags.append(tag)
                }
            }
        } label: {
            Text(tag.capitalized)
                .font(.system(.caption).weight(.medium))
                .foregroundStyle(isOn ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(chipBackground(isOn: isOn))
                .overlay(chipBorder(isOn: isOn))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag)
        .accessibilityValue(isOn ? "selected" : "not selected")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    @ViewBuilder
    private func chipBackground(isOn: Bool) -> some View {
        if isOn {
            Capsule(style: .continuous).fill(Color.accentColor)
        } else if reduceTransparency {
            Capsule(style: .continuous).fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        }
    }

    private func chipBorder(isOn: Bool) -> some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isOn ? Color.clear : Color.white.opacity(0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - FlowLayout

/// Wrapping horizontal chip layout — no fixed frame sizes.
private struct FC2AdminFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .init(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        _ = maxWidth // suppress unused warning
    }
}

// MARK: - ServiceTimeSuggestion (local stub model)

/// Crowd-sourced service time suggestion submitted by a congregation member.
/// Full model lives in the backend; client uses this struct for display only.
private struct ServiceTimeSuggestion {
    let id: String
    let proposedDayOfWeek: Int
    let proposedStartHour: Int
    let proposedStartMinute: Int
    let serviceType: String?
    let submittedBy: String
    let submittedAt: Date

    private static let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var displayDay: String {
        guard proposedDayOfWeek >= 1, proposedDayOfWeek <= 7 else { return "" }
        return Self.dayNames[proposedDayOfWeek]
    }

    var displayTime: String {
        let h12 = proposedStartHour % 12 == 0 ? 12 : proposedStartHour % 12
        let ampm = proposedStartHour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, proposedStartMinute, ampm)
    }
}

// MARK: - SuggestionRow

private struct FC2SuggestionRow: View {

    let suggestion: ServiceTimeSuggestion

    @State private var isApproved: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(suggestion.displayDay) at \(suggestion.displayTime)")
                    .font(.system(.subheadline).weight(.medium))
                if let type = suggestion.serviceType {
                    Text(type)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
                Text("Suggested by a congregation member")
                    .font(.system(.caption2))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let approved = isApproved {
                Image(systemName: approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(.title3))
                    .foregroundStyle(approved ? .green : .red)
                    .accessibilityLabel(approved ? "Approved" : "Rejected")
            } else {
                HStack(spacing: 8) {
                    Button {
                        withAnimation { isApproved = false }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(.title3))
                            .foregroundStyle(.red)
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reject suggestion: \(suggestion.displayDay) at \(suggestion.displayTime)")

                    Button {
                        withAnimation { isApproved = true }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(.title3))
                            .foregroundStyle(.green)
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Approve suggestion: \(suggestion.displayDay) at \(suggestion.displayTime)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

#if DEBUG
private let _adminPreviewChurch = ChurchObject(
    id: "admin-preview-1",
    placeId: nil,
    ein: nil,
    name: "Grace Community Church",
    normalizedName: "grace community church",
    address: "123 Faith Ave",
    normalizedAddress: "123 faith ave",
    city: "Nashville",
    state: "TN",
    zipCode: "37201",
    country: "US",
    coordinate: .init(latitude: 36.162, longitude: -86.781),
    phoneNumber: "(615) 555-0123",
    email: "hello@gracenash.org",
    website: "https://gracenash.org",
    photoURL: nil,
    logoURL: nil,
    denomination: "Non-denominational",
    denominationFamily: nil,
    denominationIsFlexible: true,
    denominationLineage: [],
    beliefs: BeliefSchema(
        baptismView: "Believer's baptism",
        communionView: "Memorial",
        governance: "Congregational",
        worshipStyle: "Contemporary",
        spiritualGifts: "Continuationist",
        womenInMinistry: "Egalitarian",
        scriptureView: "Inerrancy",
        customTags: []
    ),
    serviceTimes: [
        StructuredServiceTime(dayOfWeek: 1, startHour: 9, startMinute: 0, serviceType: "First Service"),
        StructuredServiceTime(dayOfWeek: 1, startHour: 11, startMinute: 0, serviceType: "Main Service")
    ],
    mediaLinks: .init(detectedMediaType: .youtube),
    accessibility: .init(),
    claimState: .verified,
    verificationTier: .domain,
    claimedBy: Auth.auth().currentUser?.uid ?? "preview-uid",
    claimedAt: Date(),
    childSafetyPolicy: .init(),
    staffCount: 12,
    ministryTags: ["youth", "women", "worship"],
    gatheringIds: [],
    availabilityCache: nil,
    availabilityCachedAt: nil,
    pendingServiceTimeSuggestions: 3,
    amenMemberCount: 142,
    visitCount: 48,
    friendSavedCount: 3,
    source: .googlePlaces,
    createdAt: Date(),
    updatedAt: Date(),
    isDeleted: false
)

#Preview("Admin portal") {
    FindChurch2AdminPortalView(church: _adminPreviewChurch)
}
#endif
