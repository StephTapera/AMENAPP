// AmenCatchMeUpSheet.swift
// AMEN Connect + Spaces — Late-Joiner AI Catch-Up Sheet
// Built: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Local types

private enum SummaryLength: CaseIterable, Identifiable {
    case thirtySeconds
    case twoMinutes
    case fiveMinutes

    var id: Self { self }

    var lengthSeconds: Int {
        switch self {
        case .thirtySeconds: return 30
        case .twoMinutes:    return 120
        case .fiveMinutes:   return 300
        }
    }

    var title: String {
        switch self {
        case .thirtySeconds: return "30-Second Recap"
        case .twoMinutes:    return "2-Minute Summary"
        case .fiveMinutes:   return "5-Minute Deep Dive"
        }
    }

    var bestFor: String {
        switch self {
        case .thirtySeconds: return "Just joined"
        case .twoMinutes:    return "Missed a section"
        case .fiveMinutes:   return "Completely new"
        }
    }
}

private struct CatchUpResult {
    var summary: String
    var topics: [String]
    var prayerRequests: [String]
    var actionItems: [String]
    var scriptureRefs: [String]
}

// MARK: - Main sheet

struct AmenCatchMeUpSheet: View {
    let streamId: String
    let streamTitle: String
    let minutesElapsed: Int
    let onDismiss: () -> Void

    @State private var selectedLength: SummaryLength? = nil
    @State private var isLoading: Bool = false
    @State private var summaryResult: CatchUpResult? = nil
    @State private var loadError: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let functions = Functions.functions()

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                Divider().opacity(0.2)

                ScrollView {
                    VStack(spacing: 20) {
                        lengthPickerSection

                        if isLoading {
                            loadingSkeletonSection
                        } else if let error = loadError {
                            errorSection(error)
                        } else if let result = summaryResult {
                            summarySection(result)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                dismissFooter
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: "070607"))
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(streamTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("Started \(minutesElapsed) minute\(minutesElapsed == 1 ? "" : "s") ago")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streamTitle), started \(minutesElapsed) minute\(minutesElapsed == 1 ? "" : "s") ago")
    }

    // MARK: - Length Picker

