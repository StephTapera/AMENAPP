//
//  PathProgressCard.swift
//  AMENAPP
//
//  Reusable card showing a walk path with animated progress bar.
//  Animation 2: Bar fills on appear with staggered spring.
//

import SwiftUI

struct PathProgressCard: View {
    let path: WalkPath
    let isLocked: Bool
    let index: Int
    let animateBars: Bool
    var onTap: () -> Void = {}

    @State private var barProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pathColor: Color {
        Color(hex: path.color) ?? .amenGold
    }

    var body: some View {
        Button(action: {
            if !isLocked { onTap() }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isLocked ? Color.adaptiveTextTertiary.opacity(0.2) : pathColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isLocked ? "lock.fill" : path.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isLocked ? Color.adaptiveTextTertiary : pathColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(path.title)
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(isLocked ? Color.adaptiveTextTertiary : Color.adaptiveTextPrimary)

                        Spacer()

                        if path.isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.amenSuccess)
                        } else if !isLocked {
                            Text("\(path.completedLessons)/\(path.totalLessons)")
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(Color.adaptiveTextSecondary)
                        }
                    }

                    Text(path.description)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(Color.adaptiveTextTertiary)
                        .lineLimit(1)

                    // Progress bar
                    if !isLocked {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(pathColor.opacity(0.12))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(pathColor)
                                    .frame(width: geo.size.width * barProgress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    } else {
                        Text("Unlocks at \(path.requiredStage.progressLabel) stage")
                            .font(.custom("OpenSans-Regular", size: 10))
                            .foregroundStyle(Color.adaptiveTextTertiary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.adaptiveSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.adaptiveBorder, lineWidth: 1)
            )
            .opacity(isLocked ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(path.title), \(isLocked ? "locked" : "\(path.completedLessons) of \(path.totalLessons) lessons completed")")
        .onAppear {
            if animateBars && !isLocked {
                let delay = Double(index) * 0.12
                if reduceMotion {
                    barProgress = path.progress
                } else {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.65).delay(0.5 + delay)) {
                        barProgress = path.progress
                    }
                }
            } else if !isLocked {
                barProgress = path.progress
            }
        }
    }
}

// MARK: - Color Hex Init

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        PathProgressCard(
            path: WalkPath(id: "1", title: "Foundations of Faith", description: "Core beliefs and first steps", icon: "book.closed.fill", totalLessons: 12, completedLessons: 5, requiredStage: .newBeliever, color: "#16a34a"),
            isLocked: false,
            index: 0,
            animateBars: true
        )
        PathProgressCard(
            path: WalkPath(id: "2", title: "Theology Deep Dive", description: "Understanding doctrine", icon: "graduationcap.fill", totalLessons: 20, completedLessons: 0, requiredStage: .established, color: "#9333ea"),
            isLocked: true,
            index: 1,
            animateBars: true
        )
    }
    .padding()
}
