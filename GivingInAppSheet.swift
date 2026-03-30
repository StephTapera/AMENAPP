// GivingInAppSheet.swift
// AMENAPP
//
// In-app giving flow for Christian nonprofits.
// - Amount selector with preset tiles + custom entry
// - One-time or recurring (monthly/annually) toggle
// - Apple Pay via PKPaymentAuthorizationViewController
// - Platform fee disclosure (1–3%)
// - Tax receipt disclosure
//
// INTEGRATION NOTES:
//   - Replace `AMENMerchantID` with your Apple Pay merchant ID
//   - Replace Stripe publishable key placeholder in StripeGivingBridge
//   - Tithe.ly SDK can be dropped in alongside PKPaymentRequest for church giving
//

import SwiftUI
import PassKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Giving In-App Sheet

struct GivingInAppSheet: View {
    let nonprofit: ChristianNonprofit
    @Environment(\.dismiss) private var dismiss

    private let accent: Color
    private let presets: [Double] = [5, 10, 25, 50, 100, 250]

    @State private var selectedPreset: Double? = 25
    @State private var customAmount: String = ""
    @State private var isCustom: Bool = false
    @State private var recurringMode: RecurringMode = .oneTime
    @State private var showApplePayError: Bool = false
    @State private var showSuccess: Bool = false
    @State private var isProcessing: Bool = false
    @FocusState private var customFieldFocused: Bool

    enum RecurringMode: String, CaseIterable {
        case oneTime  = "One Time"
        case monthly  = "Monthly"
        case annually = "Annually"
    }

    init(nonprofit: ChristianNonprofit) {
        self.nonprofit = nonprofit
        self.accent = nonprofit.color
    }

    private var effectiveAmount: Double {
        if isCustom, let v = Double(customAmount), v > 0 { return v }
        return selectedPreset ?? 0
    }

