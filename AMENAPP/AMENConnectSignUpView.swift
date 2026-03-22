// AMENConnectSignUpView.swift
// AMENAPP
//
// AMEN Connect sign-up / profile setup flow + membership paywall.
// Step 1: Create profile (name, role, ministry, skills, interests)
// Step 2: Choose tier (Free vs Pro)
// Step 3: Confirmation

import SwiftUI
import FirebaseAuth

// MARK: - Sign-Up Flow Entry

struct AMENConnectSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AMENConnectMembershipStore.shared
    @State private var step = 0
    @State private var billingAnnual = false

    // Profile fields
    @State private var displayName: String = Auth.auth().currentUser?.displayName ?? ""
    @State private var role: String = ""
    @State private var ministry: String = ""
    @State private var bio: String = ""
    @State private var selectedSkills: Set<String> = []
    @State private var selectedInterests: Set<AMENConnectTab> = []
    @State private var selectedTier: AMENConnectTier = .free
    @State private var isSubmitting = false
    @State private var showSuccess = false

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let blue  = Color(red: 0.18, green: 0.30, blue: 0.60)
    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showSuccess {
                successView
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                VStack(spacing: 0) {
                    // Header
                    signUpHeader

                    // Step progress dots
                    stepDots
                        .padding(.bottom, 8)

                    // Step content
                    TabView(selection: $step) {
                        profileStep.tag(0)
                        tierStep.tag(1)
                        reviewStep.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.28), value: step)

                    // Nav buttons
                    navRow
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            store.loadProfile()
        }
    }

    // MARK: - Header

    private var signUpHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AMEN Connect")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                Text("Join the faith community network")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Step dots

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? ink : Color(.systemGray4))
                    .frame(width: i == step ? 22 : 7, height: 7)
                    .animation(.easeOut(duration: 0.2), value: step)
            }
            Spacer()
            Text("\(step + 1) of \(totalSteps)")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 1: Profile

    private var profileStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                stepTitle("Build your profile", sub: "This is how the community will know you.")

                inputField(label: "Your Name", placeholder: "Full name", text: $displayName)
                inputField(label: "Your Role / Title", placeholder: "e.g. Worship Leader, Software Engineer", text: $role)
                inputField(label: "Ministry or Church", placeholder: "e.g. Grace Community Church (optional)", text: $ministry)

                bioField

                // Skills
                VStack(alignment: .leading, spacing: 10) {
                    Text("Skills & Expertise")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                    Text("Choose up to 5")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    FlowTagSelector(
                        options: allSkills,
                        selected: $selectedSkills,
                        maxSelected: 5,
                        accentColor: blue
                    )
                }

                // Interest categories
                VStack(alignment: .leading, spacing: 10) {
                    Text("I'm interested in...")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                    FlowTabSelector(
                        options: [.jobs, .network, .marketplace, .serve, .events, .ministries, .prayer, .mentorship, .forum],
                        selected: $selectedInterests,
                        accentColor: blue
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 2: Tier

    private var tierStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                stepTitle("Choose your plan", sub: "Start free. Upgrade anytime.")

                // Billing toggle
                HStack(spacing: 0) {
                    billingToggleButton("Monthly", isSelected: !billingAnnual) { billingAnnual = false }
                    billingToggleButton("Annual (save 33%)", isSelected: billingAnnual) { billingAnnual = true }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                // Tier cards
                ForEach(AMENConnectTier.allCases, id: \.self) { tier in
                    TierCard(
                        tier: tier,
                        isSelected: selectedTier == tier,
                        billingAnnual: billingAnnual
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedTier = tier
                        }
                    }
                }

                // Money-back note
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                    Text("7-day money-back guarantee. Cancel anytime.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 3: Review & Confirm

    private var reviewStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                stepTitle("Almost done!", sub: "Review your details and join.")

                // Summary card
                VStack(alignment: .leading, spacing: 14) {
                    reviewRow(icon: "person.fill", label: "Name", value: displayName.isEmpty ? "—" : displayName)
                    reviewRow(icon: "briefcase.fill", label: "Role", value: role.isEmpty ? "—" : role)
                    if !ministry.isEmpty {
                        reviewRow(icon: "building.2.fill", label: "Ministry", value: ministry)
                    }
                    Divider().opacity(0.4)
                    reviewRow(
                        icon: selectedTier == .pro ? "star.fill" : "person.crop.circle",
                        label: "Plan",
                        value: "\(selectedTier.displayName) · \(billingAnnual ? selectedTier.annualPrice : selectedTier.monthlyPrice)",
                        valueColor: selectedTier == .pro ? Color(red: 0.85, green: 0.58, blue: 0.10) : .secondary
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                if selectedTier == .pro {
                    // Pro CTA note
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.85, green: 0.58, blue: 0.10))
                        Text("Pro unlocks AI matching, direct connects, and marketplace listings — helping you find the right people for your calling.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.08))
                    )
                }

                // Terms note
                Text("By joining, you agree to AMEN's community standards. We are committed to a safe, faith-centered environment.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineSpacing(3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Nav Row

    private var navRow: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { step -= 1 }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }

            Button {
                if step < totalSteps - 1 {
                    withAnimation(.easeOut(duration: 0.25)) { step += 1 }
                } else {
                    Task { await submitProfile() }
                }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(step < totalSteps - 1 ? "Continue" : (selectedTier == .pro ? "Join Pro — \(billingAnnual ? "Pay \(AMENConnectTier.pro.annualPrice)" : "Pay \(AMENConnectTier.pro.monthlyPrice)")" : "Join Free"))
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isStepValid ? (selectedTier == .pro && step == 2 ? Color(red: 0.85, green: 0.58, blue: 0.10) : ink) : Color(.systemGray4))
                )
            }
            .disabled(!isStepValid || isSubmitting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Submit

    private func submitProfile() async {
        isSubmitting = true
        var p = store.profile
        p.uid = Auth.auth().currentUser?.uid ?? p.uid
        p.displayName = displayName
        p.role = role
        p.ministry = ministry
        p.bio = bio
        p.skills = Array(selectedSkills)
        p.interests = selectedInterests.map { $0.rawValue }
        p.focusCategories = Array(selectedInterests)
        p.tier = selectedTier
        p.memberSince = Date()
        // Save free-tier profile first so the profile exists regardless of purchase outcome
        p.tier = selectedTier == .pro ? .free : .free  // will be .pro only after confirmed purchase
        store.profile = p
        await store.saveProfile()

        if selectedTier == .pro {
            let purchased = await store.upgradeToPro()
            if !purchased {
                // User cancelled purchase — keep free tier, still proceed to success
                isSubmitting = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { dismiss() }
                return
            }
        }

        isSubmitting = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showSuccess = true
        }
        // Auto dismiss after showing success
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            dismiss()
        }
    }

    // MARK: - Validation

    private var isStepValid: Bool {
        switch step {
        case 0: return !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true // tier always valid
        case 2: return true
        default: return false
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(selectedTier == .pro
                          ? Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.12)
                          : Color(red: 0.18, green: 0.30, blue: 0.60).opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: selectedTier == .pro ? "star.fill" : "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedTier == .pro
                                     ? Color(red: 0.85, green: 0.58, blue: 0.10)
                                     : Color(red: 0.18, green: 0.30, blue: 0.60))
            }

            VStack(spacing: 10) {
                Text(selectedTier == .pro ? "Welcome to Pro!" : "You're in!")
                    .font(.custom("OpenSans-Bold", size: 26))
                    .foregroundStyle(.primary)
                Text(selectedTier == .pro
                     ? "AI matching, direct connects, and marketplace listings are now active."
                     : "Start browsing jobs, events, prayer, mentorship, and more.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepTitle(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.primary)
            Text(sub)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func inputField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.custom("OpenSans-Regular", size: 15))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .autocorrectionDisabled()
        }
    }

    private var bioField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Short Bio (optional)")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            TextEditor(text: $bio)
                .font(.custom("OpenSans-Regular", size: 15))
                .frame(height: 80)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    @ViewBuilder
    private func reviewRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(valueColor)
        }
    }

    @ViewBuilder
    private func billingToggleButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                        }
                    }
                )
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - Tier Card

