//
//  ThoughtTrailsView.swift
//  AMENAPP
//
//  Theme Memory system — shows recurring themes across Selah sessions,
//  lets users browse their trail of reflections, and surfaces patterns
//  in their spiritual journey.
//

import SwiftUI

struct ThoughtTrailsView: View {
    @ObservedObject private var selahService = SelahService.shared
    @State private var selectedTheme: ThemeTag?
    @State private var selectedSession: SelahSession?
    @State private var showSessionDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Theme cloud
                if !selahService.themes.isEmpty {
                    themeCloudSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }

                // Filtered sessions or all sessions
                sessionTrailSection
                    .padding(.horizontal, 20)

                Spacer(minLength: 48)
            }
        }
    }

    // MARK: - Theme Cloud

    private var themeCloudSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR THEMES")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Spacer()

                if selectedTheme != nil {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                            selectedTheme = nil
                        }
                    } label: {
                        Text("Show All")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Flow layout of theme chips
            themeChipsGrid
        }
    }

    private var themeChipsGrid: some View {
        let themes = selahService.themes
        return SelahWrappingHStack(items: themes) { theme in
            ThemeTagChip(
                theme: theme,
                isSelected: selectedTheme?.name == theme.name
            ) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                    if selectedTheme?.name == theme.name {
                        selectedTheme = nil
                    } else {
                        selectedTheme = theme
                    }
                }
            }
        }
    }

    // MARK: - Session Trail

    private var sessionTrailSection: some View {
        let filteredSessions: [SelahSession]
        if let theme = selectedTheme {
            filteredSessions = selahService.sessions(forTheme: theme.name)
        } else {
            filteredSessions = selahService.sessions
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedTheme != nil ? "SESSIONS: \(selectedTheme!.name.uppercased())" : "RECENT SESSIONS")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(filteredSessions.count)")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            if filteredSessions.isEmpty {
                emptyTrailState
            } else {
                ForEach(filteredSessions) { session in
                    SessionTrailCard(session: session) {
                        selectedSession = session
                        showSessionDetail = true
                    }
                }
            }
        }
        .sheet(isPresented: $showSessionDetail) {
            if let session = selectedSession {
                SessionDetailSheet(session: session)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var emptyTrailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.systemScaled(32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.35))
            Text("No trails yet")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Your Selah sessions will appear here,\nrevealing patterns in your journey.")
                .font(.systemScaled(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Theme Tag Chip

struct ThemeTagChip: View {
    let theme: ThemeTag
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(theme.color)
                    .frame(width: 6, height: 6)
                Text(theme.name)
                    .font(.systemScaled(12, weight: isSelected ? .semibold : .medium))
                Text("(\(theme.count))")
                    .font(.systemScaled(10))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? theme.color.opacity(0.15) : Color.primary.opacity(0.04))
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? theme.color.opacity(0.30) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Trail Card

struct SessionTrailCard: View {
    let session: SelahSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Title and date
                HStack {
                    Text(session.title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(session.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }

                // Preview
                if !session.responsePreview.isEmpty {
                    Text(session.responsePreview)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                // Tags + refs
                HStack(spacing: 6) {
                    // Scripture refs
                    ForEach(session.scriptureRefs.prefix(2), id: \.self) { ref in
                        HStack(spacing: 3) {
                            Image(systemName: "book.fill")
                                .font(.systemScaled(8))
                            Text(ref)
                                .font(.systemScaled(10, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                    }

                    // Theme tags
                    ForEach(session.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.systemScaled(10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.40), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Detail Sheet

private struct SessionDetailSheet: View {
    let session: SelahSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Query
                    if !session.query.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QUESTION")
                                .font(.systemScaled(10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                            Text(session.query)
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }

                    // Response preview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESPONSE")
                            .font(.systemScaled(10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                        Text(session.responsePreview)
                            .font(.systemScaled(14))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }

                    // Scripture references
                    if !session.scriptureRefs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SCRIPTURE")
                                .font(.systemScaled(10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(session.scriptureRefs, id: \.self) { ref in
                                        HStack(spacing: 4) {
                                            Image(systemName: "book.fill")
                                                .font(.systemScaled(10))
                                            Text(ref)
                                                .font(.systemScaled(12, weight: .semibold))
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Tags
                    if !session.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("THEMES")
                                .font(.systemScaled(10, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(session.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.systemScaled(12, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.06), in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Date + format
                    HStack(spacing: 12) {
                        Label(session.createdAt.formatted(.dateTime.month(.abbreviated).day().year()), systemImage: "calendar")
                        Label(session.format, systemImage: "doc.text")
                    }
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.systemScaled(14, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Wrapping HStack (Flow Layout)

/// Simple wrapping horizontal stack for theme chips.
private struct SelahWrappingHStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                content(item)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= d.height + 6
                        }
                        let result = width
                        if item.id as AnyHashable == items.last?.id as AnyHashable {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item.id as AnyHashable == items.last?.id as AnyHashable {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async {
                binding.wrappedValue = geo.frame(in: .local).size.height
            }
            return Color.clear
        }
    }
}