    private var platformFee: Double { effectiveAmount * 0.02 } // 2% platform fee
    private var totalCharge: Double { effectiveAmount + platformFee }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if showSuccess {
                    successView.transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            orgHeader
                            amountSection
                            recurringSection
                            feeSummary
                            applePayButton
                            disclaimers
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Give")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSuccess)
        }
    }

    // MARK: - Org header

    private var orgHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: nonprofit.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nonprofit.name)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                if !nonprofit.verificationBadges.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text(nonprofit.verificationBadges.prefix(2).joined(separator: " · "))
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amount")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presets, id: \.self) { amount in
                    amountTile(amount: amount)
                }
                customTile
            }
        }
    }

    @ViewBuilder
    private func amountTile(amount: Double) -> some View {
        let selected = !isCustom && selectedPreset == amount
        Button {
            isCustom = false
            selectedPreset = amount
            customFieldFocused = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("$\(Int(amount))")
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(selected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? accent : Color(.secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var customTile: some View {
        HStack {
            Text("$")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(isCustom ? .white : .secondary)
            TextField("Other", text: $customAmount)
                .keyboardType(.decimalPad)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(isCustom ? .white : .primary)
                .focused($customFieldFocused)
                .onChange(of: customFieldFocused) { _, focused in
                    if focused { isCustom = true; selectedPreset = nil }
                }
                .onChange(of: customAmount) { _, _ in isCustom = true }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCustom ? accent : Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Recurring

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Frequency")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(RecurringMode.allCases, id: \.self) { mode in
                    Button {
                        recurringMode = mode
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(mode.rawValue)
                            .font(.custom(recurringMode == mode ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                            .foregroundStyle(recurringMode == mode ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(recurringMode == mode ? accent : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Fee summary

    private var feeSummary: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your gift to \(nonprofit.name)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(effectiveAmount > 0 ? String(format: "$%.2f", effectiveAmount) : "—")
                    .font(.custom("OpenSans-Regular", size: 14))
            }
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("AMEN platform (2%)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(effectiveAmount > 0 ? String(format: "$%.2f", platformFee) : "—")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Total")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Spacer()
                Text(effectiveAmount > 0 ? String(format: "$%.2f", totalCharge) : "—")
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Apple Pay button

    private var applePayButton: some View {
        VStack(spacing: 12) {
            // Apple Pay
            if PKPaymentAuthorizationController.canMakePayments(usingNetworks: [.visa, .masterCard, .amex]) {
                ApplePayButton(amount: totalCharge, nonprofit: nonprofit, recurringMode: recurringMode) {
                    withAnimation { showSuccess = true }
                }
                .frame(height: 54)
            } else {
                // Fallback card button (placeholder — wire to Stripe)
                Button {
                    guard effectiveAmount > 0 else { return }
                    // TODO: Present Stripe payment sheet for non-Apple Pay users
                    withAnimation { showSuccess = true }
                } label: {
                    Label("Donate with Card", systemImage: "creditcard.fill")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(effectiveAmount <= 0)
            }
        }
    }

    // MARK: - Disclaimers

    private var disclaimers: some View {
        VStack(spacing: 6) {
            Text("You'll receive a tax receipt at your verified email address. AMEN does not store payment card numbers — all transactions are processed via Stripe.")
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if recurringMode != .oneTime {
                Text("Recurring gifts can be cancelled anytime from Profile → Giving History.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(accent)
            VStack(spacing: 8) {
                Text("Thank you.")
                    .font(.custom("OpenSans-Bold", size: 28))
                Text(String(format: "Your $%.0f %@ gift to %@ is confirmed.", effectiveAmount, recurringMode == .oneTime ? "one-time" : recurringMode.rawValue.lowercased(), nonprofit.name))
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Text("\"Each of you should give what you have decided in your heart to give, not reluctantly or under compulsion, for God loves a cheerful giver.\" — 2 Corinthians 9:7")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .italic()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }
}

// MARK: - Apple Pay Button Wrapper

struct ApplePayButton: UIViewRepresentable {
    let amount: Double
    let nonprofit: ChristianNonprofit
    let recurringMode: GivingInAppSheet.RecurringMode
    var onSuccess: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .donate, paymentButtonStyle: .automatic)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PKPaymentAuthorizationControllerDelegate {
        let parent: ApplePayButton
        init(_ parent: ApplePayButton) { self.parent = parent }

        @objc func tapped() {
            let request = PKPaymentRequest()
            // Replace with your Apple Pay merchant ID registered in Apple Developer Portal
            request.merchantIdentifier = "merchant.com.amen.giving"
            request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
            request.merchantCapabilities = .threeDSecure
            request.countryCode = "US"
            request.currencyCode = "USD"

            let orgItem = PKPaymentSummaryItem(
                label: parent.nonprofit.name,
                amount: NSDecimalNumber(value: parent.amount - parent.amount * 0.02),
                type: .final
            )
            let feeItem = PKPaymentSummaryItem(
                label: "AMEN Platform (2%)",
                amount: NSDecimalNumber(value: parent.amount * 0.02),
                type: .final
            )
            let totalItem = PKPaymentSummaryItem(
                label: "Total",
                amount: NSDecimalNumber(value: parent.amount),
                type: .final
            )
            request.paymentSummaryItems = [orgItem, feeItem, totalItem]

            if parent.recurringMode != .oneTime {
                // Recurring billing descriptor
                request.paymentSummaryItems[2].label = "\(parent.nonprofit.name) · \(parent.recurringMode.rawValue)"
            }

            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            controller.delegate = self
            controller.present(completion: nil)
        }

        func paymentAuthorizationController(
            _ controller: PKPaymentAuthorizationController,
            didAuthorizePayment payment: PKPayment,
            handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
        ) {
            // TODO: Send payment.token.paymentData to your Stripe backend
            // POST /charge with { token: base64, amount: cents, nonprofitId, recurring }
            dlog("✅ Apple Pay authorized for \(parent.nonprofit.name)")
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            DispatchQueue.main.async { self.parent.onSuccess() }
        }

        func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
            controller.dismiss(completion: nil)
        }
    }
}
