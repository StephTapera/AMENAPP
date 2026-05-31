//
//  VergeCreateRoomSheet.swift
//  AMENAPP
//
//  Sheet for creating or scheduling a new Verge room.
//

import SwiftUI

struct VergeCreateRoomSheet: View {

    @ObservedObject var vm: VergeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Form state
    @State private var title           = ""
    @State private var selectedType    = VergeRoomType.openDiscussion
    @State private var isScheduled     = false
    @State private var scheduledDate   = Date().addingTimeInterval(3600)
    @State private var monetization    = MonetizationOption.free
    @State private var ticketPrice     = 5.0
    @State private var maxParticipants = 100.0
    @State private var enableRecording = false
    @State private var enableAIMod     = true
    @State private var isCreating      = false
    @State private var errorMessage: String?

    private let amenPurple = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let amenGold   = Color(hex: "F59E0B")
    private let bg         = Color(hex: "0A0A0F")
    private let vergeGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum MonetizationOption: String, CaseIterable {
        case free            = "Free"
        case paid            = "Paid"
        case subscribersOnly = "Subscribers Only"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        titleSection
                        typeSection
                        scheduleSection
                        monetizationSection
                        participantSection
                        togglesSection

                        if let err = errorMessage {
                            Text(err)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.red.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }

                        goLiveButton
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Room Title")
            TextField("What are you discussing today?", text: $title)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white)
                .padding(14)
                .background(glassFieldBackground)
        }
    }

    // MARK: - Type Section

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Room Type")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(VergeRoomType.allCases, id: \.self) { type in
                        typeChip(type)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func typeChip(_ type: VergeRoomType) -> some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(type.label)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(selectedType == type ? .white : .white.opacity(0.55))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                Capsule()
                    .fill(selectedType == type ? amenPurple : Color.white.opacity(0.07))
                    .shadow(color: selectedType == type ? amenPurple.opacity(0.35) : .clear, radius: 8, y: 3)
            )
        }
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Schedule")
                Spacer()
                Toggle("", isOn: $isScheduled.animation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))))
                    .labelsHidden()
                    .tint(amenPurple)
            }
            if isScheduled {
                DatePicker(
                    "Start time",
                    selection: $scheduledDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(amenViolet)
                .foregroundStyle(.white)
                .padding(10)
                .background(glassCardBackground)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Monetization Section

    private var monetizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Monetization")
            Picker("Monetization", selection: $monetization) {
                ForEach(MonetizationOption.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(amenViolet.opacity(0.7))

            if monetization == .paid {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Ticket Price")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(String(format: "$%.0f", ticketPrice))
                            .font(AMENFont.bold(15))
                            .foregroundStyle(amenGold)
                    }
                    Slider(value: $ticketPrice, in: 1...100, step: 1)
                        .tint(amenGold)
                }
                .padding(14)
                .background(glassCardBackground)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75)), value: monetization)
            }
        }
    }

    // MARK: - Participants Section

    private var participantSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Max Participants")
                Spacer()
                Text("\(Int(maxParticipants))")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(amenViolet)
            }
            Slider(value: $maxParticipants, in: 10...500, step: 10)
                .tint(amenViolet)
        }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(spacing: 0) {
            toggleRow(
                icon: "record.circle.fill",
                label: "Enable Recording",
                binding: $enableRecording,
                color: Color.red
            )
            Divider().background(Color.white.opacity(0.06))
            toggleRow(
                icon: "sparkles",
                label: "Enable AI Moderation",
                binding: $enableAIMod,
                color: amenViolet
            )
        }
        .background(glassCardBackground)
    }

    private func toggleRow(icon: String, label: String, binding: Binding<Bool>, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(amenPurple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Go Live Button

    private var goLiveButton: some View {
        Button {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                withAnimation(reduceMotion ? nil : .default) { errorMessage = "Please enter a room title." }
                return
            }
            errorMessage = nil
            isCreating   = true
            Task {
                do {
                    _ = try await vm.createRoom(
                        workspaceId:      "default",
                        title:            title.trimmingCharacters(in: .whitespaces),
                        description:      "",
                        type:             selectedType,
                        scheduledAt:      isScheduled ? scheduledDate : nil,
                        maxParticipants:  Int(maxParticipants),
                        isMonetized:      monetization != .free,
                        ticketPrice:      monetization == .paid ? ticketPrice : nil,
                        subscribersOnly:  monetization == .subscribersOnly,
                        isRecorded:       enableRecording
                    )
                    isCreating = false
                    dismiss()
                } catch {
                    isCreating = false
                    withAnimation(reduceMotion ? nil : .default) { errorMessage = error.localizedDescription }
                }
            }
        } label: {
            ZStack {
                if isCreating {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: isScheduled ? "calendar.badge.plus" : "video.fill")
                            .font(.systemScaled(15, weight: .semibold))
                        Text(isScheduled ? "Schedule Room" : "Go Live Now")
                            .font(AMENFont.bold(17))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vergeGradient)
                    .shadow(color: amenPurple.opacity(0.4), radius: 14, y: 5)
            )
        }
        .disabled(isCreating)
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.semiBold(13))
            .foregroundStyle(.white.opacity(0.55))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private var glassFieldBackground: some ShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(AmenTheme.Colors.backgroundElevated)
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(reduceTransparency
                ? AnyShapeStyle(AmenTheme.Colors.backgroundElevated)
                : AnyShapeStyle(.regularMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}
