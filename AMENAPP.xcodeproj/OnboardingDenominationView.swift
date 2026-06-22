//
//  OnboardingDenominationView.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI

struct OnboardingDenominationView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator
    
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
                
                // Denomination list
                VStack(spacing: 12) {
                    ForEach(OnboardingUserData.availableDenominations, id: \.self) { denomination in
                        DenominationButton(
                            denomination: denomination,
                            isSelected: coordinator.userData.denomination == denomination
                        ) {
                            selectDenomination(denomination)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer(minLength: 100)
            }
        }
    }
    
    private func selectDenomination(_ denomination: String) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        if coordinator.userData.denomination == denomination {
            coordinator.userData.denomination = nil
        } else {
            coordinator.userData.denomination = denomination
        }
    }
}

struct DenominationButton: View {
    let denomination: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        isSelected
                            ? LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.black.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                
                Text(denomination)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.black)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [Color.black.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    OnboardingDenominationView()
        .environmentObject(OnboardingCoordinator())
}
