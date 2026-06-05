// LocationDelayService.swift
// AMENAPP — Camera OS
// Manages deferred publishing: hold the post until user leaves a location.
// "Share after you leave" default for visit/travel posts.
//
// Design: Liquid Glass on dark/black camera context.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
//   iOS 26+:    .glassEffect() on controls

import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - LocationDelayService

@MainActor
final class LocationDelayService: ObservableObject {

    // MARK: Shared instance

    static let shared = LocationDelayService()

    // MARK: Published state

    @Published var selectedDelay: CameraLocationDelayOption = .none
    @Published var scheduledPublishDate: Date? = nil

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Computes and stores the scheduled publish date for the chosen delay option.
    func scheduleDelay(
        _ option: CameraLocationDelayOption,
        from captureDate: Date = Date()
    ) {
        selectedDelay = option

        switch option {
        case .none:
            scheduledPublishDate = nil

        case .thirtyMinutes:
            scheduledPublishDate = captureDate.addingTimeInterval(30 * 60)

        case .oneHour:
            scheduledPublishDate = captureDate.addingTimeInterval(3600)

        case .afterEvent:
            // Placeholder: treat "after event" as 4 hours after capture.
            scheduledPublishDate = captureDate.addingTimeInterval(4 * 3600)

        case .tomorrow:
            // Start of the day after captureDate.
            let nextDay = captureDate.addingTimeInterval(86400)
            scheduledPublishDate = Calendar.current.startOfDay(for: nextDay)

        case .afterTrip:
            // Placeholder: treat "after trip" as one week after capture.
            scheduledPublishDate = captureDate.addingTimeInterval(7 * 86400)
        }
    }

    /// Cancels any active delay and resets to immediate publishing.
    func cancelDelay() {
        scheduledPublishDate = nil
        selectedDelay = .none
    }

    // MARK: - Computed properties

    var isDelayActive: Bool {
        scheduledPublishDate != nil
    }

    /// Human-readable summary of the current delay state.
    var delayDescription: String {
        guard let date = scheduledPublishDate else {
            return "Publishing immediately"
        }

        switch selectedDelay {
        case .none:
            return "Publishing immediately"

        case .thirtyMinutes, .oneHour:
            let formatted = timeFormatter.string(from: date)
            return "Publishing at \(formatted)"

        case .afterEvent:
            let formatted = timeFormatter.string(from: date)
            return "Publishing after the event (\(formatted))"

        case .tomorrow:
            return "Publishing tomorrow morning"

        case .afterTrip:
            let formatted = shortDateFormatter.string(from: date)
            return "Publishing after your trip (\(formatted))"
        }
    }

    // MARK: - Private helpers

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}

// MARK: - LocationDelayPickerView

struct LocationDelayPickerView: View {

    // MARK: Props

    @Binding var selectedDelay: CameraLocationDelayOption

    // MARK: Layout constants

    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text("When should this post go live?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            // Horizontal scrollable pill row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CameraLocationDelayOption.allCases) { option in
                        DelayPill(
                            option: option,
                            isSelected: selectedDelay == option,
                            accentColor: amberGold
                        ) {
                            selectedDelay = option
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Delay options")

            // Travel safety note — only visible when afterTrip is selected
            if selectedDelay == .afterTrip {
                Text("Travel safety: share after you arrive home")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Travel safety tip: share after you arrive home")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedDelay)
    }
}

// MARK: - DelayPill

private struct DelayPill: View {

    let option: CameraLocationDelayOption
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(option.displayName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(pillBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this delay")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var pillBackground: some View {
        if isSelected {
            // Amber solid fill for selected state
            Capsule()
                .fill(accentColor)
        } else {
            // Glass pill for unselected state
            if #available(iOS 26, *) {
                Capsule().glassEffect()
            } else {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Location Delay Picker") {
    struct PreviewWrapper: View {
        @State private var delay: CameraLocationDelayOption = .none
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                LocationDelayPickerView(selectedDelay: $delay)
                    .padding()
            }
        }
    }
    return PreviewWrapper()
}
