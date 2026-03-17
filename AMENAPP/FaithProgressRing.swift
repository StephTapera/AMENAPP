//
//  FaithProgressRing.swift
//  AMENAPP
//
//  Animated circular progress ring showing faith journey completion.
//  Animation 1: Count-up with spring on appear.
//

import SwiftUI

struct FaithProgressRing: View {
    let progress: Double           // 0.0 – 1.0
    let stage: FaithStage
    let lessonsCompleted: Int
    let totalLessons: Int
    let animate: Bool

    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stageColor: Color {
        switch stage {
        case .newBeliever: return Color(red: 0.086, green: 0.635, blue: 0.290) // #16a34a
        case .growing: return Color(red: 0.145, green: 0.388, blue: 0.922)     // #2563eb
        case .established: return Color(red: 0.576, green: 0.200, blue: 0.918) // #9333ea
        case .mentor: return Color(red: 0.706, green: 0.325, blue: 0.035)      // #b45309
        }
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    stageColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )

            // Progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    stageColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 2) {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveTextPrimary)
                    .contentTransition(.numericText())

                Text(stage.progressLabel)
                    .font(.custom("OpenSans-SemiBold", size: 10))
                    .foregroundStyle(stageColor)
                    .textCase(.uppercase)
                    .tracking(1)
            }
        }
        .frame(width: 90, height: 90)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.progressLabel) stage, \(Int(progress * 100)) percent complete, \(lessonsCompleted) of \(totalLessons) lessons")
        .onAppear {
            if animate {
                if reduceMotion {
                    animatedProgress = progress
                } else {
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3)) {
                        animatedProgress = progress
                    }
                }
            } else {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            if reduceMotion {
                animatedProgress = newValue
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animatedProgress = newValue
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        FaithProgressRing(progress: 0.35, stage: .newBeliever, lessonsCompleted: 4, totalLessons: 12, animate: true)
        FaithProgressRing(progress: 0.72, stage: .growing, lessonsCompleted: 18, totalLessons: 25, animate: true)
        FaithProgressRing(progress: 1.0, stage: .mentor, lessonsCompleted: 8, totalLessons: 8, animate: true)
    }
    .padding()
}
