//
//  TipView.swift
//  AMENAPP
//
//  Half-sheet for sending a tip to a creator.
//

import SwiftUI

// MARK: - TipView

struct TipView: View {

    let creatorId:   String
    let creatorName: String
    let onSuccess:   () -> Void

    @StateObject private var vm = CreatorViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedAmount: Double = 3.0
    @State private var customAmount            = ""
    @State private var tipMessage              = ""
    @State private var isSending               = false
    @State private var didSend                 = false
    @State private var errorMessage: String?   = nil

    private let amenPurple = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let amenGold   = Color(red: 0.96, green: 0.62, blue: 0.04)
    private let amenDark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    private let presets: [Double] = [1, 3, 5, 10]
    private let amountColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var effectiveAmount: Double {
        if let custom = Double(customAmount), custom > 0 { return custom }
        return selectedAmount > 0 ? selectedAmount : 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                amenDark.ignoresSafeArea()

                if didSend {
                    successState
                } else {
                    tipForm
                }
            }
            .navigationTitle("Support \(creatorName)")
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Tip Form

    private var tipForm: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // ── Amount Presets ────────────────────────────────────
                LazyVGrid(columns: amountColumns, spacing: 10) {
                    ForEach(presets, id: \.self) { amount in
                        AmountPresetCard(
                            amount: amount,
                            isSelected: selectedAmount == amount && customAmount.isEmpty,
                            accentColor: amenPurple
                        ) {
                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                                selectedAmount = amount
                                customAmount   = ""
                            }
                        }
                    }
                }

                // ── Custom Amount ─────────────────────────────────────
                HStack(spacing: 10) {
                    Text("$")
                        .font(AMENFont.bold(18))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Enter amount", text: $customAmount)
                        .font(AMENFont.semiBold(18))
                        .foregroundStyle(.white)
                        .keyboardType(.decimalPad)
                        .onChange(of: customAmount) { val in
                            if !val.isEmpty {
                                withAnimation(reduceMotion ? nil : .default) { selectedAmount = -1 }
                            } else {
                                withAnimation(reduceMotion ? nil : .default) { selectedAmount = 3.0 }
                            }
                        }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )

                // ── Message ───────────────────────────────────────────
                TextField("Add a message (optional)", text: $tipMessage)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )

                // ── Error ─────────────────────────────────────────────
                if let err = errorMessage {
                    Text(err)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ── Send Button ───────────────────────────────────────
                Button {
                    guard effectiveAmount > 0 else {
                        withAnimation(reduceMotion ? nil : .default) { errorMessage = "Please select or enter an amount." }
                        return
                    }
                    errorMessage = nil
                    isSending = true
                    Task {
                        do {
                            try await vm.sendTip(
                                toCreatorId: creatorId,
                                amount: effectiveAmount,
                                message: tipMessage
                            )
                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                                isSending = false
                                didSend = true
                            }
                            onSuccess()
                        } catch {
                            isSending = false
                            withAnimation(reduceMotion ? nil : .default) { errorMessage = error.localizedDescription }
                        }
                    }
                } label: {
                    ZStack {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .font(.systemScaled(15, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text("Send \(formattedAmount)")
                                    .font(AMENFont.bold(17))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [amenPurple, Color(red: 0.94, green: 0.28, blue: 0.64)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: amenPurple.opacity(0.4), radius: 14, y: 5)
                    )
                }
                .disabled(isSending || effectiveAmount <= 0)
                .buttonStyle(CoCreationPressStyle())

                // ── Apple Pay note ────────────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "applelogo")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Charged via Apple Pay")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "heart.circle.fill")
                    .font(.systemScaled(64, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.green)
                // Shimmer ring
                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
            }

            VStack(spacing: 8) {
                Text("Tip Sent!")
                    .font(AMENFont.bold(28))
                    .foregroundStyle(.white)
                Text("You sent \(formattedAmount) to \(creatorName)")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.white)
                    .frame(width: 160)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.green)
                            .shadow(color: Color.green.opacity(0.35), radius: 10, y: 4)
                    )
            }
            .buttonStyle(CoCreationPressStyle())

            Spacer()
        }
        .padding(.horizontal, 32)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Helpers

    private var formattedAmount: String {
        String(format: "$%.0f", effectiveAmount)
    }
}

// MARK: - Amount Preset Card

private struct AmountPresetCard: View {
    let amount: Double
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(String(format: "$%.0f", amount))
                    .font(AMENFont.bold(22))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accentColor : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.clear : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: isSelected ? accentColor.opacity(0.35) : .clear,
                radius: 10, y: 4
            )
        }
        .buttonStyle(CoCreationPressStyle())
    }
}
