//
//  AgeGateView.swift
//  AMENAPP
//
//  COPPA compliance age gate — shown once on first launch.
//  Per COPPA, we block users under 13.
//
//  Age data storage:
//  - This view only collects a year-of-birth to compute the current age.
//    The raw year is NOT persisted by this view.
//  - After account creation, AgeAssuranceService stores the full date of birth
//    in Firestore at users/{uid}/private/age_assurance (a private subcollection
//    inaccessible to other users per Firestore rules). This is required for
//    ongoing age-tier enforcement and COPPA audit purposes.
//  - AgeAssuranceService.loadTier() defaults to .teen (fail-closed) when no
//    profile exists, preventing accidental adult-tier access.
//

import SwiftUI

struct AgeGateView: View {
    @Binding var isEligible: Bool
    @AppStorage("hasCompletedAgeVerification") private var hasCompletedAgeVerification = false

    @State private var birthDate = Calendar.current.date(
        byAdding: .year, value: -16, to: Date()
    ) ?? Date()
    @State private var showUnderAgeMessage = false
    @State private var appeared = false

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.systemScaled(52))
                    .foregroundStyle(.indigo)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

                Text("How old are you?")
                    .font(.title2.bold())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appeared)

                Text("You must be \(AppConfig.Legal.minimumAge) or older to use AMEN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15), value: appeared)
            }

            DatePicker(
                "Date of birth",
                selection: $birthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: birthDate) { _, _ in
                showUnderAgeMessage = age < AppConfig.Legal.minimumAge
            }

            if showUnderAgeMessage {
                Text("Sorry, you must be \(AppConfig.Legal.minimumAge) or older to create an account.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button("Continue") {
                if age >= AppConfig.Legal.minimumAge {
                    // Do NOT store birthDate — only record that verification passed
                    hasCompletedAgeVerification = true
                    isEligible = true
                } else {
                    showUnderAgeMessage = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(age >= AppConfig.Legal.minimumAge ? Color.indigo : Color.indigo.opacity(0.35))
            )
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: age >= AppConfig.Legal.minimumAge)

            Spacer()
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }
}
