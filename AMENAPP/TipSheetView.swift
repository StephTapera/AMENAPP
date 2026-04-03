//
//  TipSheetView.swift
//  AMENAPP
//
//  Verge-specific tip sheet, shown inside a live room.
//  (See TipView.swift for the general creator tipping half-sheet.)
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TipSheetView: View {

    let creatorId:   String
    let creatorName: String
    let roomTitle:   String

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAmount: Double  = 5.0
    @State private var customAmountText        = ""
    @State private var optionalMessage         = ""
    @State private var isSending               = false
    @State private var didSend                 = false
    @State private var heartBurst              = false
    @State private var errorMessage: String?

    private let amenPurple = Color(hex: "6B48FF")
    private let amenViolet = Color(hex: "C084FC")
    private let amenGold   = Color(hex: "F59E0B")
    private let bg         = Color(hex: "0A0A0F")
    private let presets: [Double] = [1, 3, 5, 10]

    private var effectiveAmount: Double {
        if let custom = Double(customAmountText), custom > 0 { return custom }
        return selectedAmount > 0 ? selectedAmount : 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if didSend {
                    successView
                } else {
                    formView
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
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.systemScaled(22))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                // Room context banner
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.systemScaled(14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(amenViolet)
                    Text("Supporting during \"\(roomTitle)\"")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(amenViolet.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(amenViolet.opacity(0.15), lineWidth: 0.5)
                        )
                )

                // Preset grid
                amountGrid

                // Custom amount
                customAmountField

                // Optional message
                TextField("Add a message (optional)", text: $optionalMessage)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(glassField)

                // Error
                if let err = errorMessage {
                    Text(err)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Send button
                sendButton

                // Note
                HStack(spacing: 6) {
                    Image(systemName: "applelogo")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Charged via Apple Pay")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Amount Grid

    private var amountGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(presets, id: \.self) { amount in
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        selectedAmount    = amount
                        customAmountText  = ""
                    }
                } label: {
                    Text(String(format: "$%.0f", amount))
                        .font(AMENFont.bold(18))
                        .foregroundStyle(selectedAmount == amount && customAmountText.isEmpty ? .white : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedAmount == amount && customAmountText.isEmpty
                                      ? amenPurple
                                      : Color.white.opacity(0.07))
                                .shadow(
                                    color: selectedAmount == amount && customAmountText.isEmpty
                                    ? amenPurple.opacity(0.35) : .clear,
                                    radius: 10, y: 4
                                )
                        )
                }
                .buttonStyle(CoCreationPressStyle())
            }
        }
    }

    // MARK: - Custom Amount

    private var customAmountField: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(AMENFont.bold(18))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Custom amount", text: $customAmountText)
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.white)
                .keyboardType(.decimalPad)
                .onChange(of: customAmountText) { val in
                    if !val.isEmpty {
                        withAnimation { selectedAmount = -1 }
                    } else {
                        withAnimation { selectedAmount = 5.0 }
                    }
                }
        }
        .padding(14)
        .background(glassField)
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            guard effectiveAmount > 0 else {
                withAnimation { errorMessage = "Please select or enter an amount." }
                return
            }
            errorMessage = nil
            isSending    = true
            Task { await submitTip() }
        } label: {
            ZStack {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Text("❤️")
                            .font(.systemScaled(16))
                        Text("Send with ❤️  \(String(format: "$%.0f", effectiveAmount))")
                            .font(AMENFont.bold(17))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [amenPurple, Color(hex: "C084FC")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: amenPurple.opacity(0.4), radius: 14, y: 5)
            )
        }
        .disabled(isSending || effectiveAmount <= 0)
        .buttonStyle(CoCreationPressStyle())
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // Burst rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.pink.opacity(heartBurst ? 0 : 0.4), lineWidth: 2)
                        .frame(
                            width: heartBurst ? CGFloat(100 + i * 40) : 60,
                            height: heartBurst ? CGFloat(100 + i * 40) : 60
                        )
                        .animation(
                            .easeOut(duration: 0.8).delay(Double(i) * 0.15),
                            value: heartBurst
                        )
                }

                Text("❤️")
                    .font(.systemScaled(heartBurst ? 72 : 40))
                    .scaleEffect(heartBurst ? 1.0 : 0.5)
                    .opacity(heartBurst ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: heartBurst)
            }
            .frame(height: 130)
            .onAppear {
                withAnimation { heartBurst = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                }
            }

            VStack(spacing: 8) {
                Text("Tip Sent!")
                    .font(AMENFont.bold(28))
                    .foregroundStyle(.white)
                Text(String(format: "You sent $%.0f to %@", effectiveAmount, creatorName))
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Firestore Write

    private func submitTip() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            withAnimation { errorMessage = "You must be signed in to send a tip." }
            isSending = false
            return
        }
        do {
            try await Firestore.firestore().collection("tips").addDocument(data: [
                "senderId":    uid,
                "recipientId": creatorId,
                "amount":      effectiveAmount,
                "message":     optionalMessage,
                "roomTitle":   roomTitle,
                "createdAt":   FieldValue.serverTimestamp()
            ])
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                isSending = false
                didSend   = true
            }
        } catch {
            isSending = false
            withAnimation { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Helpers

    private var glassField: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
            )
    }
}
