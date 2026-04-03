// KoraRootView.swift
// AMENAPP
//
// Root view for the Kora spiritual accountability circles feature.

import SwiftUI
import FirebaseFirestore

struct KoraRootView: View {
    @StateObject private var vm = KoraViewModel()
    @State private var showCreateSheet = false
    @State private var pulsing = false
    @State private var selectedCircleId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(hex: "0A0A0F").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Active check-in banner
                        if !vm.activeCheckIns.isEmpty {
                            activeCheckInBanner
                                .padding(.horizontal, 16)
                        }

                        // Circle chips horizontal scroll
                        if !vm.circles.isEmpty {
                            circleChipsRow
                        }

                        // Main circle cards
                        if vm.isLoading {
                            loadingState
                        } else if vm.circles.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(vm.circles) { circle in
                                    NavigationLink(value: circle) {
                                        KoraCircleCardView(
                                            circle: circle,
                                            hasOpenCheckIn: vm.activeCheckIns.contains { $0.circleId == circle.id }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.top, 8)
                }

                // FAB
                fabButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Kora")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: KoraCircle.self) { circle in
                KoraCircleDetailView(circle: circle, vm: vm)
            }
            .sheet(isPresented: $showCreateSheet) {
                KoraCreateCircleSheet(vm: vm)
            }
        }
        .task {
            await vm.loadCircles()
        }
    }

    // MARK: - Subviews

    private var activeCheckInBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "F59E0B").opacity(0.25))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulsing ? 1.35 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                        value: pulsing
                    )
                Circle()
                    .fill(Color(hex: "F59E0B"))
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("A check-in is waiting ✦")
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.white)
                Text("\(vm.activeCheckIns.count) circle\(vm.activeCheckIns.count == 1 ? "" : "s") waiting for your response")
                    .font(AMENFont.regular(12))
                    .foregroundColor(Color(hex: "F59E0B").opacity(0.85))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(Color(hex: "F59E0B").opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "F59E0B").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "F59E0B").opacity(0.28), lineWidth: 0.8)
                )
        )
        .onAppear { pulsing = true }
    }

    private var circleChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vm.circles) { circle in
                    KoraCircleChipView(circle: circle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "hands.sparkles.fill")
                .font(.systemScaled(52))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Circles are where real\nconversations happen")
                    .font(AMENFont.semiBold(18))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Gather a few people. Check in regularly.\nGrow together.")
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreateSheet = true
            } label: {
                Text("Start one")
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(CoCreationPressStyle())
        }
        .padding(.horizontal, 32)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 130)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var fabButton: some View {
        Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                showCreateSheet = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(hex: "F59E0B").opacity(0.4), radius: 12, x: 0, y: 4)

                Image(systemName: "plus")
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(CoCreationPressStyle())
    }
}

// MARK: - Circle Chip

struct KoraCircleChipView: View {
    let circle: KoraCircle

    private var daysUntilNextCheckIn: Int {
        let diff = circle.nextCheckInAt.timeIntervalSinceNow
        return max(0, Int(ceil(diff / 86400)))
    }

    var body: some View {
        HStack(spacing: 8) {
            // Color accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: circle.coverColorHex))
                .frame(width: 3, height: 22)

            Text(circle.name)
                .font(AMENFont.semiBold(13))
                .foregroundColor(.white)
                .lineLimit(1)

            Text("in \(daysUntilNextCheckIn)d")
                .font(AMENFont.regular(11))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(Capsule())
    }
}
