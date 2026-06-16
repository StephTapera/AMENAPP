// AgeGateView.swift — Features/Safety
// COPPA compliance age gate for new Google/Apple SSO users.
//
// Presented as a fullScreenCover when the signed-in user's Firestore doc
// has ageVerificationRequired == true. This flag is set by createGoogleUserProfile
// and createAppleUserProfile in FirebaseManager.swift.
//
// Invariants:
//  • Under-13: account is deleted server-side via validateUserAge callable;
//    user sees a COPPA message and is returned to sign-in.
//  • 13+: ageVerified=true is stamped server-side; the gate dismisses.
//  • The date picker cannot be pre-set to a valid adult age; it opens at
//    the current date so the user must actively select a birth date.
//  • No full DOB is stored locally after the server call — year only.

import SwiftUI
import FirebaseFunctions
import FirebaseAuth

struct AgeGateView: View {

    @Binding var isPresented: Bool

    @State private var selectedDate = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showCOPPABlock = false

    // Earliest reasonable DOB for the date picker
    private static let earliestDate: Date = {
        var c = DateComponents(); c.year = 1900; c.month = 1; c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showCOPPABlock {
                coppaBlockView
            } else {
                ageEntryView
            }
        }
    }

    // MARK: - Age entry form

    private var ageEntryView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Confirm Your Age")
                    .font(.title2.bold())
                Text("AMEN requires users to be at least 13 years old.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            DatePicker(
                "Date of Birth",
                selection: $selectedDate,
                in: Self.earliestDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 180)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button(action: submitAge) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                } else {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - COPPA block

    private var coppaBlockView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("Account Not Created")
                .font(.title2.bold())

            Text("AMEN is for users aged 13 and older. We're unable to create an account for someone under 13.\n\nYour information has not been stored.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Return to Sign In") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Submit

    private func submitAge() {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let functions = Functions.functions(region: "us-east1")
                let result = try await functions
                    .httpsCallable("validateUserAge")
                    .call(["birthYear": year, "birthMonth": month, "birthDay": day])

                guard let data = result.data as? [String: Any],
                      let allowed = data["allowed"] as? Bool else {
                    await MainActor.run {
                        errorMessage = "Unexpected response. Please try again."
                        isSubmitting = false
                    }
                    return
                }

                await MainActor.run {
                    isSubmitting = false
                    if allowed {
                        isPresented = false
                    } else {
                        // Server deleted the Firebase Auth account — sign out locally too
                        try? Auth.auth().signOut()
                        showCOPPABlock = true
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not verify your age. Please check your connection and try again."
                    isSubmitting = false
                }
            }
        }
    }
}
