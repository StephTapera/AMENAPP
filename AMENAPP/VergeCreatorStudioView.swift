//
//  VergeCreatorStudioView.swift
//  AMENAPP
//
//  Creator monetisation dashboard inside Verge.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct VergeCreatorStudioView: View {

    @ObservedObject var vm: VergeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var subscriptionPriceText = ""
    @State private var tipsEnabled           = true
    @State private var isSavingPrice         = false
    @State private var isRefreshingAI        = false
    @State private var saveSuccess           = false

    private let bg         = Color(hex: "0A0A0F")
    private let amenPurple = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let amenGold   = Color(hex: "F59E0B")
    private let vergeGradient = LinearGradient(
        colors: [Color(hex: "06B6D4"), Color(hex: "6B48FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        earningsHeroCard
                        metricsGrid
                        aiForecastCard
                        monetizationSettings
                        pastRoomsList
                        refreshAIButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Creator Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let profile = vm.creatorProfile {
                subscriptionPriceText = profile.subscriptionPrice.map {
                    String(format: "%.0f", $0)
                } ?? ""
                tipsEnabled = profile.tipsEnabled
            }
        }
    }

    // MARK: - Earnings Hero Card

    private var earningsHeroCard: some View {
        VStack(spacing: 4) {
            Text("This Month")
                .font(AMENFont.regular(13))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.8)
            Text(vm.creatorProfile?.monthlyRevenue.formatted(.currency(code: "USD")) ?? "$0.00")
                .font(AMENFont.bold(46))
                .foregroundStyle(.white)
            Text("Lifetime: \(lifetimeFormatted)")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(vergeGradient.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(amenPurple.opacity(0.3), lineWidth: 0.8)
                )
        )
    }

    // MARK: - 2×2 Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(
                icon: "person.2.fill",
                label: "Subscribers",
                value: "\(vm.creatorProfile?.subscriberCount ?? 0)",
                color: amenViolet
            )
            metricCard(
                icon: "gift.fill",
                label: "Tips Received",
                value: vm.creatorProfile?.totalTipsReceived.formatted(.currency(code: "USD")) ?? "$0",
                color: amenGold
            )
            metricCard(
                icon: "video.fill",
                label: "Rooms Hosted",
                value: "\(vm.pastRooms.count)",
                color: Color(hex: "06B6D4")
            )
            metricCard(
                icon: "person.3.fill",
                label: "Total Attendees",
                value: "\(totalAttendees)",
                color: Color.green.opacity(0.9)
            )
        }
    }

    private func metricCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            Text(value)
                .font(AMENFont.bold(22))
                .foregroundStyle(.white)
            Text(label)
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(glassCard)
    }

    // MARK: - AI Forecast Card

    private var aiForecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(amenViolet)
                Text("AI Forecast")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.white)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projected Revenue")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(vm.creatorProfile?.aiRevenueProjection.formatted(.currency(code: "USD")) ?? "–")
                        .font(AMENFont.bold(24))
                        .foregroundStyle(amenGold)
                }
                Spacer()
            }

            if let next = vm.creatorProfile?.aiNextMove, !next.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Move")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(amenViolet.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(next)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(amenViolet.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(amenViolet.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(16)
        .background(glassCard)
    }

    // MARK: - Monetization Settings

    private var monetizationSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monetization Settings")
                .font(AMENFont.bold(15))
                .foregroundStyle(.white)

            // Subscription price
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Subscription Price")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 10) {
                    Text("$")
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("e.g. 4.99", text: $subscriptionPriceText)
                        .font(AMENFont.semiBold(17))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                    Spacer()
                    Button {
                        saveSubscriptionPrice()
                    } label: {
                        Group {
                            if isSavingPrice {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else if saveSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                            } else {
                                Text("Save")
                                    .font(AMENFont.bold(14))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(amenPurple))
                    }
                    .buttonStyle(CoCreationPressStyle())
                    .disabled(isSavingPrice)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }

            // Tip jar toggle
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.systemScaled(17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(amenGold)
                Text("Tip Jar")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Toggle("", isOn: $tipsEnabled)
                    .labelsHidden()
                    .tint(amenPurple)
                    .onChange(of: tipsEnabled) { _ in saveTipsEnabled() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .padding(16)
        .background(glassCard)
    }

    // MARK: - Past Rooms List

    private var pastRoomsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Rooms")
                .font(AMENFont.bold(15))
                .foregroundStyle(.white)

            if vm.pastRooms.isEmpty {
                Text("No past rooms yet.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.pastRooms) { room in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(room.title)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(room.participantCount) attendees")
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Text("$0")
                                .font(AMENFont.bold(15))
                                .foregroundStyle(amenGold.opacity(0.7))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(glassCard)
    }

    // MARK: - Refresh AI Button

    private var refreshAIButton: some View {
        Button {
            isRefreshingAI = true
            Task {
                _ = await vm.generateRoomSummary(roomId: "studio", messages: [])
                isRefreshingAI = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRefreshingAI {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.systemScaled(14, weight: .semibold))
                    Text("Refresh AI Projection")
                        .font(AMENFont.bold(15))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(amenViolet.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(amenViolet.opacity(0.3), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(CoCreationPressStyle())
        .disabled(isRefreshingAI)
    }

    // MARK: - Helpers

    private var lifetimeFormatted: String {
        guard let profile = vm.creatorProfile else { return "$0.00" }
        let total = profile.monthlyRevenue + profile.totalTipsReceived
        return total.formatted(.currency(code: "USD"))
    }

    private var totalAttendees: Int {
        vm.pastRooms.reduce(0) { $0 + $1.participantCount }
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private func saveSubscriptionPrice() {
        guard let uid = Auth.auth().currentUser?.uid,
              let profileId = vm.creatorProfile?.id else { return }
        let price = Double(subscriptionPriceText) ?? 0
        isSavingPrice = true
        lazy var db = Firestore.firestore()
        db.collection("vergeCreatorProfiles").document(profileId).updateData([
            "subscriptionPrice": price
        ]) { _ in
            Task { @MainActor in
                isSavingPrice = false
                withAnimation(reduceMotion ? nil : .default) {
                    saveSuccess = true
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(reduceMotion ? nil : .default) { saveSuccess = false }
                await vm.loadCreatorProfile(userId: uid)
            }
        }
    }

    private func saveTipsEnabled() {
        guard let uid = Auth.auth().currentUser?.uid,
              let profileId = vm.creatorProfile?.id else { return }
        lazy var db = Firestore.firestore()
        db.collection("vergeCreatorProfiles").document(profileId).updateData([
            "tipsEnabled": tipsEnabled
        ]) { _ in
            Task { @MainActor in
                await vm.loadCreatorProfile(userId: uid)
            }
        }
    }
}
