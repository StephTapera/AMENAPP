// AmenGatheringDetailView.swift
// AMENAPP — Gathering Detail / Event Page
//
// Hero, RSVP actions, spiritual section, community, safety disclosures.
// Privacy: prayer requests and pastoral follow-up are hosts-only by default.

import SwiftUI

struct AmenGatheringDetailView: View {
    let gathering: AmenGathering

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var userRsvpStatus: AmenGatheringRsvpStatus?
    @State private var isSubmittingRsvp = false
    @State private var showRsvpError: String?
    @State private var showPrayerRequestSheet = false
    @State private var showGuestList = false
    @State private var showShareSheet = false
    @State private var showHostConsole = false
    @State private var showAddToCalendar = false
    @State private var showSafetyInfo = false

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    contentSection
                }
                .padding(.bottom, 80)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .sheet(isPresented: $showPrayerRequestSheet) {
                AmenGatheringPrayerRequestView(gatheringId: gathering.gatheringId, gatheringTitle: gathering.title)
            }
            .sheet(isPresented: $showGuestList) {
                AmenGatheringGuestListView(gathering: gathering)
            }
            .sheet(isPresented: $showShareSheet) {
                AmenGatheringShareSheet(gathering: gathering)
            }
            .sheet(isPresented: $showHostConsole) {
                AmenGatheringHostConsoleView(gathering: gathering)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroCover
            heroGradient
            heroInfo
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    @ViewBuilder
    private var heroCover: some View {
        if let url = gathering.theme.coverImageUrl {
            CachedAsyncImage(url: URL(string: url), size: CGSize(width: 1200, height: 800)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                gradientCover
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            gradientCover
        }
    }

    private var gradientCover: some View {
        ZStack {
            AmenTheme.Colors.backgroundSecondary
            Image(systemName: gathering.type.systemImage)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.secondary)
        }
    }

    private var heroGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.6)],
            startPoint: .center,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: gathering.type.systemImage)
                    .font(.caption.weight(.medium))
                Text(gathering.type.displayName)
                    .font(.caption.weight(.semibold))
                if gathering.hostVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Verified host")
                }
            }
            .foregroundStyle(.white.opacity(0.9))

            Text(gathering.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4)

            HStack(spacing: 12) {
                Label(gathering.startAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                Label(gathering.location.displaySummary,
                      systemImage: gathering.location.type.systemImage)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            rsvpBar
            divider
            detailsSection
            divider
            spiritualSection
            if flags.gatheringGuestListEnabled {
                divider
                communitySection
            }
            divider
            safetySection
        }
    }

    // MARK: - RSVP Bar

    private var rsvpBar: some View {
        VStack(spacing: 12) {
            if gathering.status == .cancelled {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("This gathering has been cancelled.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                rsvpButtons
            }

            HStack(spacing: 8) {
                actionButton(label: "Invite", icon: "person.badge.plus", compact: true) { showShareSheet = true }
                actionButton(label: "Share", icon: "square.and.arrow.up", compact: true) { showShareSheet = true }
                actionButton(label: "Calendar", icon: "calendar.badge.plus", compact: true) { showAddToCalendar = true }
            }
        }
        .padding(16)
    }

    private var rsvpButtons: some View {
        HStack(spacing: 8) {
            if gathering.rsvpSettings.allowGoing {
                rsvpButton(.going)
            }
            if gathering.rsvpSettings.allowMaybe {
                rsvpButton(.maybe)
            }
            if gathering.rsvpSettings.allowDecline {
                rsvpButton(.declined)
            }
        }
    }

    private func rsvpButton(_ status: AmenGatheringRsvpStatus) -> some View {
        let isSelected = userRsvpStatus == status
        return Button {
            submitRsvp(status)
        } label: {
            HStack(spacing: 5) {
                if isSubmittingRsvp && userRsvpStatus == status {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: status.systemImage)
                        .font(.subheadline)
                }
                Text(status.actionLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.black : .primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AmenTheme.Colors.amenGold)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AmenTheme.Colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSubmittingRsvp || gathering.status != .published)
        .accessibilityLabel(status.actionLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func actionButton(label: String, icon: String, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.primary)
            .frame(minWidth: 60, minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(AmenTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func submitRsvp(_ status: AmenGatheringRsvpStatus) {
        guard !isSubmittingRsvp else { return }
        isSubmittingRsvp = true
        Task {
            do {
                let input = AmenGatheringRsvpInput(gatheringId: gathering.gatheringId, status: status)
                try await AmenGatheringService.shared.rsvpToGathering(input)
                userRsvpStatus = status
            } catch let e as AmenGatheringError {
                showRsvpError = e.localizedDescription
            } catch {
                showRsvpError = error.localizedDescription
            }
            isSubmittingRsvp = false
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About This Gathering")
                .font(.headline.weight(.bold))

            if let desc = gathering.description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let speaker = gathering.details.speaker {
                    detailItem(icon: "mic", label: "Speaker", value: speaker)
                }
                if let leader = gathering.details.leader {
                    detailItem(icon: "person.fill", label: "Leader", value: leader)
                }
                if let bring = gathering.details.whatToBring {
                    detailItem(icon: "bag", label: "What to Bring", value: bring)
                }
                if let childcare = gathering.details.childcare {
                    detailItem(icon: "figure.and.child.holdinghands", label: "Childcare", value: childcare)
                }
                if let parking = gathering.details.parking {
                    detailItem(icon: "parkingsign.circle", label: "Parking", value: parking)
                }
                if let access = gathering.details.accessibilityNotes {
                    detailItem(icon: "figure.roll", label: "Accessibility", value: access)
                }
            }

            countRow
        }
        .padding(16)
    }

    private func detailItem(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var countRow: some View {
        HStack(spacing: 16) {
            if gathering.counts.going > 0 {
                Label("\(gathering.counts.going) Going", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
            if gathering.counts.maybe > 0 {
                Label("\(gathering.counts.maybe) Maybe", systemImage: "questionmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if gathering.waitlistEnabled && gathering.counts.waitlisted > 0 {
                Label("\(gathering.counts.waitlisted) Waitlisted", systemImage: "clock.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Spiritual Section

    private var spiritualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spiritual Focus")
                .font(.headline.weight(.bold))

            if let scripture = gathering.spiritual.scriptureReference {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scripture")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(scripture)
                            .font(.subheadline)
                    }
                }
            }

            if let prayerFocus = gathering.spiritual.prayerFocus {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hands.sparkles")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prayer Focus")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(prayerFocus)
                            .font(.subheadline)
                    }
                }
            }

            if flags.gatheringPrayerRequestsEnabled && gathering.spiritual.allowPrayerRequests {
                Button {
                    showPrayerRequestSheet = true
                } label: {
                    Label("Submit a Prayer Request", systemImage: "hands.sparkles.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AmenTheme.Colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Submit a prayer request for this gathering")
            }
        }
        .padding(16)
    }

    // MARK: - Community Section

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Community")
                .font(.headline.weight(.bold))

            Button {
                showGuestList = true
            } label: {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Guest List")
                            .font(.subheadline.weight(.medium))
                        if gathering.counts.going > 0 {
                            Text("\(gathering.counts.going) attending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Be the first to RSVP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View guest list, \(gathering.counts.going) attending")
        }
        .padding(16)
    }

    // MARK: - Safety Section

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showSafetyInfo.toggle()
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Privacy & Safety")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: showSafetyInfo ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy and safety information")
            .accessibilityHint("Tap to \(showSafetyInfo ? "collapse" : "expand")")

            if showSafetyInfo {
                VStack(alignment: .leading, spacing: 8) {
                    safetyRow(
                        icon: "person.fill",
                        text: "Your display name and profile photo may appear on the guest list if you RSVP."
                    )
                    if gathering.spiritual.allowPrayerRequests {
                        safetyRow(
                            icon: "lock.fill",
                            text: "Prayer requests are private and only visible to hosts and ministry leaders."
                        )
                    }
                    if gathering.spiritual.allowPastoralFollowUp {
                        safetyRow(
                            icon: "heart.fill",
                            text: "Pastoral follow-up requests are confidential and handled by authorized staff only."
                        )
                    }
                    safetyRow(
                        icon: gathering.visibility.systemImage,
                        text: "This gathering is \(gathering.visibility.displayName.lowercased())."
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func safetyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Divider().padding(.horizontal, 16)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("Share this gathering")
                }
                if flags.gatheringHostConsoleEnabled {
                    Button {
                        showHostConsole = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .accessibilityLabel("Host controls")
                    }
                }
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Prayer Request View (inline placeholder)

struct AmenGatheringPrayerRequestView: View {
    let gatheringId: String
    let gatheringTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var prayerText = ""
    @State private var requestPastoralFollowUp = false
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                submittedState
            } else {
                formState
            }
        }
    }

    private var formState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What would you like prayer for?")
                        .font(.headline)
                    TextEditor(text: $prayerText)
                        .frame(minHeight: 120)
                        .padding(10)
                        .background(AmenTheme.Colors.surfaceCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Toggle(isOn: $requestPastoralFollowUp) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Request pastoral follow-up")
                            .font(.subheadline.weight(.medium))
                        Text("A ministry leader will reach out privately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("This prayer request is private.", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Only the gathering host and authorized ministry leaders can see it. It will never be shown publicly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    submitPrayer()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit Prayer Request")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(prayerText.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.systemGray4) : AmenTheme.Colors.amenGold)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(prayerText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.65 : 1)
                }
                .buttonStyle(.plain)
                .disabled(prayerText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                .accessibilityLabel("Submit prayer request")
            }
            .padding(20)
        }
        .navigationTitle("Prayer Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var submittedState: some View {
        VStack(spacing: 24) {
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Prayer Request Submitted")
                    .font(.title3.weight(.semibold))
                Text("Your request has been sent privately to the gathering host.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submitPrayer() {
        guard !prayerText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubmitting = true
        Task {
            let input = AmenGatheringRsvpInput(
                gatheringId: gatheringId,
                status: .going,
                requestedPrayer: true,
                requestedPastoralFollowUp: requestPastoralFollowUp
            )
            _ = try? await AmenGatheringService.shared.rsvpToGathering(input)
            submitted = true
            isSubmitting = false
        }
    }
}