private struct TierCard: View {
    let tier: AMENConnectTier
    let isSelected: Bool
    let billingAnnual: Bool
    let onSelect: () -> Void

    private let proGold = Color(red: 0.85, green: 0.58, blue: 0.10)

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if tier == .pro {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(proGold)
                            }
                            Text(tier.displayName)
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.primary)
                        }
                        Text(billingAnnual ? tier.annualPrice : tier.monthlyPrice)
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(tier == .pro ? proGold : .secondary)
                    }
                    Spacer()
                    // Selection indicator
                    ZStack {
                        Circle()
                            .stroke(isSelected ? (tier == .pro ? proGold : Color(.label)) : Color(.systemGray4), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        if isSelected {
                            Circle()
                                .fill(tier == .pro ? proGold : Color(.label))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: isSelected)
                }

                // Feature list
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tier.features) { feature in
                        HStack(spacing: 10) {
                            Image(systemName: feature.included ? "checkmark" : "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(feature.included
                                                 ? (tier == .pro ? proGold : .green)
                                                 : Color(.systemGray4))
                                .frame(width: 16)
                            Text(feature.text)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(feature.included ? .primary : Color(.systemGray3))
                        }
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected
                        ? (tier == .pro ? proGold.opacity(0.25) : Color(.label).opacity(0.15))
                        : .black.opacity(0.05),
                        radius: isSelected ? 16 : 8,
                        y: isSelected ? 6 : 3
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected
                        ? (tier == .pro ? proGold : Color(.label))
                        : Color(.separator).opacity(0.5),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Flow Tag Selector (skills)

struct FlowTagSelector: View {
    let options: [String]
    @Binding var selected: Set<String>
    let maxSelected: Int
    let accentColor: Color

    var body: some View {
        // Wrap tags into rows
        ConnectFlowLayout(options) { skill in
            Button {
                if selected.contains(skill) {
                    selected.remove(skill)
                } else if selected.count < maxSelected {
                    selected.insert(skill)
                }
            } label: {
                Text(skill)
                    .font(.custom(selected.contains(skill) ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                    .foregroundStyle(selected.contains(skill) ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(selected.contains(skill) ? accentColor : Color(.secondarySystemBackground))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.easeOut(duration: 0.15), value: selected.contains(skill))
        }
    }
}

// MARK: - Flow Tab Selector (interest categories)

struct FlowTabSelector: View {
    let options: [AMENConnectTab]
    @Binding var selected: Set<AMENConnectTab>
    let accentColor: Color

    var body: some View {
        ConnectFlowLayout(options) { tab in
            Button {
                if selected.contains(tab) {
                    selected.remove(tab)
                } else {
                    selected.insert(tab)
                }
            } label: {
                Text(tab.rawValue)
                    .font(.custom(selected.contains(tab) ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                    .foregroundStyle(selected.contains(tab) ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(selected.contains(tab) ? accentColor : Color(.secondarySystemBackground))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .animation(.easeOut(duration: 0.15), value: selected.contains(tab))
        }
    }
}

// MARK: - ConnectFlowLayout (generic flow layout for tag selectors)

struct ConnectFlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content
    @State private var totalHeight: CGFloat = 0

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lastHeight: CGFloat = 0
        let itemSpacing: CGFloat = 8

        return ZStack(alignment: .topLeading) {
            ForEach(Array(data.enumerated()), id: \.element) { _, item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= lastHeight + itemSpacing
                        }
                        let result = width
                        if item == data.last {
                            width = 0
                        } else {
                            width -= d.width + itemSpacing
                        }
                        lastHeight = d.height
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == data.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    totalHeight = geo.size.height
                }
            }
        )
    }
}

// MARK: - Skills data

private let allSkills: [String] = [
    "Worship Music", "Teaching", "Preaching", "Counseling", "Youth Ministry",
    "Admin / Operations", "Graphic Design", "Video / Media", "Software Dev",
    "Finance / Accounting", "Writing / Editing", "Photography", "Event Planning",
    "Nonprofit Management", "Social Media", "Translation", "Chaplaincy",
    "Prayer Ministry", "Discipleship", "Leadership Development",
]

// MARK: - Preview

#Preview {
    AMENConnectSignUpView()
}
