// AmenCatchMeUpSheet.swift
// AMEN Connect + Spaces — Late-Joiner AI Catch-Up Sheet

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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let functions = Functions.functions()

    var body: some View {
        VStack(spacing: 0) {
            sheetHandle

            sheetHeader
            Divider()
                .padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
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
                .padding(.top, 16)
            }

            dismissFooter
        }
        .background(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Handle

    private var sheetHandle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.primary.opacity(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(streamTitle)
                .font(.systemScaled(17, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("Started \(minutesElapsed) minute\(minutesElapsed == 1 ? "" : "s") ago")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streamTitle), started \(minutesElapsed) minute\(minutesElapsed == 1 ? "" : "s") ago")
    }

    // MARK: - Length Picker

    private var lengthPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a summary length")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                ForEach(SummaryLength.allCases) { length in
                    LengthCard(
                        length: length,
                        isSelected: selectedLength == length,
                        reduceMotion: reduceMotion,
                        reduceTransparency: reduceTransparency,
                        contrast: contrast
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
            SkeletonBar(width: 200, height: 14)
        }
        .padding(.top, 8)
        .accessibilityLabel("Loading summary")
    }

    // MARK: - Error

    @ViewBuilder
    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(28))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let length = selectedLength { fetchSummary(length: length) }
            } label: {
                Text("Try Again")
                    .font(.systemScaled(14, weight: .semibold))
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
            // Main summary card
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .accessibilityAddTraits(.isHeader)

                AttributedSummaryText(
                    summary: result.summary,
                    scriptureRefs: result.scriptureRefs
                )
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(reduceTransparency ? Color(.systemGray6) : Color(.secondarySystemBackground).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.black.opacity(contrast == .increased ? 0.18 : 0.07), lineWidth: contrast == .increased ? 1 : 0.75)
                        )
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            }

            // Key Topics chips
            if !result.topics.isEmpty {
                chipRowSection(
                    title: "Key Topics",
                    items: result.topics,
                    chipColor: Color(hex: "D9A441")
                )
            }

            // Prayer Requests
            if !result.prayerRequests.isEmpty {
                bulletListSection(
                    title: "Prayer Requests",
                    icon: "hands.sparkles.fill",
                    items: result.prayerRequests,
                    accentColor: Color(hex: "6E4BB5")
                )
            }

            // Action Items
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
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(chipColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(chipColor.opacity(0.10))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(chipColor.opacity(0.30), lineWidth: 1)
                                    )
                            )
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
                    .font(.systemScaled(11))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.systemScaled(12, weight: .semibold))
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
                            .font(.systemScaled(14))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel(item)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(reduceTransparency ? Color(.systemGray6) : Color(.secondarySystemBackground).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accentColor.opacity(contrast == .increased ? 0.25 : 0.12), lineWidth: contrast == .increased ? 1 : 0.75)
                    )
            )
        }
    }

    // MARK: - Dismiss Footer

    private var dismissFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: onDismiss) {
                Text("Got it, take me in")
                    .font(.systemScaled(17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .accessibilityLabel("Got it, join the stream")
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func selectLength(_ length: SummaryLength) {
        let anim: Animation? = reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
        withAnimation(anim) { selectedLength = length }
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
                summaryResult = CatchUpResult(
                    summary: data["summary"] as? String ?? "",
                    topics: data["topics"] as? [String] ?? [],
                    prayerRequests: data["prayerRequests"] as? [String] ?? [],
                    actionItems: data["actionItems"] as? [String] ?? [],
                    scriptureRefs: data["scriptureRefs"] as? [String] ?? []
                )
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Length Card (white Liquid Glass)

private struct LengthCard: View {
    let length: SummaryLength
    let isSelected: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let contrast: ColorSchemeContrast
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "D9A441").opacity(0.15) : Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: "clock.fill")
                        .font(.systemScaled(15))
                        .foregroundStyle(isSelected ? Color(hex: "D9A441") : .secondary)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(length.title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Best for: \(length.bestFor)")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.systemScaled(isSelected ? 16 : 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "D9A441") : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(.systemGray6))
                          : AnyShapeStyle(isSelected ? .thinMaterial : .ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color(hex: "D9A441").opacity(0.5) : Color.black.opacity(contrast == .increased ? 0.18 : 0.07),
                                lineWidth: contrast == .increased ? 1 : 0.75
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: "D9A441").opacity(0.12) : .black.opacity(0.04), radius: isSelected ? 10 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        .accessibilityLabel("\(length.title). Best for: \(length.bestFor)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Attributed Summary Text

private struct AttributedSummaryText: View {
    let summary: String
    let scriptureRefs: [String]

    var body: some View {
        buildText()
            .font(.systemScaled(14))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildText() -> Text {
        guard !scriptureRefs.isEmpty else { return Text(summary) }
        var remaining = summary
        var result = Text("")
        var didHighlight = false
        for ref in scriptureRefs {
            if let range = remaining.range(of: ref) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty { result = result + Text(before) }
                result = result + Text(ref)
                    .foregroundStyle(Color(hex: "D9A441"))
                    .fontWeight(.semibold)
                remaining = String(remaining[range.upperBound...])
                didHighlight = true
            }
        }
        if !remaining.isEmpty { result = result + Text(remaining) }
        return didHighlight ? result : Text(summary)
    }
}

// MARK: - Skeleton Bar

private struct SkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    @State private var opacity: Double = 0.12

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(opacity))
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.04
                }
            }
    }
}

// MARK: - Preview

#Preview {
    Color(.systemBackground).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AmenCatchMeUpSheet(
                streamId: "stream-001",
                streamTitle: "Men's Bible Study: Romans 8",
                minutesElapsed: 24,
                onDismiss: {}
            )
        }
}
