// AmenGatheringCreateFlow.swift
// AMENAPP — Gathering Creation Wizard (6 Steps)
//
// Step 1: Basics (name, type, host)
// Step 2: Theme (cover, scripture)
// Step 3: Details (date, time, location, description)
// Step 4: Access (mode, QR, capacity)
// Step 5: Questions (RSVP questions)
// Step 6: Publish (preview, share, QR)

import SwiftUI

struct AmenGatheringCreateFlow: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AmenGatheringCreateViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                TabView(selection: $vm.step) {
                    GatheringCreateStep1(vm: vm).tag(1)
                    GatheringCreateStep2(vm: vm).tag(2)
                    GatheringCreateStep3(vm: vm).tag(3)
                    GatheringCreateStep4(vm: vm).tag(4)
                    GatheringCreateStep5(vm: vm).tag(5)
                    GatheringCreateStep6(vm: vm).tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: vm.step)

                navigationButtons
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel creating gathering")
                }
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                Capsule(style: .continuous)
                    .fill(Color.primary)
                    .frame(width: geo.size.width * CGFloat(vm.step) / 6.0, height: 4)
                    .animation(.easeInOut, value: vm.step)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Step \(vm.step) of 6")
        .accessibilityValue("\(Int(CGFloat(vm.step) / 6.0 * 100))% complete")
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if vm.step > 1 {
                Button("Back") { vm.back() }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 48)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to previous step")
            }

            Button {
                if vm.step < 6 {
                    vm.next()
                } else {
                    vm.publish()
                }
            } label: {
                Group {
                    if vm.isPublishing {
                        ProgressView().tint(.white)
                    } else {
                        Text(vm.step < 6 ? "Continue" : "Publish Gathering")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(minHeight: 48)
                .frame(maxWidth: .infinity)
                .background(vm.canAdvance ? Color.primary : Color(.systemGray4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!vm.canAdvance || vm.isPublishing)
            .accessibilityLabel(vm.step < 6 ? "Continue to next step" : "Publish gathering")
        }
    }

    private var stepTitle: String {
        switch vm.step {
        case 1: return "Basics"
        case 2: return "Theme"
        case 3: return "Details"
        case 4: return "Access"
        case 5: return "Questions"
        case 6: return "Publish"
        default: return "Create Gathering"
        }
    }
}

// MARK: - Step 1: Basics

private struct GatheringCreateStep1: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Gathering Name")
                    TextField("e.g. Friday Night Prayer", text: $vm.input.title)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.next)
                        .accessibilityLabel("Gathering name")
                }

                VStack(alignment: .leading, spacing: 12) {
                    stepLabel("Type of Gathering")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(AmenGatheringType.allCases, id: \.self) { type in
                            typeButton(type)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    stepLabel("Hosting As")
                    ForEach(AmenGatheringHostType.allCases, id: \.self) { hostType in
                        hostTypeRow(hostType)
                    }
                }
            }
            .padding(20)
        }
    }

    private func typeButton(_ type: AmenGatheringType) -> some View {
        let isSelected = vm.input.type == type
        return Button {
            vm.input.type = type
            vm.input.access.mode = type.defaultAccessMode
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80)
            .background(isSelected ? Color.primary : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func hostTypeRow(_ hostType: AmenGatheringHostType) -> some View {
        let isSelected = vm.input.hostType == hostType
        return Button {
            vm.input.hostType = hostType
        } label: {
            HStack {
                Text(hostType.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
            .padding(14)
            .background(isSelected ? Color.primary.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hostType.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Step 2: Theme

private struct GatheringCreateStep2: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Scripture (Optional)")
                    TextField("e.g. Hebrews 10:25", text: Binding(
                        get: { vm.input.theme.scriptureReference ?? "" },
                        set: { vm.input.theme.scriptureReference = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Scripture reference")
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Prayer Focus (Optional)")
                    TextField("What will this gathering focus on in prayer?", text: Binding(
                        get: { vm.input.spiritual.prayerFocus ?? "" },
                        set: { vm.input.spiritual.prayerFocus = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Prayer focus description")
                }

                VStack(alignment: .leading, spacing: 12) {
                    stepLabel("Spiritual Options")
                    Toggle("Allow Prayer Requests", isOn: $vm.input.spiritual.allowPrayerRequests)
                    Toggle("Allow Pastoral Follow-Up Requests", isOn: $vm.input.spiritual.allowPastoralFollowUp)
                    Toggle("Allow Testimonies / Praise Reports", isOn: $vm.input.spiritual.allowTestimonies)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Step 3: Details

private struct GatheringCreateStep3: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Date & Time")
                    DatePicker("Start", selection: $vm.input.startAt, in: Date()...)
                        .datePickerStyle(.compact)
                        .accessibilityLabel("Start date and time")
                    if vm.hasEndTime {
                        DatePicker("End", selection: Binding(
                            get: { vm.input.endAt ?? vm.input.startAt },
                            set: { vm.input.endAt = $0 }
                        ), in: vm.input.startAt...)
                        .datePickerStyle(.compact)
                        .accessibilityLabel("End date and time")
                    }
                    Button(vm.hasEndTime ? "Remove End Time" : "Add End Time") {
                        vm.hasEndTime.toggle()
                        if !vm.hasEndTime { vm.input.endAt = nil }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Location")
                    Picker("Type", selection: $vm.input.location.type) {
                        ForEach(AmenGatheringLocationType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Location type")

                    if vm.input.location.type != .online {
                        TextField("Venue Name", text: Binding(
                            get: { vm.input.location.name ?? "" },
                            set: { vm.input.location.name = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Venue name")

                        TextField("Address", text: Binding(
                            get: { vm.input.location.address ?? "" },
                            set: { vm.input.location.address = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Address")

                        TextField("City", text: Binding(
                            get: { vm.input.location.city ?? "" },
                            set: { vm.input.location.city = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("City")
                    }

                    if vm.input.location.type == .online || vm.input.location.type == .hybrid {
                        TextField("Online Link (Zoom, YouTube, etc.)", text: Binding(
                            get: { vm.input.location.onlineUrl ?? "" },
                            set: { vm.input.location.onlineUrl = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Online meeting link")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Description (Optional)")
                    TextField("Tell people what this gathering is about...", text: Binding(
                        get: { vm.input.description ?? "" },
                        set: { vm.input.description = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Gathering description")
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Additional Details (Optional)")
                    TextField("Speaker / Leader", text: Binding(
                        get: { vm.input.details.speaker ?? "" },
                        set: { vm.input.details.speaker = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Speaker or leader name")

                    TextField("What to bring", text: Binding(
                        get: { vm.input.details.whatToBring ?? "" },
                        set: { vm.input.details.whatToBring = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("What to bring")

                    TextField("Childcare", text: Binding(
                        get: { vm.input.details.childcare ?? "" },
                        set: { vm.input.details.childcare = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Childcare information")
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Step 4: Access

private struct GatheringCreateStep4: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    stepLabel("Access Mode")
                    ForEach(AmenAccessMode.allCases, id: \.self) { mode in
                        accessModeRow(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Visibility")
                    Picker("Visibility", selection: $vm.input.visibility) {
                        ForEach(AmenGatheringVisibility.allCases, id: \.self) { vis in
                            Label(vis.displayName, systemImage: vis.systemImage).tag(vis)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Gathering visibility")
                }

                VStack(alignment: .leading, spacing: 8) {
                    stepLabel("Capacity (Optional)")
                    Toggle("Limit Attendance", isOn: Binding(
                        get: { vm.input.capacity != nil },
                        set: { vm.input.capacity = $0 ? 50 : nil }
                    ))
                    .accessibilityLabel("Limit attendance capacity")

                    if vm.input.capacity != nil {
                        Stepper("Max \(vm.input.capacity ?? 50) attendees",
                                value: Binding(
                                    get: { vm.input.capacity ?? 50 },
                                    set: { vm.input.capacity = $0 }
                                ),
                                in: 5...5000, step: 5)
                        .accessibilityLabel("Maximum attendees: \(vm.input.capacity ?? 50)")

                        Toggle("Enable Waitlist", isOn: $vm.input.waitlistEnabled)
                            .accessibilityLabel("Enable waitlist when capacity is full")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    stepLabel("Guest List Visibility")
                    Picker("Guest List", selection: $vm.input.rsvpSettings.guestListVisibility) {
                        ForEach(AmenGatheringGuestListVisibility.allCases, id: \.self) { vis in
                            Text(vis.displayName).tag(vis)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Who can see the guest list")
                }

                Toggle("Enable Access Pass (QR / NFC / Link)", isOn: $vm.input.access.accessPassEnabled)
                    .accessibilityLabel("Enable QR code, NFC, and share link access")
            }
            .padding(20)
        }
    }

    private func accessModeRow(_ mode: AmenAccessMode) -> some View {
        let isSelected = vm.input.access.mode == mode
        return Button {
            vm.input.access.mode = mode
            vm.input.access.requiresApproval = mode == .request || mode == .roleGated
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(mode.accessStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
            .padding(14)
            .background(isSelected ? Color.primary.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityHint(mode.accessStatusLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Step 5: Questions

private struct GatheringCreateStep5: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel
    @State private var showAddQuestion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Questions")
                        .font(.headline.weight(.bold))
                    Text("Collect information from attendees when they RSVP. Prayer and follow-up answers are private to hosts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enable Questions", isOn: $vm.input.rsvpSettings.questionsEnabled)
                    .accessibilityLabel("Enable RSVP questions")

                if vm.input.rsvpSettings.questionsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        stepLabel("Quick Add")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(quickQuestions, id: \.0) { (prompt, type, sensitive) in
                                quickQuestionChip(prompt: prompt, type: type, sensitive: sensitive)
                            }
                        }
                    }

                    if !vm.input.questions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            stepLabel("Added Questions")
                            ForEach(vm.input.questions.indices, id: \.self) { i in
                                questionRow(index: i)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private let quickQuestions: [(String, AmenGatheringQuestionType, Bool)] = [
        ("Are you bringing someone?", .boolean, false),
        ("Do you need childcare?", .boolean, false),
        ("Would you like prayer?", .boolean, true),
        ("Can you volunteer?", .boolean, false),
        ("Do you need a ride?", .boolean, false),
        ("Dietary restrictions?", .shortText, false)
    ]

    private func quickQuestionChip(prompt: String, type: AmenGatheringQuestionType, sensitive: Bool) -> some View {
        let alreadyAdded = vm.input.questions.contains { $0.prompt == prompt }
        return Button {
            if !alreadyAdded {
                vm.input.questions.append(AmenCreateQuestionInput(
                    prompt: prompt, type: type, options: [],
                    required: false, sensitive: sensitive,
                    sortOrder: vm.input.questions.count
                ))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.caption)
                Text(prompt)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(alreadyAdded ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alreadyAdded ? Color.primary : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .accessibilityLabel(prompt)
        .accessibilityAddTraits(alreadyAdded ? .isSelected : [])
    }

    private func questionRow(index: Int) -> some View {
        HStack {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(vm.input.questions[index].prompt)
                .font(.subheadline)
            Spacer()
            Button {
                vm.input.questions.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Remove question: \(vm.input.questions[index].prompt)")
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Step 6: Publish

private struct GatheringCreateStep6: View {
    @ObservedObject var vm: AmenGatheringCreateViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let response = vm.publishedResponse {
                    publishedState(response)
                } else {
                    previewState
                }
            }
            .padding(20)
        }
    }

    private var previewState: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to Publish")
                    .font(.title3.weight(.bold))
                Text("Review your gathering before sharing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            summaryCard

            VStack(alignment: .leading, spacing: 12) {
                stepLabel("After Publishing")
                Toggle("Allow Prayer Requests", isOn: $vm.input.spiritual.allowPrayerRequests)
                Toggle("Enable Access Pass (QR / Share)", isOn: $vm.input.access.accessPassEnabled)
                Toggle("Publish Immediately", isOn: $vm.input.publishImmediately)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(vm.input.type.displayName, systemImage: vm.input.type.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(vm.input.title)
                .font(.headline.weight(.bold))

            Label(vm.input.startAt.formatted(date: .long, time: .shortened),
                  systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(vm.input.location.displaySummary,
                  systemImage: vm.input.location.type.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(vm.input.access.mode.displayName, systemImage: "person.badge.key.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func publishedState(_ response: AmenCreateGatheringResponse) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Gathering Published!")
                .font(.title3.weight(.bold))

            if let shareLink = response.shareLink {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Share Link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(shareLink)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = shareLink
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.subheadline)
                        }
                        .accessibilityLabel("Copy share link")
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

private func stepLabel(_ text: String) -> some View {
    Text(text)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
}

// MARK: - View Model

@MainActor
final class AmenGatheringCreateViewModel: ObservableObject {
    @Published var input = AmenCreateGatheringInput.empty()
    @Published var step = 1
    @Published var hasEndTime = false
    @Published var isPublishing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var publishedResponse: AmenCreateGatheringResponse?

    var canAdvance: Bool {
        switch step {
        case 1: return !input.title.trimmingCharacters(in: .whitespaces).isEmpty
        case 3:
            if input.location.type == .physical {
                return input.location.name != nil || input.location.city != nil
            }
            return true
        default: return true
        }
    }

    func next() {
        guard step < 6 else { return }
        withAnimation { step += 1 }
    }

    func back() {
        guard step > 1 else { return }
        withAnimation { step -= 1 }
    }

    func publish() {
        guard !isPublishing else { return }
        isPublishing = true
        input.publishImmediately = true
        Task {
            do {
                let response = try await AmenGatheringService.shared.createGathering(input)
                publishedResponse = response
            } catch let e as AmenGatheringError {
                errorMessage = e.localizedDescription
                showError = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isPublishing = false
        }
    }
}
