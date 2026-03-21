//
//  BereanVOTDCard.swift
//  AMENAPP
//
//  Verse of the Day card for the Berean landing/home screen.
//  Shows one of 7 curated verses based on the day of the week.
//  Tapping opens a new Berean conversation pre-seeded with 3 reflection questions.
//

import SwiftUI

// MARK: - VOTD Data

struct BereanVOTD {
    let reference: String
    let text: String
    let reflection: String   // Short thematic subtitle shown on the card
}

private let bereanVOTDs: [BereanVOTD] = [
    // Sunday
    BereanVOTD(
        reference: "Psalm 118:24",
        text: "This is the day the Lord has made; let us rejoice and be glad in it.",
        reflection: "Joy & Gratitude"
    ),
    // Monday
    BereanVOTD(
        reference: "Joshua 1:9",
        text: "Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.",
        reflection: "Strength & Courage"
    ),
    // Tuesday
    BereanVOTD(
        reference: "Proverbs 3:5–6",
        text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
        reflection: "Trust & Direction"
    ),
    // Wednesday
    BereanVOTD(
        reference: "Philippians 4:13",
        text: "I can do all this through him who gives me strength.",
        reflection: "Faith & Perseverance"
    ),
    // Thursday
    BereanVOTD(
        reference: "Romans 8:28",
        text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
        reflection: "Hope & Providence"
    ),
    // Friday
    BereanVOTD(
        reference: "Isaiah 40:31",
        text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
        reflection: "Renewal & Hope"
    ),
    // Saturday
    BereanVOTD(
        reference: "Matthew 11:28",
        text: "Come to me, all you who are weary and burdened, and I will give you rest.",
        reflection: "Rest & Grace"
    ),
]

// MARK: - BereanVOTDCard

struct BereanVOTDCard: View {

    /// Called when the user taps the card — passes the pre-seeded prompt.
    var onTap: (String) -> Void = { _ in }

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private var todayVOTD: BereanVOTD {
        let dayIndex = Calendar.current.component(.weekday, from: Date()) - 1  // 0 = Sun
        return bereanVOTDs[dayIndex % bereanVOTDs.count]
    }

    private var seedPrompt: String {
        let v = todayVOTD
        return """
        Today's verse is \(v.reference): "\(v.text)"

        Give me 3 meaningful reflection questions about this verse \
        that I can journal on or meditate on throughout my day.
        """
    }

    var body: some View {
        let votd = todayVOTD

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap(seedPrompt)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top: Day label + reflection theme
                HStack {
                    Label("Verse of the Day", systemImage: "sun.horizon.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .labelStyle(.titleAndIcon)

                    Spacer()

                    Text(votd.reflection)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.horizontal, 18)

                // Verse text
                Text("\u{201C}\(votd.text)\u{201D}")
                    .font(.system(size: 15, weight: .light, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineSpacing(5)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                // Reference + CTA
                HStack {
                    Text(votd.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.80))

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Reflect")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.70))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color(red: 0.30, green: 0.20, blue: 0.55).opacity(0.30), radius: 16, y: 6)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Verse of the Day: \(votd.reference). Tap to reflect.")
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.25, blue: 0.68),  // deep indigo
                Color(red: 0.24, green: 0.18, blue: 0.55),  // richer purple
                Color(red: 0.18, green: 0.14, blue: 0.42),  // near-navy
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("VOTD Card") {
    VStack(spacing: 0) {
        BereanVOTDCard { prompt in
            print("Opening Berean with:", prompt)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
#endif
