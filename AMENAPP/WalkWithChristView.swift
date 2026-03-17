//
//  WalkWithChristView.swift
//  AMENAPP
//
//  Full Walk With Christ experience — personalized faith journey screen.
//  Hero greeting, progress ring, daily verse, quiz, paths, reflections.
//  All 4 animations: progress ring count-up, staggered path bars,
//  reflection icon spin-to-check, quiz option spring lift.
//

import SwiftUI

struct WalkWithChristView: View {
    @StateObject private var viewModel = WalkWithChristViewModel()
    @ObservedObject private var verseService = DailyVerseGenkitService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                heroSection
                progressStrip
                dailyVerseSection
                quizSection
                pathsSection
                reflectionSection
                Spacer(minLength: 40)
            }
            .padding(.top, 8)
        }
        .background(Color.adaptiveBackground)
        .navigationTitle("Walk With Christ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadUserData()
            viewModel.hasAppeared = true
        }
        .refreshable {
            await viewModel.loadUserData()
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            // Greeting
            VStack(spacing: 4) {
                Text(greetingText)
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(Color.adaptiveTextPrimary)

                Text(viewModel.faithStage.greeting)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(Color.adaptiveTextSecondary)
            }

            // Streak badge
            if viewModel.walkStreak > 0 {
                HStack(spacing: 6) {
                    Text(viewModel.streakLabel)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(Color.amenGold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.amenGold.opacity(0.12))
                )
            }

            // Days on journey
            if viewModel.daysOnJourney > 0 {
                Text("Day \(viewModel.daysOnJourney) of your journey")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color.adaptiveTextTertiary)
            }
        }
        .padding(.horizontal)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = viewModel.firstName
        switch hour {
        case 5..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        case 17..<21: return "Good evening, \(name)"
        default: return "Peace be with you, \(name)"
        }
    }

    // MARK: - Progress Strip

    private var progressStrip: some View {
        HStack(spacing: 20) {
            // Progress Ring — Animation 1
            FaithProgressRing(
                progress: overallProgress,
                stage: viewModel.faithStage,
                lessonsCompleted: viewModel.totalLessonsCompleted,
                totalLessons: totalLessonsAcrossPaths,
                animate: viewModel.hasAppeared
            )

            // Stats
            VStack(alignment: .leading, spacing: 8) {
                statRow(label: "Lessons", value: "\(viewModel.totalLessonsCompleted)")
                statRow(label: "Paths", value: "\(completedPathCount)/\(viewModel.paths.count)")
                statRow(label: "Stage", value: viewModel.faithStage.progressLabel)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.adaptiveSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.adaptiveBorder, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(Color.adaptiveTextTertiary)
            Text(value)
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(Color.adaptiveTextPrimary)
        }
    }

    private var overallProgress: Double {
        guard totalLessonsAcrossPaths > 0 else { return 0 }
        return Double(viewModel.totalLessonsCompleted) / Double(totalLessonsAcrossPaths)
    }

    private var totalLessonsAcrossPaths: Int {
        viewModel.paths.reduce(0) { $0 + $1.totalLessons }
    }

    private var completedPathCount: Int {
        viewModel.paths.filter { $0.isComplete }.count
    }

    // MARK: - Daily Verse Section

    private var dailyVerseSection: some View {
        Group {
            if let verse = viewModel.dailyVerse {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.amenGold)

                        Text("Today's Verse")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(Color.adaptiveTextSecondary)
                            .textCase(.uppercase)
                            .tracking(1)

                        Spacer()

                        Text(verse.theme)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.amenGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.amenGold.opacity(0.12))
                            )
                    }

                    Text("\"\(verse.text)\"")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(Color.adaptiveTextPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .italic()

                    Text("— \(verse.reference)")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(Color.adaptiveTextSecondary)

                    if !verse.reflection.isEmpty {
                        Text(verse.reflection)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(Color.adaptiveTextTertiary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.adaptiveSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.adaptiveBorder, lineWidth: 1)
                )
                .padding(.horizontal)
            } else if verseService.isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading today's verse...")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(Color.adaptiveTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Quiz Section

    private var quizSection: some View {
        Group {
            if let quiz = viewModel.todayQuiz {
                // Animation 4: Quiz card option spring lift on press
                FaithQuizCard(quiz: quiz) { answerIndex in
                    Task { await viewModel.submitQuizAnswer(answerIndex) }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Paths Section

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Paths")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(Color.adaptiveTextPrimary)

                Spacer()

                Text("\(completedPathCount) complete")
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(Color.adaptiveTextTertiary)
            }
            .padding(.horizontal)

            // Animation 2: Staggered path bar fill
            ForEach(Array(viewModel.paths.enumerated()), id: \.element.id) { index, path in
                PathProgressCard(
                    path: path,
                    isLocked: viewModel.isPathLocked(path),
                    index: index,
                    animateBars: viewModel.hasAppeared
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Reflection Section

    private var reflectionSection: some View {
        Group {
            if let reflection = viewModel.todayReflection {
                // Animation 3: Reflection icon spin-to-check on complete
                ReflectionPromptCard(reflection: reflection) {
                    Task { await viewModel.completeReflection() }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Loading Overlay

private struct WalkLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Preparing your journey...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(Color.adaptiveTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.adaptiveBackground)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WalkWithChristView()
    }
}
