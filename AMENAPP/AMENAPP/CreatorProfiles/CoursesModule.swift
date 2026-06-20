// CoursesModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// The course catalog: each CreatorHubCourse renders as a glass card showing module and
// lesson counts plus a progress affordance whose presentation matches the course's
// progressModel — a linear progress bar for `.linear`, a freeform "pick any lesson"
// chip for `.freeform`. CalmCap-bounded with a "Load more" that pages via
// CreatorHubService.pageCourses. Skeleton-first.
//
// Conventions: black primary text; glass course cards (no glass-on-glass — flat inner
// elements); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver — each card is one
// combined, tappable element.

import SwiftUI

struct CoursesModule: View {
    let creatorId: String
    let courses: [CreatorHubCourse]

    /// Start / open a course (host opens the course detail/player).
    var onOpenCourse: (CreatorHubCourse) -> Void = { _ in }

    /// CalmCap: bound how many courses render before "Load more".
    var initialVisible: Int = 12

    @State private var maxVisible: Int = 12
    @State private var loaded: [CreatorHubCourse] = []
    @State private var nextCursor: String?
    @State private var didInitialLoad = false
    @State private var isPaging = false
    @State private var pageError: String?

    private var allCourses: [CreatorHubCourse] { loaded.isEmpty ? courses : loaded }
    private var window: [CreatorHubCourse] { Array(allCourses.prefix(maxVisible)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !didInitialLoad && courses.isEmpty {
                skeleton
            } else if allCourses.isEmpty {
                emptyState
            } else {
                ForEach(window) { course in
                    courseCard(course)
                }
                loadMore
            }
        }
        .padding(.horizontal, 16)
        .onAppear {
            if loaded.isEmpty { loaded = courses }
            maxVisible = max(maxVisible, initialVisible)
            didInitialLoad = true
        }
    }

    // MARK: - Course card

    private func courseCard(_ course: CreatorHubCourse) -> some View {
        let moduleCount = course.modules.count
        let lessonCount = course.modules.reduce(0) { $0 + $1.lessons.count }

        return Button {
            onOpenCourse(course)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(AmenTheme.Colors.amenGoldText)
                        .accessibilityHidden(true)
                    Text(course.title)
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 14) {
                    countLabel(icon: "square.stack.3d.up", value: moduleCount, unit: "module")
                    countLabel(icon: "list.bullet", value: lessonCount, unit: "lesson")
                }

                progressAffordance(for: course)

                startButton(for: course)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .amenGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(course, modules: moduleCount, lessons: lessonCount))
        .accessibilityHint("Opens this course")
        .accessibilityAddTraits(.isButton)
    }

    private func countLabel(icon: String, value: Int, unit: String) -> some View {
        Label("\(value) \(unit)\(value == 1 ? "" : "s")", systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
    }

    // MARK: - Progress affordance (matches progressModel)

    @ViewBuilder
    private func progressAffordance(for course: CreatorHubCourse) -> some View {
        switch course.progressModel {
        case .linear:
            VStack(alignment: .leading, spacing: 5) {
                Text("Step-by-step")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                ProgressView(value: 0)
                    .tint(AmenTheme.Colors.amenGoldText)
                    .accessibilityHidden(true)
            }
        case .freeform:
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x2")
                    .imageScale(.small)
                Text("Take lessons in any order")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    private func startButton(for course: CreatorHubCourse) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .imageScale(.small)
            Text(course.progressModel == .linear ? "Start course" : "Explore lessons")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
        .accessibilityHidden(true)  // surfaced via the card's combined label + hint
    }

    // MARK: - Load more (CalmCap-bounded pagination)

    @ViewBuilder
    private var loadMore: some View {
        let hasMoreWindow = allCourses.count > maxVisible
        if hasMoreWindow || nextCursor != nil {
            VStack(spacing: 8) {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    HStack(spacing: 6) {
                        if isPaging {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isPaging ? "Loading…" : "Load more")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPaging)
                .accessibilityLabel("Load more courses")

                if let pageError {
                    Text(pageError)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.statusError)
                }
            }
        }
    }

    private func loadNextPage() async {
        if allCourses.count > maxVisible {
            maxVisible += 12
            return
        }
        guard !isPaging else { return }
        isPaging = true
        pageError = nil
        defer { isPaging = false }
        do {
            let (items, cursorOut) = try await CreatorHubService.shared.pageCourses(
                creatorId: creatorId,
                cursor: nextCursor
            )
            loaded.append(contentsOf: items)
            nextCursor = cursorOut
            maxVisible += items.count
        } catch {
            pageError = "Couldn't load more courses."
        }
    }

    // MARK: - Skeleton / empty

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                SkeletonCardRow()
            }
        }
        .accessibilityLabel("Loading courses")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap")
                .font(.title)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No courses yet")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Courses from this ministry will appear here.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(_ course: CreatorHubCourse, modules: Int, lessons: Int) -> String {
        let model = course.progressModel == .linear ? "Step-by-step course" : "Self-paced course"
        return "\(course.title). \(model). \(modules) modules, \(lessons) lessons."
    }
}
