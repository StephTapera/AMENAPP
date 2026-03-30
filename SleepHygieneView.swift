// SleepHygieneView.swift
// AMENAPP
//
// Sleep hygiene checklist + optional bedtime prayer routine.
// Users tap items to check them off; completion writes to HealthKit.
//

import SwiftUI
import HealthKit

struct SleepHygieneView: View {
    @Environment(\.dismiss) private var dismiss
    private let healthStore = HKHealthStore()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private let accent = Color(red: 0.28, green: 0.38, blue: 0.62)

    private let hygieneItems: [SleepItem] = [
        SleepItem(icon: "iphone.slash",          title: "Screens off",          subtitle: "Put your phone face-down now"),
        SleepItem(icon: "thermometer.medium",    title: "Cool the room",        subtitle: "65–68°F is ideal for sleep"),
        SleepItem(icon: "lightbulb.slash.fill",  title: "Dim the lights",       subtitle: "Melatonin needs darkness"),
        SleepItem(icon: "cup.and.saucer.fill",   title: "No caffeine after 2pm",subtitle: "Check today's total"),
        SleepItem(icon: "bed.double.fill",        title: "Bed is for sleep",     subtitle: "Only sleep — no scrolling"),
        SleepItem(icon: "clock.fill",             title: "Same time tomorrow",   subtitle: "Consistent wake time matters most"),
    ]

    private let prayerSteps: [SleepItem] = [
        SleepItem(icon: "hand.raised.fill",       title: "Surrender your worries", subtitle: "\"Cast your anxiety on Him\" — 1 Pet 5:7"),
        SleepItem(icon: "heart.fill",             title: "Gratitude",              subtitle: "Name three things from today"),
        SleepItem(icon: "person.fill",            title: "Intercession",           subtitle: "One person you're praying for"),
        SleepItem(icon: "sparkles",               title: "Scripture",              subtitle: "\"In peace I will lie down and sleep\" — Ps 4:8"),
        SleepItem(icon: "moon.stars.fill",        title: "Rest in Him",            subtitle: "Release tomorrow to God. He is awake."),
    ]

    @State private var checkedHygiene: Set<Int> = []
    @State private var checkedPrayer: Set<Int> = []
    @State private var showPrayer: Bool = false
    @State private var showComplete: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.02, green: 0.04, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if showComplete {
                completionView.transition(.opacity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 36, height: 36)
                                    .background(Color.white.opacity(0.1), in: Circle())
                            }
                            Spacer()
                            Text("Sleep Hygiene")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.white)
                            Spacer()
                            Color.clear.frame(width: 36)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 56)

                        // Moon icon
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(accent)
                            .padding(.top, 28)
                            .padding(.bottom, 8)

                        Text("Wind-down routine")
                            .font(.custom("OpenSans-SemiBold", size: 20))
                            .foregroundStyle(.white)
                        Text("Check each item as you complete it")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 4)
                            .padding(.bottom, 28)

                        // Hygiene checklist
                        sectionHeader("SLEEP HYGIENE", icon: "checkmark.circle")
                        ForEach(hygieneItems.indices, id: \.self) { i in
                            checkRow(hygieneItems[i], checked: checkedHygiene.contains(i)) {
                                toggle(&checkedHygiene, i)
                            }
                        }

                        // Prayer section
                        sectionHeader("BEDTIME PRAYER", icon: "moon.fill")
                            .padding(.top, 28)
                        ForEach(prayerSteps.indices, id: \.self) { i in
                            checkRow(prayerSteps[i], checked: checkedPrayer.contains(i)) {
                                toggle(&checkedPrayer, i)
                            }
                        }

                        // Complete button
                        let totalChecked = checkedHygiene.count + checkedPrayer.count
                        let totalItems = hygieneItems.count + prayerSteps.count

                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            Task { await writeHealthKit() }
                            withAnimation { showComplete = true }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Complete Routine (\(totalChecked)/\(totalItems))")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(totalChecked > 0 ? accent : Color.white.opacity(0.15))
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 52)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showComplete)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func checkRow(_ item: SleepItem, checked: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(checked ? accent : Color.white.opacity(0.1))
                        .frame(width: 32, height: 32)
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(checked ? .white : .white.opacity(0.6))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(checked ? .white.opacity(0.5) : .white)
                    Text(item.subtitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(
                Color.white.opacity(checked ? 0.04 : 0.07)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundStyle(accent)
            Text("Rest well.")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
            Text("\"He grants sleep to those he loves.\"\n— Psalm 127:2")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Good night")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    private func toggle(_ set: inout Set<Int>, _ i: Int) {
        haptic.impactOccurred()
        if set.contains(i) { set.remove(i) } else { set.insert(i) }
    }

    private func writeHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [type], read: [])
            let now = Date()
            let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                          start: now.addingTimeInterval(-600), end: now,
                                          metadata: ["AMENSleepRoutine": "completed"])
            try await healthStore.save(sample)
        } catch { }
    }
}

struct SleepItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}
