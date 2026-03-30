// MovementWellnessView.swift
// AMENAPP
//
// Walking prayer guide + simple stretch routine.
// Faith-body connection. Writes mindfulSession to HealthKit on completion.
//

import SwiftUI
import HealthKit

struct MovementWellnessView: View {
    @Environment(\.dismiss) private var dismiss
    private let healthStore = HKHealthStore()
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let accent = Color(red: 0.22, green: 0.52, blue: 0.38)

    enum MovementMode: String, CaseIterable {
        case walking = "Walking Prayer"
        case stretch = "Stretch Routine"

        var icon: String {
            switch self { case .walking: return "figure.walk"; case .stretch: return "figure.flexibility" }
        }
        var subtitle: String {
            switch self { case .walking: return "15–30 min · Pray while you move"; case .stretch: return "8 min · Gentle movement + scripture" }
        }
    }

    @State private var selectedMode: MovementMode = .walking
    @State private var stepIndex: Int = 0
    @State private var started: Bool = false
    @State private var completed: Bool = false

    private let walkingSteps: [(String, String, String)] = [
        ("Prepare", "figure.stand",        "Before you begin, breathe deeply. Tell God why you're going on this walk today."),
        ("Step 1",  "figure.walk",         "As you begin walking, notice your footsteps. \"The Lord makes firm the steps of the one who delights in him.\" — Psalm 37:23"),
        ("Step 2",  "heart.fill",          "Name one thing weighing on your heart. Speak it aloud — or silently — to God as you walk."),
        ("Step 3",  "eye.fill",            "Look around you. Find something beautiful. Thank God for creating it."),
        ("Step 4",  "person.2.fill",       "Think of someone you care about. Intercede for them with each step you take."),
        ("Step 5",  "text.bubble.fill",    "Listen. Quiet your mind. Walk in silence for one full minute. What surfaces?"),
        ("Close",   "hands.sparkles.fill", "End your walk with gratitude. \"I press on toward the goal for the prize of the upward call of God.\" — Phil 3:14"),
    ]

    private let stretchSteps: [(String, String, String)] = [
        ("Begin",          "lungs.fill",           "Sit or stand. Take 3 slow breaths. \"Let everything that has breath praise the Lord.\" — Psalm 150:6"),
        ("Neck Rolls",     "arrow.clockwise",       "Gently roll your neck side to side, 3 times each. Release the weight you've been carrying."),
        ("Shoulder Drops", "figure.arms.open",      "Roll shoulders back and down. Feel tension release. You are not alone in this."),
        ("Side Stretch",   "arrow.left.arrow.right","Arms overhead, lean left then right. Breathe into each stretch for 5 counts."),
        ("Forward Fold",   "figure.flexibility",    "Slowly fold forward from the hips. Let your head hang. Say: \"I surrender today to you, Lord.\""),
        ("Hip Openers",    "figure.walk",           "Stand and shift weight side to side. Pray for each person you'll see today."),
        ("Final Rest",     "sparkles",              "Stand tall. One hand on your heart. \"My strength is renewed like the eagle's.\" — Isaiah 40:31"),
    ]

    private var steps: [(String, String, String)] {
        selectedMode == .walking ? walkingSteps : stretchSteps
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.12, blue: 0.08), Color(red: 0.02, green: 0.07, blue: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            if completed {
                completionView.transition(.opacity)
            } else if started {
                activeView
            } else {
                setupView
            }
        }
        .animation(.easeInOut(duration: 0.35), value: completed)
        .animation(.easeInOut(duration: 0.35), value: started)
    }

    private var setupView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Spacer()
                Text("Movement")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Image(systemName: "figure.walk")
                .font(.system(size: 52))
                .foregroundStyle(accent)
                .padding(.top, 36)

            Text("Move with purpose")
                .font(.custom("OpenSans-SemiBold", size: 22))
                .foregroundStyle(.white)
                .padding(.top, 12)

            Text("Exercise and prayer together reduce anxiety by up to 48% — movement and meditation are both in the Bible.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 10)

            Spacer().frame(height: 40)

            VStack(spacing: 12) {
                ForEach(MovementMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.5))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.white)
                                Text(mode.subtitle)
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            if selectedMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedMode == mode ? accent.opacity(0.2) : Color.white.opacity(0.07))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            Button {
                stepIndex = 0
                withAnimation { started = true }
            } label: {
                Text("Begin \(selectedMode.rawValue)")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var activeView: some View {
        let step = steps[stepIndex]
        return VStack(spacing: 0) {
            HStack {
                Button {
                    if stepIndex > 0 {
                        withAnimation { stepIndex -= 1 }
                    } else {
                        withAnimation { started = false }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                Spacer()
                Text("\(stepIndex + 1) of \(steps.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Color.clear.frame(width: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Spacer()

            VStack(spacing: 20) {
                Image(systemName: step.1)
                    .font(.system(size: 56))
                    .foregroundStyle(accent)

                Text(step.0)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .kerning(2)
                    .foregroundStyle(accent)

                Text(step.2)
                    .font(.custom("OpenSans-Regular", size: 17))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == stepIndex ? accent : Color.white.opacity(0.2))
                        .frame(width: i == stepIndex ? 20 : 6, height: 6)
                }
            }
            .padding(.bottom, 24)

            Button {
                haptic.impactOccurred()
                if stepIndex < steps.count - 1 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { stepIndex += 1 }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { await writeHealthKit() }
                    withAnimation { completed = true }
                }
            } label: {
                Text(stepIndex < steps.count - 1 ? "Next" : "Complete")
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: selectedMode == .walking ? "figure.walk" : "figure.flexibility")
                .font(.system(size: 64))
                .foregroundStyle(accent)
            Text("Well done.")
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
            Text(selectedMode == .walking
                 ? "You walked and prayed. That's a holy thing."
                 : "Your body and spirit both moved today.")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("\"Do you not know that your body is a temple of the Holy Spirit?\"\n— 1 Corinthians 6:19")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.4))
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button { dismiss() } label: {
                Text("Done")
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

    private func writeHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [type], read: [])
            let now = Date()
            let duration: TimeInterval = selectedMode == .walking ? 900 : 480
            let sample = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue,
                                          start: now.addingTimeInterval(-duration), end: now,
                                          metadata: ["AMENMovement": selectedMode.rawValue])
            try await healthStore.save(sample)
        } catch { }
    }
}
