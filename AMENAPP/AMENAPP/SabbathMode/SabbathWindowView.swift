// SabbathWindowView.swift
// AMENAPP — SabbathMode
//
// Main full-screen view shown when Sabbath is active (state == .active).
// Faithful port of SabbathWindowView.tsx.
//
// Layout:
//   1. Weekday label in gray (uppercased)
//   2. White card with heading, subline, divider, SabbathSurfaceListView
//   3. SolidarityPresenceView (if enabled)
//   4. "Step out of Sabbath" button (tertiary, understated)
//   Sheet: BlessAndCloseSheet (confirmation required)
//
// BANNED tokens: gold (#C9A84C, #FFD97D), purple, dark gradients, serif fonts,
// streaks, badge numbers, "X people" text.

import SwiftUI

struct SabbathWindowView: View {
    @ObservedObject var service: SabbathModeService
    var onSurfaceSelect: (SabbathSurface) -> Void

    @State private var showStepOutSheet = false

    // Weekday label (device-local)
    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: Date()).uppercased()
    }

    var body: some View {
        ZStack {
            // Page background — light gray (#F7F7F7 equivalent)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer().frame(height: 16)

                    // 1. Day of week header
                    Text(todayLabel)
                        .font(.caption.weight(.regular))
                        .tracking(2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Today is \(DateFormatter().string(from: Date()))")

                    // 2. White card
                    sabbathCard

                    // 3. Solidarity (text only — never a count)
                    SolidarityPresenceView()

                    // 4. Step out button — tertiary, understated, small
                    stepOutButton

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .accessibilityLabel("Sabbath mode")
        .sheet(isPresented: $showStepOutSheet) {
            BlessAndCloseSheet(service: service, isPresented: $showStepOutSheet)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Card

    private var sabbathCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Heading
            Text("Today is a day for rest.")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.bottom, 6)

            // Subline
            Text("The app is quiet. You don't have to be.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // Divider
            Divider()
                .padding(.bottom, 16)

            // 8 surface rows
            SabbathSurfaceListView(onSurfaceSelect: onSurfaceSelect)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sabbath rest")
    }

    // MARK: - Step out button

    private var stepOutButton: some View {
        Button {
            // requiresConfirm: true — always show confirmation sheet first
            showStepOutSheet = true
        } label: {
            Text("Step out of Sabbath")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step out of Sabbath for the rest of today")
    }
}

#Preview {
    SabbathWindowView(
        service: SabbathModeService.shared,
        onSurfaceSelect: { surface in
            print("Surface selected: \(surface.rawValue)")
        }
    )
}
