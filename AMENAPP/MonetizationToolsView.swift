//
//  MonetizationToolsView.swift
//  AMENAPP
//
//  Expandable monetization controls — subscriptions, tips, digital goods.
//

import SwiftUI

// MARK: - MonetizationToolsView

struct MonetizationToolsView: View {

    @ObservedObject var vm: CreatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var subscriptionPriceInput = ""
    @State private var expandedSection: String? = nil
    @State private var showAddGoodSheet        = false

    private let amenPink   = Color(red: 0.94, green: 0.28, blue: 0.64)
    private let amenGreen  = Color(red: 0.20, green: 0.75, blue: 0.45)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    var body: some View {
        ZStack {
            amenDark.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {

                    // ── Subscriptions ──────────────────────────────────
                    MonetizationSection(
                        id: "subscriptions",
                        title: "Subscriptions",
                        subtitle: "Recurring monthly revenue",
                        icon: "crown.fill",
                        accentColor: Color.accentColor,
                        expandedSection: $expandedSection
                    ) {
                        subscriptionsContent
                    }

                    // ── Tips ──────────────────────────────────────────
                    MonetizationSection(
                        id: "tips",
                        title: "Tips",
                        subtitle: "One-time appreciation payments",
                        icon: "heart.circle.fill",
                        accentColor: amenPink,
                        expandedSection: $expandedSection
                    ) {
                        tipsContent
                    }

                    // ── Digital Goods ─────────────────────────────────
                    MonetizationSection(
                        id: "goods",
                        title: "Digital Goods",
                        subtitle: "Sell devotionals, art, audio",
                        icon: "bag.fill",
                        accentColor: amenGreen,
                        expandedSection: $expandedSection
                    ) {
                        digitalGoodsContent
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Monetization")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddGoodSheet) {
            AddDigitalGoodSheet(vm: vm)
        }
        .onAppear {
            if let price = vm.profile.subscriptionPrice, price > 0 {
                subscriptionPriceInput = String(format: "%.2f", price)
            }
        }
    }

    // MARK: - Subscriptions Content

    private var subscriptionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Stats row
            HStack(spacing: 12) {
                subscriptionStat(
                    value: "\(vm.profile.subscriberCount)",
                    label: "Subscribers",
                    color: Color.accentColor
                )
                subscriptionStat(
                    value: mrrFormatted,
                    label: "MRR",
                    color: Color(red: 0.20, green: 0.75, blue: 0.45)
                )
            }

            Divider().opacity(0.1)

            // Price input
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Price (USD)")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 10) {
                    Text("$")
                        .font(AMENFont.bold(18))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("4.99", text: $subscriptionPriceInput)
                        .font(AMENFont.semiBold(18))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                    Spacer()
                    Button {
                        if let price = Double(subscriptionPriceInput) {
                            Task { await vm.setSubscriptionPrice(price) }
                        }
                    } label: {
                        Text("Save")
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 3)
                            )
                    }
                    .buttonStyle(CoCreationPressStyle())
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }

            Divider().opacity(0.1)

            // Benefits
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Subscriber Benefits")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button {
                        // Add benefit placeholder
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(CoCreationPressStyle())
                }

                if vm.profile.subscriptionBenefits.isEmpty {
                    Text("No benefits added yet")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    ForEach(vm.profile.subscriptionBenefits, id: \.self) { benefit in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(14))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                            Text(benefit)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    private var mrrFormatted: String {
        let mrr = (vm.profile.subscriptionPrice ?? 0) * Double(vm.profile.subscriberCount)
        return String(format: "$%.0f", mrr)
    }

    @ViewBuilder
    private func subscriptionStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AMENFont.bold(22))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(AMENFont.regular(12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Tips Content

    private var tipsContent: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Toggle
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable tip button on posts")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                    Text("Tips are sent directly when viewers appreciate your content")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.profile.tipsEnabled },
                    set: { _ in Task { await vm.toggleTips() } }
                ))
                .tint(amenPink)
                .labelsHidden()
            }

            Divider().opacity(0.1)

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.systemScaled(14))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Total tips received this month: $0")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    // MARK: - Digital Goods Content

    private var digitalGoodsContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            if vm.profile.digitalGoods.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bag.badge.plus")
                        .font(.systemScaled(32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(amenGreen)
                    Text("No digital goods yet")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Add devotionals, art, audio files and more")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(vm.profile.digitalGoods) { good in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(amenGreen.opacity(0.15))
                                    .frame(width: 38, height: 38)
                                Image(systemName: good.type.icon)
                                    .font(.systemScaled(16, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(amenGreen)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(good.title)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(.white)
                                Text(good.type.label)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(String(format: "$%.2f", good.price))
                                    .font(AMENFont.bold(15))
                                    .foregroundStyle(.white)
                                Text("\(good.salesCount) sold")
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            Button {
                showAddGoodSheet = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(16))
                        .symbolRenderingMode(.hierarchical)
                    Text("Add New Good")
                        .font(AMENFont.semiBold(15))
                }
                .foregroundStyle(amenGreen)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(amenGreen.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(CoCreationPressStyle())
        }
    }
}

// MARK: - Monetization Section (Expandable)

private struct MonetizationSection<Content: View>: View {

    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    @Binding var expandedSection: String?
    @ViewBuilder let content: () -> Content

    private var isExpanded: Bool { expandedSection == id }

    var body: some View {
        VStack(spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                    expandedSection = isExpanded ? nil : id
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.systemScaled(20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(AMENFont.semiBold(16))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(16)
            }
            .buttonStyle(CoCreationPressStyle())

            // Expanded body
            if isExpanded {
                Divider()
                    .opacity(0.08)
                    .padding(.horizontal, 16)

                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isExpanded ? accentColor.opacity(0.25) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isExpanded)
    }
}

// MARK: - Add Digital Good Sheet

private struct AddDigitalGoodSheet: View {

    @ObservedObject var vm: CreatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var goodTitle  = ""
    @State private var goodPrice  = ""
    @State private var goodDesc   = ""
    @State private var selectedType: DigitalGood.GoodType = .devotional

    private let amenGreen  = Color(red: 0.20, green: 0.75, blue: 0.45)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        glassField("Title", text: $goodTitle)
                        glassField("Price (e.g. 4.99)", text: $goodPrice, keyboard: .decimalPad)
                        glassField("Description", text: $goodDesc)

                        // Type picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(.white.opacity(0.55))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(DigitalGood.GoodType.allCases, id: \.self) { type in
                                        Button {
                                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                                                selectedType = type
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: type.icon)
                                                    .font(.systemScaled(13, weight: .semibold))
                                                    .symbolRenderingMode(.hierarchical)
                                                Text(type.label)
                                                    .font(AMENFont.semiBold(13))
                                            }
                                            .foregroundStyle(selectedType == type ? .white : .white.opacity(0.55))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(
                                                Capsule()
                                                    .fill(selectedType == type ? amenGreen : Color.white.opacity(0.07))
                                                    .overlay(
                                                        Capsule().stroke(
                                                            selectedType == type ? Color.clear : Color.white.opacity(0.1),
                                                            lineWidth: 1
                                                        )
                                                    )
                                            )
                                        }
                                        .buttonStyle(CoCreationPressStyle())
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Button {
                            // Placeholder add action
                            dismiss()
                        } label: {
                            Text("Add Good")
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(amenGreen)
                                        .shadow(color: amenGreen.opacity(0.3), radius: 10, y: 4)
                                )
                        }
                        .buttonStyle(CoCreationPressStyle())

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("New Digital Good")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func glassField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(AMENFont.regular(15))
            .foregroundStyle(.white)
            .keyboardType(keyboard)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}
