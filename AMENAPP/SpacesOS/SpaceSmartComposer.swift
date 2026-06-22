// SpaceSmartComposer.swift
// AMENAPP — SpacesOS
// Unified smart composer for all Space post types.

import SwiftUI

struct SpaceSmartComposer: View {
    let spaceName: String
    let memberRole: SpaceMemberRole
    let onSubmit: (ContentCard, SpacePostType) -> Void
    let onDismiss: () -> Void

    @State private var selectedType: SpacePostType = .discussion
    @State private var title = ""
    @State private var messageBody = ""
    @State private var audience: ContentAudience = .spaceMembers
    @State private var isSubmitting = false

    // Event fields
    @State private var eventDate = Date().addingTimeInterval(86400)
    @State private var eventLocation = ""

    // Poll fields
    @State private var pollOptions: [String] = ["", ""]
    @State private var pollAnonymous = false

    // Prayer Room fields
    @State private var prayerPrivate = false

    // Study fields
    @State private var studyScripture = ""
    @State private var studyQuestions: [String] = [""]

    // Resource fields
    @State private var resourceURL = ""

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isValid: Bool {
        switch selectedType {
        case .discussion, .announcement: return !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
        case .event: return !title.isEmpty
        case .prayerRoom: return !messageBody.isEmpty
        case .study: return !studyScripture.isEmpty
        case .poll: return !messageBody.isEmpty && pollOptions.filter { !$0.isEmpty }.count >= 2
        case .resource: return !title.isEmpty && !resourceURL.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Post type picker
                typePicker

                Divider().opacity(0.3)

                // Form body
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        formContent
                        audiencePicker
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }

                // Submit bar
                submitBar
            }
            .navigationTitle("Post to \(spaceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpacePostType.allCases) { type in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28)) {
                            selectedType = type
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: type.icon)
                                .font(.systemScaled(12, weight: .semibold))
                            Text(type.displayName)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(selectedType == type ? .white : .primary)
                        .background(
                            selectedType == type
                                ? Color.accentColor
                                : Color(.secondarySystemBackground),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.displayName)
                    .accessibilityAddTraits(selectedType == type ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        switch selectedType {
        case .discussion:
            composerTextField(placeholder: "What's on your mind?", text: $messageBody, minHeight: 100)
        case .announcement:
            composerTextField(placeholder: "Announcement title", text: $title, minHeight: 44, isTitle: true)
            composerTextField(placeholder: "Details…", text: $messageBody, minHeight: 80)
        case .event:
            composerTextField(placeholder: "Event name", text: $title, minHeight: 44, isTitle: true)
            composerTextField(placeholder: "Description", text: $messageBody, minHeight: 60)
            DatePicker("Date & Time", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)
            composerTextField(placeholder: "Location (optional)", text: $eventLocation, minHeight: 44)
        case .prayerRoom:
            composerTextField(placeholder: "What would you like prayer for?", text: $messageBody, minHeight: 100)
            Toggle("Keep Private (only prayer team sees)", isOn: $prayerPrivate)
                .font(.subheadline)
        case .study:
            composerTextField(placeholder: "Study title", text: $title, minHeight: 44, isTitle: true)
            composerTextField(placeholder: "Scripture passage (e.g. James 1:1-12)", text: $studyScripture, minHeight: 44)
            composerTextField(placeholder: "Description", text: $messageBody, minHeight: 60)
            VStack(alignment: .leading, spacing: 8) {
                Text("Discussion Questions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(studyQuestions.enumerated()), id: \.offset) { i, _ in
                    HStack {
                        Text("\(i + 1).").foregroundStyle(.secondary).frame(width: 20)
                        TextField("Question", text: $studyQuestions[i])
                            .font(.subheadline)
                    }
                }
                Button("+ Add Question") { studyQuestions.append("") }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        case .poll:
            composerTextField(placeholder: "Poll question", text: $messageBody, minHeight: 44, isTitle: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Options").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(pollOptions.enumerated()), id: \.offset) { i, _ in
                    TextField("Option \(i + 1)", text: $pollOptions[i])
                        .font(.subheadline)
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                if pollOptions.count < 6 {
                    Button("+ Add Option") { pollOptions.append("") }
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            Toggle("Anonymous responses", isOn: $pollAnonymous).font(.subheadline)
        case .resource:
            composerTextField(placeholder: "Resource title", text: $title, minHeight: 44, isTitle: true)
            composerTextField(placeholder: "URL or file link", text: $resourceURL, minHeight: 44)
            composerTextField(placeholder: "Description", text: $messageBody, minHeight: 60)
        }
    }

    @ViewBuilder
    private func composerTextField(placeholder: String, text: Binding<String>, minHeight: CGFloat, isTitle: Bool = false) -> some View {
        if isTitle {
            TextField(placeholder, text: text)
                .font(.headline)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        } else {
            TextEditor(text: text)
                .font(.subheadline)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder).font(.subheadline).foregroundStyle(.quaternary).padding(14).allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Audience Picker

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audience").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                audienceChip(.spaceMembers, label: "Space Members", icon: "person.2.fill")
                if memberRole.canPostAnnouncement {
                    audienceChip(.trustedCircle, label: "Leaders Only", icon: "star.fill")
                }
                if memberRole != .guest {
                    audienceChip(.publicFeed, label: "Public", icon: "globe")
                }
            }
        }
    }

    @ViewBuilder
    private func audienceChip(_ value: ContentAudience, label: String, icon: String) -> some View {
        Button {
            audience = value
        } label: {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .foregroundStyle(audience == value ? .white : .primary)
                .background(audience == value ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit Bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Post to \(spaceName)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    isValid && !isSubmitting ? Color.accentColor : Color.secondary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isValid || isSubmitting)
            .padding(16)
            .accessibilityLabel("Post to \(spaceName)")
        }
        .background {
            if reduceTransparency { Color(.systemBackground) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        let card = ContentCard(
            id: UUID().uuidString,
            title: title.isEmpty ? String(messageBody.prefix(60)) : title,
            body: messageBody,
            sourceType: .post,
            sourceSurface: .space,
            sourceId: UUID().uuidString,
            originalAudience: audience,
            creatorId: "current-user",
            creatorDisplayName: nil,
            sensitivityScore: selectedType == .prayerRoom ? 0.6 : 0.2,
            hasPrayerContent: selectedType == .prayerRoom,
            hasChildContent: false,
            hasLocationData: selectedType == .event && !eventLocation.isEmpty,
            hasMinors: false,
            isAnonymous: selectedType == .prayerRoom && prayerPrivate,
            isPaidContent: false,
            isDM: false,
            isChurchInternal: selectedType == .announcement,
            createdAt: Date(),
            expiresAt: nil,
            moderationState: .safe,
            discussionStatus: .open,
            attributionRules: ContentAttributionRules(
                requiresAttribution: !prayerPrivate,
                allowsAnonymous: selectedType == .prayerRoom,
                allowsQuoteOnly: false,
                expiresAfterDays: nil
            )
        )
        onSubmit(card, selectedType)
        isSubmitting = false
        onDismiss()
    }
}

// MARK: - Preview

#Preview {
    SpaceSmartComposer(
        spaceName: "Sunday Morning Group",
        memberRole: .member,
        onSubmit: { _, _ in },
        onDismiss: {}
    )
}
