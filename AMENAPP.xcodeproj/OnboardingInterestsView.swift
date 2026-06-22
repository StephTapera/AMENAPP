//
//  OnboardingInterestsView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

struct OnboardingInterestsView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: coordinator.currentStep.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 40)
                
                // Title and subtitle
                VStack(spacing: 8) {
                    Text(coordinator.currentStep.title)
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.black)
                    
                    Text(coordinator.currentStep.subtitle)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.black.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                // Hint
                Text("Select exactly 3 interests (\(coordinator.userData.selectedInterests.count)/3)")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(coordinator.userData.selectedInterests.count == 3 ? .green : .black.opacity(0.5))
                    .padding(.top, 8)
                
                // Interest grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingUserData.availableInterests, id: \.self) { interest in
                        let isSelected = coordinator.userData.selectedInterests.contains(interest)
                        let isDisabled = !isSelected && coordinator.userData.selectedInterests.count >= 3

                        InterestButton(
                            interest: interest,
                            isSelected: isSelected,
                            isDisabled: isDisabled
                        ) {
                            toggleInterest(interest)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer(minLength: 100)
            }
        }
    }
    
    private func toggleInterest(_ interest: String) {
        let haptic = UIImpactFeedbackGenerator(style: .light)

        if coordinator.userData.selectedInterests.contains(interest) {
            // Always allow deselection
            haptic.impactOccurred()
            coordinator.userData.selectedInterests.removeAll { $0 == interest }
        } else {
            // Only allow selection if less than 3 interests are selected
            if coordinator.userData.selectedInterests.count < 3 {
                haptic.impactOccurred()
                coordinator.userData.selectedInterests.append(interest)
            } else {
                // Play error haptic when limit is reached
                let errorHaptic = UINotificationFeedbackGenerator()
                errorHaptic.notificationOccurred(.error)
            }
        }
    }
}

struct InterestButton: View {
    let interest: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }

                Text(interest)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(isSelected ? .white : (isDisabled ? .black.opacity(0.3) : .black))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [isDisabled ? Color.gray.opacity(0.1) : Color.white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .shadow(
                        color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.05),
                        radius: isSelected ? 8 : 4,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? Color.clear
                            : Color.black.opacity(isDisabled ? 0.05 : 0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

#Preview {
    OnboardingInterestsView()
        .environmentObject(OnboardingCoordinator())
}
