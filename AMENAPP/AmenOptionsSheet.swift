//
//  AmenOptionsSheet.swift
//  AMENAPP
//
//  Premium Liquid Glass options sheet for AMEN.
//

import SwiftUI

// MARK: - Data Models

struct AmenOptionAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let isDestructive: Bool
    let showsChevron: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        isDestructive: Bool = false,
        showsChevron: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.showsChevron = showsChevron
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct AmenQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
}

struct AmenOptionsSectionModel: Identifiable {
    let id = UUID()
    let title: String?
    let actions: [AmenOptionAction]

    init(title: String? = nil, actions: [AmenOptionAction]) {
        self.title = title
        self.actions = actions
    }
}

// MARK: - Amen Options Sheet

struct AmenOptionsSheet: View {
    @Binding var isPresented: Bool
    let title: String?
    let subtitle: String?
    let quickActions: [AmenQuickAction]
    let sections: [AmenOptionsSectionModel]

    @State private var dragOffset: CGFloat = 0
    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismiss() }

                sheetContent
                    .offset(y: isVisible ? max(dragOffset, 0) : 400)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .gesture(dragGesture)
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: isPresented)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: dragOffset)
        .onChange(of: isPresented) { _, newValue in
            if newValue {
                isVisible = true
            } else {
                isVisible = false
                dragOffset = 0
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var sheetContent: some View {
        VStack(spacing: 14) {
            grabber

            if title != nil || subtitle != nil {
                VStack(spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
            }

            if !quickActions.isEmpty {
                AmenQuickActionsRow(actions: quickActions)
            }

            VStack(spacing: 12) {
                ForEach(sections) { section in
                    AmenOptionsSection(model: section)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 36, x: 0, y: 18)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.black.opacity(0.12))
            .frame(width: 42, height: 5)
            .padding(.top, 2)
    }

    private var sheetBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.88), location: 0.0),
                            .init(color: Color.white.opacity(0.72), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.40), location: 0.0),
                            .init(color: Color.white.opacity(0.00), location: 0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                if value.translation.height > 140 || predicted > 180 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isPresented = false
        }
    }
}

// MARK: - Quick Actions Row

private struct AmenQuickActionsRow: View {
    let actions: [AmenQuickAction]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(actions) { action in
                AmenQuickActionTile(action: action)
            }
        }
    }
}

// MARK: - Amen Quick Action Tile

struct AmenQuickActionTile: View {
    let action: AmenQuickAction

    @State private var pressScale: CGFloat = 1.0
    @State private var pressTask: Task<Void, Never>? = nil

    var body: some View {
        Button {
            guard action.isEnabled else { return }
            action.action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(action.isEnabled ? 0.9 : 0.35))
                    .frame(width: 30, height: 30)

                Text(action.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(action.isEnabled ? 0.75 : 0.35))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tileBackground)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressScale)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard action.isEnabled else { return }
                    pressTask?.cancel()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        pressScale = 0.98
                    }
                }
                .onEnded { _ in
                    guard action.isEnabled else { return }
                    pressTask?.cancel()
                    pressTask = Task { @MainActor in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                            pressScale = 1.02
                        }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            pressScale = 1.0
                        }
                    }
                }
        )
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(action.isSelected ? 0.75 : 0.60))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(action.isSelected ? 0.12 : 0.06), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Options Section

struct AmenOptionsSection: View {
    let model: AmenOptionsSectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = model.title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 6)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                    AmenOptionRow(action: action)
                    if index < model.actions.count - 1 {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(6)
            .background(sectionBackground)
        }
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Options Row

struct AmenOptionRow: View {
    let action: AmenOptionAction

    @State private var pressScale: CGFloat = 1.0
    @State private var pressTask: Task<Void, Never>? = nil

    var body: some View {
        Button {
            guard action.isEnabled else { return }
            action.action()
        } label: {
            HStack(spacing: 12) {
                iconWell

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(titleColor)

                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.5))
                    }
                }

                Spacer()

                if action.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(minHeight: action.subtitle == nil ? 64 : 72)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .scaleEffect(pressScale)
        .opacity(action.isEnabled ? 1.0 : 0.55)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard action.isEnabled else { return }
                    pressTask?.cancel()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        pressScale = 0.98
                    }
                }
                .onEnded { _ in
                    guard action.isEnabled else { return }
                    pressTask?.cancel()
                    pressTask = Task { @MainActor in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                            pressScale = 1.02
                        }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            pressScale = 1.0
                        }
                    }
                }
        )
    }

    private var titleColor: Color {
        if action.isDestructive {
            return Color.red.opacity(0.85)
        }
        return Color.black.opacity(0.9)
    }

    private var iconWell: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.7))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(action.isDestructive ? Color.red.opacity(0.85) : Color.black.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 0.6)
            )
    }
}

// MARK: - Preview

#Preview {
    let quickActions = [
        AmenQuickAction(title: "Save", systemImage: "bookmark"),
        AmenQuickAction(title: "Remix", systemImage: "arrow.triangle.2.circlepath"),
        AmenQuickAction(title: "Sequence", systemImage: "sparkles")
    ]

    let sections = [
        AmenOptionsSectionModel(title: "Primary", actions: [
            AmenOptionAction(title: "Share", subtitle: "Send to friends or outside AMEN", systemImage: "square.and.arrow.up"),
            AmenOptionAction(title: "Discuss", subtitle: "Open the reasoning thread", systemImage: "bubble.left.and.text.bubble.right"),
            AmenOptionAction(title: "Copy Link", systemImage: "link")
        ]),
        AmenOptionsSectionModel(title: "Feed & Safety", actions: [
            AmenOptionAction(title: "Not Interested", subtitle: "See fewer posts like this", systemImage: "eye.slash"),
            AmenOptionAction(title: "Report", subtitle: "Let us know what's wrong", systemImage: "exclamationmark.triangle", isDestructive: true)
        ])
    ]

    ZStack {
        LinearGradient(colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        AmenOptionsSheet(
            isPresented: .constant(true),
            title: "Post Options",
            subtitle: "Calm, clear, and in your control",
            quickActions: quickActions,
            sections: sections
        )
    }
}
