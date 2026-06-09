//
//  DateOfBirthCollectionView.swift
//  AMENAPP
//
//  Age collection during sign-up (BEFORE account creation)
//  Follows Meta's Instagram/Threads pattern: DOB required at onboarding
//

import SwiftUI

struct DateOfBirthCollectionView: View {
    @Binding var dateOfBirth: Date
    @Binding var isPresented: Bool
    let onContinue: (Date) -> Void
    
    @State private var showUnderAgeMessage = false
    @State private var appeared = false
    @State private var selectedDate: Date
    
    init(
        dateOfBirth: Binding<Date>,
        isPresented: Binding<Bool>,
        onContinue: @escaping (Date) -> Void
    ) {
        self._dateOfBirth = dateOfBirth
        self._isPresented = isPresented
        self.onContinue = onContinue
        
        // Default to 16 years ago (most common age for social media sign-up)
        let defaultDate = Calendar.current.date(
            byAdding: .year,
            value: -16,
            to: Date()
        ) ?? Date()
        self._selectedDate = State(initialValue: dateOfBirth.wrappedValue == Date() ? defaultDate : dateOfBirth.wrappedValue)
    }
    
    var age: Int {
        Calendar.current.dateComponents([.year], from: selectedDate, to: Date()).year ?? 0
    }
    
    var ageTier: AMENAgeAssuranceTier {
        if age < AppConfig.Legal.minimumAge {
            return .underMinimum
        } else if age < 18 {
            return .teen
        } else {
            return .adult
        }
    }
    
    var meetsMinimumAge: Bool {
        age >= AppConfig.Legal.minimumAge
    }
    
    var body: some View {
        ZStack {
            // Dark background matching sign-in flow
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                Spacer()
                
                // Main content
                VStack(spacing: 32) {
                    titleSection
                    datePickerSection
                    ageInfoSection
                    
                    if showUnderAgeMessage {
                        underAgeMessage
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Continue button
                continueButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                appeared = true
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .opacity(appeared ? 1 : 0)
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.systemScaled(52))
                .foregroundStyle(.indigo)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.8)
                .animation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7)), value: appeared)
            
            Text("What's your birthday?")
                .font(.systemScaled(28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)), value: appeared)
            
            Text("You must be at least \(AppConfig.Legal.minimumAge) to use AMEN")
                .font(.systemScaled(15))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)), value: appeared)
        }
    }
    
    // MARK: - Date Picker Section
    
    private var datePickerSection: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Date of birth",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .onChange(of: selectedDate) { _, newDate in
                dateOfBirth = newDate
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showUnderAgeMessage = !meetsMinimumAge
                }
            }
            
            // Privacy note
            privacyNote
        }
        .padding(.vertical, 8)
    }
    
    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.systemScaled(12))
                .foregroundStyle(.white.opacity(0.5))
            
            Text("Your birthday is private and won't be shown on your profile")
                .font(.systemScaled(12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .animation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)), value: appeared)
    }
    
    // MARK: - Age Info Section
    
    @ViewBuilder
    private var ageInfoSection: some View {
        if meetsMinimumAge {
            ageInfoCard
        }
    }
    
    private var ageInfoCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: ageTierIcon)
                    .font(.systemScaled(24))
                    .foregroundStyle(ageTierColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(ageTierTitle)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text(ageTierDescription)
                        .font(.systemScaled(13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ageTierColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var ageTierIcon: String {
        switch ageTier {
        case .teen: return "person.crop.circle.badge.checkmark"
        case .adult: return "checkmark.shield.fill"
        case .underMinimum: return "exclamationmark.triangle.fill"
        }
    }
    
    private var ageTierColor: Color {
        switch ageTier {
        case .teen: return .orange
        case .adult: return .green
        case .underMinimum: return .red
        }
    }
    
    private var ageTierTitle: String {
        switch ageTier {
        case .teen: return "Teen Account"
        case .adult: return "Full Access"
        case .underMinimum: return "Too Young"
        }
    }
    
    private var ageTierDescription: String {
        switch ageTier {
        case .teen: return "Some features will be restricted for your safety"
        case .adult: return "You'll have full access to all AMEN features"
        case .underMinimum: return "You must be \(AppConfig.Legal.minimumAge) or older"
        }
    }
    
    // MARK: - Under Age Message
    
    private var underAgeMessage: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(20))
                .foregroundStyle(.red)
            
            Text("Sorry, you must be \(AppConfig.Legal.minimumAge) or older to create an account")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.red.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Continue Button
    
    private var continueButton: some View {
        Button {
            if meetsMinimumAge {
                onContinue(selectedDate)
            } else {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showUnderAgeMessage = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.systemScaled(17, weight: .semibold))
                
                Image(systemName: "arrow.right")
                    .font(.systemScaled(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(meetsMinimumAge ? Color.indigo : Color.indigo.opacity(0.35))
            )
        }
        .disabled(!meetsMinimumAge)
        .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7)), value: meetsMinimumAge)
    }
}

// MARK: - Age Gate Container (audit D-01)

/// Wraps `DateOfBirthCollectionView` for the universal age gate routed from
/// `ContentView` when `authViewModel.needsAgeGate` is true. The DOB view blocks
/// under-minimum users internally; on a valid Continue we persist the DOB → tier
/// via `AgeAssuranceService` and the gate clears.
struct AgeGateContainerView: View {
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @State private var dateOfBirth = Date()
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        DateOfBirthCollectionView(
            dateOfBirth: $dateOfBirth,
            isPresented: .constant(true)
        ) { selectedDate in
            guard !isSaving else { return }
            isSaving = true
            Task {
                do {
                    try await authViewModel.completeAgeGate(dateOfBirth: selectedDate)
                } catch {
                    // Under-minimum or write failure: the DOB view already blocks
                    // under-age locally, so this path is defensive.
                    errorText = error.localizedDescription
                    isSaving = false
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let errorText {
                Text(errorText)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DateOfBirthCollectionView(
        dateOfBirth: .constant(Date()),
        isPresented: .constant(true)
    ) { date in
        print("Selected date: \(date)")
    }
}