    private var lengthPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a summary length")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                ForEach(SummaryLength.allCases) { length in
                    LengthCard(
                        length: length,
                        isSelected: selectedLength == length,
                        reduceMotion: reduceMotion
                    ) {
                        selectLength(length)
                    }
                }
            }
        }
    }

    // MARK: - Loading Skeleton

    private var loadingSkeletonSection: some View {
        VStack(spacing: 12) {
            SkeletonBar(width: nil, height: 14)
            SkeletonBar(width: nil, height: 14)
        }
        .padding(.top, 8)
        .accessibilityLabel("Loading summary")
    }

    // MARK: - Error

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.red.opacity(0.7))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let length = selectedLength {
                    fetchSummary(length: length)
                }
            } label: {
                Text("Try Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }
            .accessibilityLabel("Retry loading summary")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(_ result: CatchUpResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Main summary — matte content area (no glass-on-glass)
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .accessibilityAddTraits(.isHeader)

                AttributedSummaryText(
                    summary: result.summary,
                    scriptureRefs: result.scriptureRefs
                )
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
            }

            // Key Topics chips
            if !result.topics.isEmpty {
                chipRowSection(
                    title: "Key Topics",
                    items: result.topics,
                    chipColor: Color(hex: "D9A441")
                )
            }

            // Prayer Requests list
            if !result.prayerRequests.isEmpty {
                bulletListSection(
                    title: "Prayer Requests So Far",
                    icon: "hands.sparkles.fill",
                    items: result.prayerRequests,
                    accentColor: Color(hex: "6E4BB5")
                )
            }

            // Action Items list
            if !result.actionItems.isEmpty {
                bulletListSection(
                    title: "Action Items",
                    icon: "checkmark.circle.fill",
                    items: result.actionItems,
                    accentColor: Color(hex: "D9A441")
                )
            }
        }
    }

    // MARK: - Chip Row

    @ViewBuilder
    private func chipRowSection(title: String, items: [String], chipColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(chipColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule()
                                    .fill(chipColor.opacity(0.14))
                                    .overlay {
                                        Capsule().strokeBorder(chipColor.opacity(0.35), lineWidth: 1)
                                    }
                            }
                            .accessibilityLabel(item)
                    }
                }
            }
        }
    }

    // MARK: - Bullet List

    @ViewBuilder
    private func bulletListSection(title: String, icon: String, items: [String], accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accentColor.opacity(0.55))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel(item)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Dismiss Footer

    private var dismissFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)
            Button(action: onDismiss) {
                Text("Got it, take me in")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .accessibilityLabel("Got it, join the stream")
        }
    }

    // MARK: - Actions

    private func selectLength(_ length: SummaryLength) {
        let anim: Animation? = reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
        withAnimation(anim) {
            selectedLength = length
        }
        fetchSummary(length: length)
    }

    private func fetchSummary(length: SummaryLength) {
        isLoading = true
        summaryResult = nil
        loadError = nil

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let callable = functions.httpsCallable("generateCatchUpSummary")
                let result = try await callable.call([
                    "streamId": streamId,
                    "lengthSeconds": length.lengthSeconds
                ])
                guard let data = result.data as? [String: Any] else {
                    loadError = "Unexpected response format. Please try again."
                    return
                }
                let summary = data["summary"] as? String ?? ""
                let topics = data["topics"] as? [String] ?? []
                let prayerRequests = data["prayerRequests"] as? [String] ?? []
                let actionItems = data["actionItems"] as? [String] ?? []
                let scriptureRefs = data["scriptureRefs"] as? [String] ?? []

                summaryResult = CatchUpResult(
                    summary: summary,
                    topics: topics,
                    prayerRequests: prayerRequests,
                    actionItems: actionItems,
                    scriptureRefs: scriptureRefs
                )
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Length Card

private struct LengthCard: View {
    let length: SummaryLength
    let isSelected: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color(hex: "070607") : Color(hex: "D9A441"))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(length.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: "070607") : .white)
                    Text("Best for: \(length.bestFor)")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color(hex: "070607").opacity(0.7) : .secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "070607").opacity(0.6) : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.clear : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(length.title). Best for: \(length.bestFor)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Attributed Summary Text (highlights scripture refs in gold)

private struct AttributedSummaryText: View {
    let summary: String
    let scriptureRefs: [String]

    var body: some View {
        // Build a Text with inline gold-highlighted scripture references.
        // Falls back gracefully if no refs are present.
        let built = buildText()
        built
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildText() -> Text {
        guard !scriptureRefs.isEmpty else {
            return Text(summary)
        }

        var remaining = summary
        var result = Text("")
        var didHighlight = false

        for ref in scriptureRefs {
            if let range = remaining.range(of: ref) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    result = result + Text(before)
                }
                result = result + Text(ref)
                    .foregroundStyle(Color(hex: "D9A441"))
                    .fontWeight(.semibold)
                remaining = String(remaining[range.upperBound...])
                didHighlight = true
            }
        }

        if !remaining.isEmpty {
            result = result + Text(remaining)
        }

        return didHighlight ? result : Text(summary)
    }
}

// MARK: - Skeleton Bar

private struct SkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    @State private var opacity: Double = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) {
                    opacity = 0.08
                }
            }
    }
}

// MARK: - Preview

#Preview("Length Selection") {
    Color(hex: "070607").ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenCatchMeUpSheet(
                streamId: "stream-001",
                streamTitle: "Sunday Morning Teaching: Grace and Redemption",
                minutesElapsed: 24,
                onDismiss: {}
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("With Result") {
    Color(hex: "070607").ignoresSafeArea()
        .preferredColorScheme(.dark)
}
