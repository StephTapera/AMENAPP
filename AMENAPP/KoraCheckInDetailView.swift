// KoraCheckInDetailView.swift
// AMENAPP
//
// Full detail view for a Kora check-in — response composer, AI summary, past responses.

import SwiftUI
import FirebaseAuth

struct KoraCheckInDetailView: View {
    let checkIn: KoraCheckIn
    let circle: KoraCircle
    @ObservedObject var vm: KoraViewModel

    @State private var responseText: String = ""
    @State private var selectedMood: KoraMood = .growing
    @State private var isPrivateResponse: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var hasSubmitted: Bool = false
    @State private var errorMessage: String? = nil
    @State private var responses: [KoraCheckInResponse] = []
    @Environment(\.dismiss) private var dismiss

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    private var userHasResponded: Bool {
        responses.contains { $0.authorId == currentUid }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A0F").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Question card
                    questionCard
                        .padding(.horizontal, 16)

                    // Response composer (open + not yet responded)
                    if checkIn.status == .open && !userHasResponded && !hasSubmitted {
                        responseComposer
                            .padding(.horizontal, 16)
                    }

                    // AI Summary card
                    if checkIn.status == .summarized {
                        aiSummaryCard
                            .padding(.horizontal, 16)
                    }

                    // Past responses (closed or summarized)
                    if checkIn.status != .open, !responses.isEmpty {
                        pastResponsesSection
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadResponses()
        }
    }

    // MARK: - Question Card

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.systemScaled(12))
                    .foregroundColor(Color(hex: "F59E0B"))
                Text("This week's question")
                    .font(AMENFont.semiBold(12))
                    .foregroundColor(Color(hex: "F59E0B"))
            }

            Text(checkIn.question)
                .font(AMENFont.semiBold(18))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "F59E0B").opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(hex: "F59E0B").opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Response Composer

    private var responseComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your response")
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white)

            // TextEditor
            ZStack(alignment: .topLeading) {
                if responseText.isEmpty {
                    Text("Share openly…")
                        .font(AMENFont.regular(15))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(.top, 10)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $responseText)
                    .font(AMENFont.regular(15))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 120)
                    .tint(Color(hex: "6B48FF"))
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Mood selector
            VStack(alignment: .leading, spacing: 10) {
                Text("How are you?")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.white.opacity(0.65))

                HStack(spacing: 8) {
                    ForEach(KoraMood.allCases, id: \.self) { mood in
                        moodPill(mood: mood)
                    }
                }
            }

            // Private toggle
            Toggle(isOn: $isPrivateResponse) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.systemScaled(12))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Keep private")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
            .tint(Color(hex: "6B48FF"))

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(AMENFont.regular(13))
                    .foregroundColor(Color(hex: "EF4444"))
            }

            // Submit button
            Button {
                Task { await submitResponse() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isSubmitting ? "Submitting…" : "Submit Response")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AnyShapeStyle(Color.white.opacity(0.1))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color(hex: "F59E0B"), Color(hex: "EF4444")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(CoCreationPressStyle())
            .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func moodPill(mood: KoraMood) -> some View {
        let isSelected = selectedMood == mood
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                selectedMood = mood
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mood.icon)
                    .font(.systemScaled(11))
                Text(mood.label)
                    .font(AMENFont.semiBold(11))
            }
            .foregroundColor(isSelected ? .white : Color(hex: mood.colorHex).opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color(hex: mood.colorHex).opacity(0.3)
                    : Color(hex: mood.colorHex).opacity(0.08)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                            ? Color(hex: mood.colorHex).opacity(0.6)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - AI Summary Card

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.systemScaled(13))
                    .foregroundColor(Color(hex: "6B48FF"))
                Text("AI Summary")
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(Color(hex: "6B48FF"))
            }

            if let summary = checkIn.aiSummary {
                Text(summary)
                    .font(AMENFont.regular(14))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !checkIn.aiInsights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checkIn.aiInsights.prefix(3), id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.systemScaled(13))
                                .foregroundColor(Color(hex: "22C55E"))
                                .padding(.top, 1)
                            Text(insight)
                                .font(AMENFont.regular(13))
                                .foregroundColor(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(hex: "6B48FF").opacity(0.25), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Past Responses

    private var pastResponsesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Responses")
                .font(AMENFont.semiBold(15))
                .foregroundColor(.white)
                .padding(.bottom, 2)

            ForEach(responses) { response in
                pastResponseRow(response)
            }
        }
    }

    private func pastResponseRow(_ response: KoraCheckInResponse) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: response.mood.colorHex))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(response.responseText)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(3)

                HStack(spacing: 6) {
                    Text(response.mood.label)
                        .font(AMENFont.regular(11))
                        .foregroundColor(Color(hex: response.mood.colorHex).opacity(0.7))

                    if response.isPrivate {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.systemScaled(9))
                            Text("Private")
                                .font(AMENFont.regular(10))
                        }
                        .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func submitResponse() async {
        guard let checkInId = checkIn.id, let circleId = circle.id else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await vm.submitResponse(
                checkInId: checkInId,
                circleId: circleId,
                responseText: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                mood: selectedMood,
                isPrivate: isPrivateResponse
            )
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                hasSubmitted = true
            }
            await loadResponses()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func loadResponses() async {
        // For closed/summarized check-ins, load public responses
        guard let checkInId = checkIn.id else { return }
        dlog("KoraCheckInDetailView: loading responses for \(checkInId)")
        // Responses will be loaded when the full responses service is implemented.
        // For now we use an empty array to avoid over-fetching.
    }
}
