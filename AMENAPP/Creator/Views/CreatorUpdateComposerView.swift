// CreatorUpdateComposerView.swift
// AMENAPP — Creator Studio / Wave 5
//
// Inline composer for creator-to-follower updates.
// Supports announcement, episode, live event, prayer request, milestone, resource.
// Draft persisted via @AppStorage; moderation notice shown inline.

import SwiftUI

struct CreatorUpdateComposerView: View {

    // MARK: - Update Type

    enum UpdateType: String, CaseIterable, Identifiable {
        case announcement  = "Announcement"
        case newEpisode    = "New Episode"
        case liveEvent     = "Live Event"
        case prayerRequest = "Prayer Request"
        case milestone     = "Milestone"
        case resource      = "Resource"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .announcement:  return "megaphone.fill"
            case .newEpisode:    return "play.circle.fill"
            case .liveEvent:     return "video.fill"
            case .prayerRequest: return "hands.sparkles.fill"
            case .milestone:     return "flag.fill"
            case .resource:      return "doc.text.fill"
            }
        }
    }

    // MARK: - Audience

    enum AudienceOption: String, CaseIterable, Identifiable {
        case allFollowers       = "All followers"
        case communityOnly      = "Community members only"

        var id: String { rawValue }
    }

    // MARK: - State

    @State private var selectedType: UpdateType = .announcement
    @State private var audienceOption: AudienceOption = .allFollowers
    @State private var scheduledDate: Date = Date()
    @State private var isScheduled = false
    @State private var showPreview = false
    @State private var isSubmitting = false

    @AppStorage("studio_draft") private var draftText: String = ""

    private let maxChars = 500

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeSelectorRow

            Divider()
                .padding(.vertical, 12)

            composerCard

            if isScheduled {
                schedulerRow
                    .padding(.top, 8)
            }

            audienceRow
                .padding(.top, 8)

            actionRow
                .padding(.top, 12)
        }
        .sheet(isPresented: $showPreview) {
            previewSheet
        }
    }

    // MARK: - Type Selector

    private var typeSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UpdateType.allCases) { type in
                    typeChip(type)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func typeChip(_ type: UpdateType) -> some View {
        let isSelected = selectedType == type
        Button {
            withAnimation(.spring(response: 0.2)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(type.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                    .shadow(color: .black.opacity(isSelected ? 0 : 0.06), radius: 4, x: 0, y: 1)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Composer Card

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if draftText.isEmpty {
                    Text("What would you like to share?")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftText)
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .onChange(of: draftText) { _, newValue in
                        if newValue.count > maxChars {
                            draftText = String(newValue.prefix(maxChars))
                        }
                    }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

            HStack {
                Text("\(draftText.count)/\(maxChars)")
                    .font(.caption2)
                    .foregroundStyle(draftText.count >= maxChars ? Color.red : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Scheduler

    private var schedulerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            DatePicker(
                "Schedule for",
                selection: $scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline)
            .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Audience

    private var audienceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            Picker("Audience", selection: $audienceOption) {
                ForEach(AudienceOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(.subheadline)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Schedule toggle
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        isScheduled.toggle()
                    }
                } label: {
                    Label(
                        isScheduled ? "Scheduled" : "Schedule",
                        systemImage: isScheduled ? "calendar.badge.checkmark" : "calendar.badge.plus"
                    )
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(isScheduled ? Color.green.opacity(0.15) : Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(isScheduled ? Color.green : Color.primary)
                }
                .buttonStyle(.plain)

                // Preview
                Button {
                    showPreview = true
                } label: {
                    Label("Preview", systemImage: "eye")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Submit
                Button {
                    Task { await submitUpdate() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 80)
                    } else {
                        Text("Share Update")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(draftText.isEmpty ? Color.accentColor.opacity(0.4) : Color.accentColor))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .disabled(draftText.isEmpty || isSubmitting)
            }

            // Moderation notice
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption2)
                Text("Updates are reviewed before reaching followers.")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Preview Sheet

    private var previewSheet: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How followers see this")
                            .font(.headline)
                            .padding(.top, 8)

                        updatePreviewCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showPreview = false }
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
    }

    private var updatePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: selectedType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(selectedType.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            if draftText.isEmpty {
                Text("(Your update will appear here)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(draftText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                Text(audienceOption.rawValue)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Submit

    private func submitUpdate() async {
        guard !draftText.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        // TODO: wire to Firestore createCreatorUpdate callable
        // Stub: clear draft on success
        try? await Task.sleep(nanoseconds: 800_000_000)
        draftText = ""
        isScheduled = false
    }
}
