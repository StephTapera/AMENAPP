//
//  AMENAccountTypeOnboardingView.swift
//  AMENAPP
//
//  Account type selection screen shown after initial account creation.
//  The user picks Personal, Church, or Business/Ministry — each unlocking
//  a distinct capability set. Selection is persisted to UserDefaults.
//  Firebase wiring is deferred to a later sprint.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Account Type Model

enum AMENAccountType: String, CaseIterable, Identifiable {
    case personal = "Personal"
    case church   = "Church"
    case business = "Business"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .church:   return "building.columns.fill"
        case .business: return "briefcase.fill"
        }
    }

    var tagline: String {
        switch self {
        case .personal: return "Your faith journey, your way"
        case .church:   return "Lead, connect, and equip your congregation"
        case .business: return "Grow your ministry or faith-based organization"
        }
    }

    var capabilities: [String] {
        switch self {
        case .personal:
            return [
                "Post and share",
                "Join communities",
                "Berean AI",
                "Church Notes",
                "Scripture study",
                "Prayer wall"
            ]
        case .church:
            return [
                "Everything in Personal",
                "Official church profile",
                "Service times and location",
                "Sermons and announcements",
                "Event management",
                "Member and community tools"
            ]
        case .business:
            return [
                "Everything in Personal",
                "Professional profile",
                "Featured resources or offerings",
                "Analytics and insights",
                "Partnership tools",
                "Store and resources expansion"
            ]
        }
    }

    /// One-line description of the operational layer this account type unlocks.
    var operationalLayerDescription: String {
        switch self {
        case .personal: return "Individual spiritual life"
        case .church:   return "Shepherding and community leadership"
        case .business: return "Mission, organization, and growth tools"
        }
    }

    var badgeColor: Color {
        switch self {
        case .personal: return Color(red: 0.30, green: 0.50, blue: 0.90)
        case .church:   return Color(red: 0.35, green: 0.30, blue: 0.90)
        case .business: return Color(red: 0.85, green: 0.45, blue: 0.20)
        }
    }

    /// Returns the pill label for Church / Business. `nil` for Personal.
    var badgePillLabel: String? {
        switch self {
        case .personal: return nil
        case .church:   return "Verification required"
        case .business: return "Pro features"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AMENAccountTypeViewModel: ObservableObject {
    @Published var selectedType: AMENAccountType? = nil
    @Published var isSubmitting: Bool = false
    @Published var showExtendedOnboarding: Bool = false

    func selectType(_ type: AMENAccountType) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            selectedType = type
        }
    }

    func confirm() async -> Bool {
        guard let type = selectedType else { return false }
        isSubmitting = true
        let selectedValue = type.rawValue
        UserDefaults.standard.set(selectedValue, forKey: "amenAccountType")

        if let uid = Auth.auth().currentUser?.uid {
            let data: [String: Any] = [
                "accountType": selectedValue,
                "accountTypeSelectedAt": Timestamp(date: Date()),
                "accountTypeOnboardingComplete": type == .personal // Only complete for Personal
            ]
            do {
                try await Firestore.firestore()
                    .document("users/\(uid)")
                    .setData(data, merge: true)
            } catch {
                dlog("⚠️ Account type save failed: \(error.localizedDescription)")
            }
        }

        AMENAnalyticsService.shared.track(.accountTypeSelected(type: selectedValue))
        try? await Task.sleep(nanoseconds: 300_000_000)
        isSubmitting = false
        
        // Return true if Church/Business needs extended onboarding
        return type == .church || type == .business
    }
}

// MARK: - Main Screen

struct AMENAccountTypeOnboardingView: View {
    @StateObject private var vm = AMENAccountTypeViewModel()

    /// Gating flag — set true after the user confirms their selection.
    @AppStorage("amenAccountTypeOnboardingComplete") private var onboardingComplete: Bool = false

    /// Entrance animation state for each card.
    @State private var cardOffsets: [Bool] = [false, false, false]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: Header
                        headerSection
                            .padding(.top, 16)

