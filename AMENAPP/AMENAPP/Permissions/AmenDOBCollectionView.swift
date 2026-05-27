//
//  AmenDOBCollectionView.swift
//  AMENAPP
//
//  Onboarding step: collect date of birth, derive age tier, and gate app access.
//  Present this after Firebase Auth account creation completes.
//
//  Usage:
//    AmenDOBCollectionView { tier in
//        // navigate to main app or next onboarding step
//    }
//    .environmentObject(permissionsService)
//

import SwiftUI

struct AmenDOBCollectionView: View {

    /// Called with the resolved AgeTier on success. Caller handles navigation.
    var onComplete: (AmenAgeTier) -> Void

    @EnvironmentObject private var permissionsService: AmenPermissionsService

    @State private var selectedDate: Date = {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let minDate = Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast
    private static let maxDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("When were you born?")
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                Text("We use your date of birth to personalize your experience and keep the community safe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            DatePicker(
                "Date of Birth",
                selection: $selectedDate,
                in: Self.minDate...Self.maxDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            Spacer()

            Button(action: submit) {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                let tier = try await permissionsService.setDateOfBirth(selectedDate)
                onComplete(tier)
            } catch {
                // The server sends a user-readable message for the under-13 case.
                errorMessage = error.localizedDescription
            }
        }
    }
}
