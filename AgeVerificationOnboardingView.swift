//
//  AgeVerificationOnboardingView.swift
//  AMENAPP
//
//  New onboarding screen — inserted after the Welcome screen.
//  Dark glassmorphic design. Age gate: min 13 (COPPA). Saves ageTier to Firestore.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct AgeVerificationOnboardingView: View {
    @Binding var currentStep: Int
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var showUnderAgeMessage = false

    private var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0A").ignoresSafeArea()

            // Glowing orbs
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -80, y: -200)
                .allowsHitTesting(false)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: 120, y: 100)
                .allowsHitTesting(false)

            VStack(spacing: 32) {
                Spacer()

                Text("How old are you?")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("We keep our community safe for everyone")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Wheel date picker with glass card
                DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                if showUnderAgeMessage {
                    Text("This app isn't for you yet. Come back when you're 13!")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Glassmorphic black pill button
                Button(action: handleContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .cornerRadius(50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 50)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .padding()
        }
    }

    private func handleContinue() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showUnderAgeMessage = false
        }

        if age < 13 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showUnderAgeMessage = true
            }
            return
        }

        // Write safe default tier using canonical tier strings (tierB/tierC/tierD).
        // The Cloud Function onUserDocCreated will overwrite this with the server-authoritative
        // value. Writing a safe default here closes the race window between doc creation
        // and the async Function execution.
        let ageTier: String
        if age < 16 { ageTier = "tierB" }
        else if age < 18 { ageTier = "tierC" }
        else { ageTier = "tierD" }

        if let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(["ageTier": ageTier], merge: true)
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentStep += 1
        }
    }
}

#Preview {
    AgeVerificationOnboardingView(currentStep: .constant(0))
}
