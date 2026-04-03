// KoraCreateCircleSheet.swift
// AMENAPP
//
// Sheet for creating a new Kora spiritual accountability circle.

import SwiftUI

struct KoraCreateCircleSheet: View {
    @ObservedObject var vm: KoraViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var circleName: String = ""
    @State private var selectedPurpose: KoraPurpose = .spiritualHealth
    @State private var selectedRhythm: KoraRhythm = .weekly
    @State private var selectedDayOfWeek: Int = 1
    @State private var selectedHour: Int = 9
    @State private var isPrivate: Bool = false
    @State private var selectedColorHex: String = "F59E0B"
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    private let coverColors: [(hex: String, name: String)] = [
        ("F59E0B", "Amber"),
        ("6B48FF", "Purple"),
        ("14B8A6", "Teal"),
        ("22C55E", "Green"),
        ("EF4444", "Red"),
        ("3B82F6", "Blue")
    ]

    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let hours = Array(6...22)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {

                        // Circle name
                        nameSection

                        // Purpose picker
                        purposeSection

                        // Rhythm picker
                        rhythmSection

                        // Day + time (weekly/biweekly only)
                        if selectedRhythm != .monthly {
                            scheduleSection
                        }

                        // Privacy toggle
                        privacySection

                        // Cover color picker
                        colorSection

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(AMENFont.regular(13))
                                .foregroundColor(Color(hex: "EF4444"))
                                .padding(.horizontal, 4)
                        }

                        // Create button
                        createButton

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Circle Name")

            TextField("e.g. Monday Morning Crew", text: $circleName)
                .font(AMENFont.regular(15))
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .tint(Color(hex: "6B48FF"))
        }
    }

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Purpose")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KoraPurpose.allCases, id: \.self) { purpose in
                    purposeButton(purpose)
                }
            }
        }
    }

    private func purposeButton(_ purpose: KoraPurpose) -> some View {
        let isSelected = selectedPurpose == purpose
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedPurpose = purpose
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: purpose.icon)
                    .font(.systemScaled(20))
                    .foregroundColor(isSelected ? Color(hex: selectedColorHex) : .white.opacity(0.4))
                Text(purpose.label)
                    .font(AMENFont.regular(11))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                isSelected
                    ? Color(hex: selectedColorHex).opacity(0.12)
                    : Color.white.opacity(0.04)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected
                            ? Color(hex: selectedColorHex).opacity(0.4)
                            : Color.white.opacity(0.07),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Rhythm")

            HStack(spacing: 0) {
                ForEach(KoraRhythm.allCases, id: \.self) { rhythm in
                    rhythmSegment(rhythm)
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func rhythmSegment(_ rhythm: KoraRhythm) -> some View {
        let isSelected = selectedRhythm == rhythm
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedRhythm = rhythm
            }
        } label: {
            Text(rhythm.label)
                .font(isSelected ? AMENFont.semiBold(13) : AMENFont.regular(13))
                .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isSelected
                        ? Capsule().fill(Color(hex: selectedColorHex).opacity(0.25))
                        : Capsule().fill(Color.clear)
                )
                .padding(3)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Day & Time")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                    Picker("Day", selection: $selectedDayOfWeek) {
                        ForEach(0..<daysOfWeek.count, id: \.self) { i in
                            Text(daysOfWeek[i]).tag(i)
                                .foregroundColor(.white)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color(hex: selectedColorHex))
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hour")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                    Picker("Hour", selection: $selectedHour) {
                        ForEach(hours, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                                .foregroundColor(.white)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color(hex: selectedColorHex))
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var privacySection: some View {
        Toggle(isOn: $isPrivate) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.systemScaled(14))
                    .foregroundColor(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private circle")
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.white)
                    Text("Invite-only · Members won't appear in search")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .tint(Color(hex: selectedColorHex))
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Cover Color")

            HStack(spacing: 12) {
                ForEach(coverColors, id: \.hex) { color in
                    colorSwatch(color)
                }
            }
        }
    }

    private func colorSwatch(_ color: (hex: String, name: String)) -> some View {
        let isSelected = selectedColorHex == color.hex
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedColorHex = color.hex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: color.hex))
                    .frame(width: 34, height: 34)
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 44, height: 44)
    }

    private var createButton: some View {
        Button {
            Task { await createCircle() }
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                }
                Text(isCreating ? "Creating…" : "Create Circle")
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                circleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? AnyShapeStyle(Color.white.opacity(0.1))
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CoCreationPressStyle())
        .disabled(circleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.semiBold(13))
            .foregroundColor(.white.opacity(0.55))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func hourLabel(_ h: Int) -> String {
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display) \(suffix)"
    }

    private func createCircle() async {
        let name = circleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        do {
            _ = try await vm.createCircle(
                name: name,
                purpose: selectedPurpose,
                rhythm: selectedRhythm,
                dayOfWeek: selectedRhythm != .monthly ? selectedDayOfWeek : nil,
                hour: selectedRhythm != .monthly ? selectedHour : nil,
                isPrivate: isPrivate,
                memberIds: [],
                coverColorHex: selectedColorHex
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
