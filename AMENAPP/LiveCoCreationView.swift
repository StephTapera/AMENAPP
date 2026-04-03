//
//  LiveCoCreationView.swift
//  AMENAPP
//
//  Full-screen immersive co-creation session.
//

import SwiftUI

// MARK: - LiveCoCreationView

struct LiveCoCreationView: View {

    let session: CoCreationSession
    @ObservedObject var vm: CoCreationViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showAISuggestionSheet = false
    @State private var showEndConfirm        = false
    @State private var showSummary           = false

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    // Avatar tints per collaborator index
    private let avatarColors: [Color] = [
        Color(red: 0.42, green: 0.28, blue: 1.00),
        Color(red: 0.94, green: 0.28, blue: 0.64),
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.20, green: 0.70, blue: 0.50),
        Color(red: 0.20, green: 0.55, blue: 0.95),
        Color(red: 0.90, green: 0.40, blue: 0.20),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            amenDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top Bar ───────────────────────────────────────────
                topBar

                // ── Canvas ────────────────────────────────────────────
                CoCreationCanvasView(vm: vm)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                // ── Bottom Toolbar ────────────────────────────────────
                bottomToolbar
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showAISuggestionSheet) {
            AISuggestionSheet(vm: vm)
        }
        .confirmationDialog(
            "End Session?",
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                Task {
                    await vm.endSession()
                    showSummary = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close the session for all collaborators.")
        }
        .fullScreenCover(isPresented: $showSummary) {
            CoCreationSummaryView(session: session, vm: vm)
        }
        .onAppear {
            vm.startCanvasListener(sessionId: session.id ?? "")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Title
                Text(session.title)
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Timer
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.systemScaled(13))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(vm.elapsedFormatted)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))

                // End button
                Button {
                    showEndConfirm = true
                } label: {
                    Text("End")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(CoCreationPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            // Collaborator avatars
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -8) {
                    ForEach(Array(session.collaboratorIds.enumerated()), id: \.offset) { idx, uid in
                        CollaboratorAvatar(
                            initial: String(uid.prefix(1)).uppercased(),
                            color: avatarColors[idx % avatarColors.count]
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            // Ask AI
            toolbarButton(icon: "sparkles", label: "Ask AI", tint: amenPurple) {
                showAISuggestionSheet = true
            }

            Divider()
                .frame(height: 28)
                .opacity(0.2)

            // Bold
            toolbarButton(icon: "bold", label: "Bold", tint: .white.opacity(0.7)) {}

            // Italic
            toolbarButton(icon: "italic", label: "Italic", tint: .white.opacity(0.7)) {}

            Divider()
                .frame(height: 28)
                .opacity(0.2)

            // Photo
            toolbarButton(icon: "photo", label: "Photo", tint: .white.opacity(0.7)) {}

            // Emoji
            toolbarButton(icon: "face.smiling", label: "React", tint: .white.opacity(0.7)) {}
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.15)
        }
    }

    @ViewBuilder
    private func toolbarButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.systemScaled(19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Text(label)
                    .font(AMENFont.regular(10))
                    .foregroundStyle(tint.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(CoCreationPressStyle())
    }
}

// MARK: - Collaborator Avatar

private struct CollaboratorAvatar: View {
    let initial: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color(red: 0.06, green: 0.06, blue: 0.09), lineWidth: 2))

            Text(initial)
                .font(AMENFont.bold(12))
                .foregroundStyle(.white)

            // Active pulse dot
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color(red: 0.06, green: 0.06, blue: 0.09), lineWidth: 1.5))
                .offset(x: 9, y: 9)
        }
        .frame(width: 30, height: 30)
    }
}