                        // MARK: Account Type Cards
                        VStack(spacing: 12) {
                            ForEach(Array(AMENAccountType.allCases.enumerated()), id: \.element.id) { index, type in
                                Button {
                                    vm.selectType(type)
                                } label: {
                                    AccountTypeCard(
                                        type: type,
                                        isSelected: vm.selectedType == type
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .offset(y: cardOffsets[index] ? 0 : 30)
                                .opacity(cardOffsets[index] ? 1 : 0)
                            }
                        }

                        // MARK: Capabilities Reveal
                        if let selected = vm.selectedType {
                            CapabilitiesCard(type: selected)
                                .transition(
                                    .move(edge: .bottom).combined(with: .opacity)
                                )
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 32)

                        // MARK: CTA
                        ContinueButton(
                            label: "Get Started",
                            isEnabled: vm.selectedType != nil,
                            isSubmitting: vm.isSubmitting
                        ) {
                            Task {
                                let needsExtendedOnboarding = await vm.confirm()
                                if needsExtendedOnboarding {
                                    vm.showExtendedOnboarding = true
                                } else {
                                    onboardingComplete = true
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear { triggerEntranceAnimations() }
            .sheet(isPresented: $vm.showExtendedOnboarding) {
                if let selectedType = vm.selectedType {
                    AMENChurchBusinessOnboardingView(accountType: selectedType)
                }
            }
        }
    }

    // MARK: Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCOUNT TYPE")
                .font(AMENFont.semiBold(11))
                .foregroundColor(Color(white: 0.55))
                .tracking(1.6)

            Text("How will you use AMEN?")
                .font(AMENFont.bold(28))
                .foregroundColor(.black)

            Text("Your selection unlocks a role-specific layer built on top of the same AMEN core. You can change this later in settings.")
                .font(AMENFont.regular(14))
                .foregroundColor(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: Entrance Animation

    private func triggerEntranceAnimations() {
        for index in AMENAccountType.allCases.indices {
            let delay = Double(index) * 0.08
            withAnimation(
                .spring(response: 0.4, dampingFraction: 0.85)
                .delay(delay)
            ) {
                cardOffsets[index] = true
            }
        }
    }
}

// MARK: - AccountTypeCard

private struct AccountTypeCard: View {
    let type: AMENAccountType
    let isSelected: Bool

    @State private var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Card surface
            ZStack {
                // Material base
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                // White overlay
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.55))

                // Hairline / selection stroke
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.black
                            : Color(white: 0.88).opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .shadow(
                color: isSelected
                    ? Color.black.opacity(0.12)
                    : Color.black.opacity(0.04),
                radius: isSelected ? 16 : 4,
                x: 0,
                y: isSelected ? 6 : 2
            )

            // Row content
            HStack(spacing: 14) {
                // Icon bubble
                iconBubble

                // Text stack
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.rawValue)
                        .font(AMENFont.semiBold(18))
                        .foregroundColor(.black)

                    Text(type.tagline)
                        .font(AMENFont.regular(14))
                        .foregroundColor(Color(white: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Selection indicator
                selectionIndicator
            }
            .padding(16)

            // Optional pill badge
            if let label = type.badgePillLabel {
                BadgePill(label: label)
                    .padding(.top, 10)
                    .padding(.trailing, 14)
            }
        }
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isPressed)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    // MARK: Icon Bubble

    private var iconBubble: some View {
        ZStack {
            Circle()
                .fill(type.badgeColor.opacity(0.15))

            // Subtle glass ring
            Circle()
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)

            Image(systemName: type.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(type.badgeColor)
        }
        .frame(width: 52, height: 52)
    }

    // MARK: Selection Indicator

    private var selectionIndicator: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.black)
                    .frame(width: 24, height: 24)

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .strokeBorder(Color(white: 0.75), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }
}

// MARK: - BadgePill

private struct BadgePill: View {
    let label: String

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)

            Capsule()
                .fill(Color.white.opacity(0.55))

            Capsule()
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)

            Text(label)
                .font(AMENFont.semiBold(11))
                .foregroundColor(Color(white: 0.45))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .fixedSize()
    }
}

// MARK: - CapabilitiesCard

