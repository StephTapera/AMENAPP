//
//  CoCreationHubView.swift
//  AMENAPP
//
//  Faith-centered collaborative creation hub — songs, prayers, scripture studies.
//

import SwiftUI
import FirebaseAuth

// MARK: - Constants

private let amenPink    = Color(red: 0.94, green: 0.28, blue: 0.64)
private let amenDark    = Color(.systemGroupedBackground)

// MARK: - CoCreationHubView

struct CoCreationHubView: View {

    @StateObject private var vm            = CoCreationViewModel()
    @State private var showStartSheet      = false
    @State private var selectedSession: CoCreationSession? = nil
    @State private var showLiveSession     = false

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 24) {

                        // ── Hero Card ─────────────────────────────────
                        heroCard

                        // ── Live Sessions ─────────────────────────────
                        sectionHeader(
                            title: "Live Sessions",
                            subtitle: "Join an active session"
                        )

                        if vm.activeSessions.isEmpty {
                            liveEmptyState
                        } else {
                            ForEach(vm.activeSessions) { session in
                                LiveSessionCard(session: session) {
                                    Task {
                                        await vm.joinSession(session)
                                        selectedSession = session
                                        showLiveSession = true
                                    }
                                }
                            }
                        }

                        // ── Your Sessions ─────────────────────────────
                        sectionHeader(
                            title: "Your Sessions",
                            subtitle: nil
                        )

                        yourSessionsRow

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Create Together")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { vm.loadSessions() }
            .sheet(isPresented: $showStartSheet) {
                StartCoCreationSheet(vm: vm) { session in
                    selectedSession = session
                    showLiveSession = true
                }
            }
            .fullScreenCover(isPresented: $showLiveSession) {
                if let s = selectedSession {
                    LiveCoCreationView(session: s, vm: vm)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        Button {
            showStartSheet = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, amenPink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 20, y: 8)

                VStack(spacing: 16) {
                    // Icon row
                    HStack(spacing: 20) {
                        Image(systemName: "music.note")
                            .font(.systemScaled(28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(32, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Image(systemName: "pencil.line")
                            .font(.systemScaled(28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .foregroundStyle(.white)

                    VStack(spacing: 6) {
                        Text("Create Together")
                            .font(AMENFont.bold(26))
                            .foregroundStyle(.white)
                        Text("Song, Prayer, Scripture Study & more")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    // CTA button
                    Text("Start a Session")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        )
                        .padding(.top, 4)
                }
                .padding(28)
            }
        }
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Live Empty State

    private var liveEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.systemScaled(36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text("No live sessions right now")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.white)

            Text("Start the first one!")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Your Sessions Horizontal Row

    private var yourSessionsRow: some View {
        Group {
            if vm.sessions.isEmpty {
                Text("Sessions you start will appear here.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.sessions) { session in
                            YourSessionCard(session: session)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AMENFont.bold(20))
                .foregroundStyle(.white)
            if let sub = subtitle {
                Text(sub)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live Session Card

private struct LiveSessionCard: View {

    let session: CoCreationSession
    let onJoin: () -> Void

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 14) {

            // Type icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: session.type.gradient.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: session.type.icon)
                    .font(.systemScaled(20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // LIVE badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulsing ? 1.35 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                value: pulsing
                            )
                        Text("LIVE")
                            .font(AMENFont.bold(10))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.15)))
                }

                HStack(spacing: 8) {
                    Text("by \(session.hostName)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.55))

                    Text(session.type.label)
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                // Collaborator count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.systemScaled(11))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("\(session.collaboratorIds.count) collaborating")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            // Join button
            Button(action: onJoin) {
                Text("Join")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 3)
                    )
            }
            .buttonStyle(CoCreationPressStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear { pulsing = true }
    }
}

// MARK: - Your Session Card (Horizontal)

private struct YourSessionCard: View {

    let session: CoCreationSession

    private var statusLabel: String { session.isLive ? "Live" : "Ended" }
    private var statusColor: Color  { session.isLive ? .green : .white.opacity(0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: session.type.gradient.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: session.type.icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }

            Text(session.title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusLabel)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let date = session.createdAt {
                Text(date, style: .date)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .padding(14)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Press Button Style

struct CoCreationPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Session Type defaults removed - no longer needed

