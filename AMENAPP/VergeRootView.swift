//
//  VergeRootView.swift
//  AMENAPP
//
//  Root navigation hub for Verge live rooms.
//

import SwiftUI
import FirebaseAuth

struct VergeRootView: View {

    @StateObject private var vm = VergeViewModel()
    @State private var showCreateSheet   = false
    @State private var selectedRoom: VergeRoom?
    @State private var showCreatorStudio = false

    private let bg         = Color(hex: "0A0A0F")
    private let Color.accentColor = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let Color.accentColor   = Color(hex: "F59E0B")
    private let vergeGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                bg.ignoresSafeArea()

                if vm.isLoading {
                    loadingView
                } else if vm.liveRooms.isEmpty && vm.upcomingRooms.isEmpty && vm.pastRooms.isEmpty {
                    emptyState
                } else {
                    mainScrollContent
                }

                // FAB — Go Live
                goLiveButton
            }
            .navigationTitle("Verge")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showCreateSheet) {
                VergeCreateRoomSheet(vm: vm)
            }
            .sheet(isPresented: $showCreatorStudio) {
                VergeCreatorStudioView(vm: vm)
            }
            .navigationDestination(item: $selectedRoom) { room in
                VergeRoomView(room: room)
            }
        }
        .preferredColorScheme(.dark)
        .task { vm.loadRooms(workspaceId: "default") }
        .task {
            if let uid = Auth.auth().currentUser?.uid {
                await vm.loadCreatorProfile(userId: uid)
            }
        }
    }

    // MARK: - Main Scroll

    private var mainScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {

                // Creator earnings banner
                if let profile = vm.creatorProfile {
                    creatorBanner(profile: profile)
                        .padding(.horizontal, 16)
                }

                // Live Now
                liveSectionHeader
                if vm.liveRooms.isEmpty {
                    Text("No live rooms right now")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                } else {
                    liveHorizontalScroll
                }

                // Upcoming
                if !vm.upcomingRooms.isEmpty {
                    sectionLabel("Upcoming")
                    LazyVStack(spacing: 12) {
                        ForEach(vm.upcomingRooms) { room in
                            VergeRoomCardView(room: room) {
                                Task { try? await vm.joinRoom(room) }
                                selectedRoom = room
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Past
                if !vm.pastRooms.isEmpty {
                    sectionLabel("Past Rooms")
                    LazyVStack(spacing: 12) {
                        ForEach(vm.pastRooms) { room in
                            VergeRoomCardView(room: room) {
                                selectedRoom = room
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Live Section Header

    private var liveSectionHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("LIVE NOW")
                .font(AMENFont.bold(12))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(1.2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Live Horizontal Scroll

    private var liveHorizontalScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.liveRooms) { room in
                    VergeRoomCardView(room: room) {
                        Task { try? await vm.joinRoom(room) }
                        selectedRoom = room
                    }
                    .frame(width: 280)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Creator Banner

    @ViewBuilder
    private func creatorBanner(profile: VergeCreatorProfile) -> some View {
        Button {
            showCreatorStudio = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.systemScaled(28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("You earned \(profile.monthlyRevenue.formatted(.currency(code: "USD"))) this month")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)
                    Text("View Creator Studio")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AMENFont.bold(18))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
    }

    // MARK: - FAB

    private var goLiveButton: some View {
        Button {
            showCreateSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.systemScaled(15, weight: .semibold))
                Text("Go Live")
                    .font(AMENFont.bold(15))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(vergeGradient)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 16, y: 6)
            )
        }
        .buttonStyle(CoCreationPressStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 30)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(amenViolet)
                .scaleEffect(1.4)
            Text("Loading rooms…")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "video.fill")
                .font(.systemScaled(52, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Start a live discussion")
                .font(AMENFont.bold(22))
                .foregroundStyle(.white)
            Text("Host scripture studies, Q&As, and workshops\nwith your community.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button {
                showCreateSheet = true
            } label: {
                Text("Go Live Now")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(Capsule().fill(vergeGradient))
            }
            .buttonStyle(CoCreationPressStyle())
            .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