private struct CapabilitiesCard: View {
    let type: AMENAccountType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.55))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)

            VStack(alignment: .leading, spacing: 14) {
                // Header — type label + operational layer
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What you get")
                            .font(AMENFont.semiBold(15))
                            .foregroundColor(.black)
                        Text(type.operationalLayerDescription)
                            .font(AMENFont.regular(12))
                            .foregroundColor(Color(white: 0.55))
                    }
                    Spacer()
                    // Type indicator chip
                    ZStack {
                        Capsule().fill(type.badgeColor.opacity(0.12))
                        Capsule().strokeBorder(type.badgeColor.opacity(0.18), lineWidth: 0.5)
                        Text(type.rawValue)
                            .font(AMENFont.semiBold(11))
                            .foregroundColor(type.badgeColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .fixedSize()
                }

                Divider()
                    .opacity(0.5)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(type.capabilities, id: \.self) { capability in
                        CapabilityRow(text: capability, accentColor: type.badgeColor)
                    }
                }

                // Footer reinforcement line
                Text("Same AMEN core · different operational layer")
                    .font(AMENFont.regular(11))
                    .foregroundColor(Color(white: 0.62))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

// MARK: - CapabilityRow

private struct CapabilityRow: View {
    let text: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentColor)
                .frame(width: 16)

            Text(text)
                .font(AMENFont.regular(14))
                .foregroundColor(Color(white: 0.45))
        }
    }
}

// MARK: - ContinueButton

private struct ContinueButton: View {
    let label: String
    let isEnabled: Bool
    let isSubmitting: Bool
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            guard isEnabled, !isSubmitting else { return }
            action()
        }) {
            ZStack {
                Capsule()
                    .fill(isEnabled ? Color.black : Color(white: 0.82))

                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Text(label)
                        .font(AMENFont.semiBold(17))
                        .foregroundColor(isEnabled ? .white : Color(white: 0.55))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .disabled(!isEnabled || isSubmitting)
    }
}

// MARK: - Preview

struct AMENAccountTypeOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AMENAccountTypeOnboardingView()
                .previewDisplayName("Default — no selection")

            AMENAccountTypeOnboardingView_SelectedPreview()
                .previewDisplayName("Church selected")
        }
    }
}

/// Helper wrapper that pre-selects a type so the capabilities card is visible in Xcode canvas.
private struct AMENAccountTypeOnboardingView_SelectedPreview: View {
    @StateObject private var vm: AMENAccountTypeViewModel = {
        let m = AMENAccountTypeViewModel()
        m.selectedType = .church
        return m
    }()

    var body: some View {
        // Expose the view through an internal init variant used only in previews.
        _AMENAccountTypeOnboardingViewInner(vm: vm)
    }
}

/// Internal view that accepts an injected ViewModel — used exclusively by the preview above.
private struct _AMENAccountTypeOnboardingViewInner: View {
    @ObservedObject var vm: AMENAccountTypeViewModel
    @AppStorage("amenAccountTypeOnboardingComplete") private var onboardingComplete: Bool = false
    @State private var cardOffsets: [Bool] = [true, true, true]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHOOSE YOUR ACCOUNT TYPE")
                                .font(AMENFont.semiBold(11))
                                .foregroundColor(Color(white: 0.65))
                                .tracking(1.4)

                            Text("How will you use AMEN?")
                                .font(AMENFont.bold(26))
                                .foregroundColor(.black)

                            Text("You can change this later in settings.")
                                .font(AMENFont.regular(14))
                                .foregroundColor(Color(white: 0.45))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                        // Cards
                        VStack(spacing: 12) {
                            ForEach(AMENAccountType.allCases) { type in
                                AccountTypeCard(
                                    type: type,
                                    isSelected: vm.selectedType == type
                                )
                                .onTapGesture { vm.selectType(type) }
                            }
                        }

                        // Capabilities
                        if let selected = vm.selectedType {
                            CapabilitiesCard(type: selected)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.top, 4)
                        }

                        Spacer(minLength: 32)

                        ContinueButton(
                            label: "Get Started",
                            isEnabled: vm.selectedType != nil,
                            isSubmitting: vm.isSubmitting
                        ) {
                            Task {
                                await vm.confirm()
                                onboardingComplete = true
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
