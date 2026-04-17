//
//  AMENChurchBusinessOnboardingView.swift
//  AMENAPP
//
//  Extended onboarding flow for Church and Business accounts.
//  Collects:
//  - Organization name
//  - Location (address/city/state)
//  - Website/social links
//  - Brief description
//  - Verification documents (for Church accounts)
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import MapKit

// MARK: - Model

struct ChurchBusinessProfile: Codable {
    var organizationName: String = ""
    var addressLine1: String = ""
    var city: String = ""
    var state: String = ""
    var zipCode: String = ""
    var website: String = ""
    var phoneNumber: String = ""
    var bio: String = ""
    var denomination: String = "" // Church only
    var category: String = "" // Business only
    var verificationDocumentURL: String? = nil
    
    var isComplete: Bool {
        !organizationName.isEmpty && !city.isEmpty && !state.isEmpty
    }
}

// MARK: - ViewModel

@MainActor
final class ChurchBusinessOnboardingViewModel: ObservableObject {
    @Published var profile = ChurchBusinessProfile()
    @Published var currentStep: Int = 0
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String?
    
    let accountType: AMENAccountType
    let totalSteps = 3
    
    init(accountType: AMENAccountType) {
        self.accountType = accountType
    }
    
    func nextStep() {
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
            currentStep = min(currentStep + 1, totalSteps - 1)
        }
    }
    
    func previousStep() {
        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.85))) {
            currentStep = max(currentStep - 1, 0)
        }
    }
    
    func canProceedFromStep(_ step: Int) -> Bool {
        switch step {
        case 0:
            return !profile.organizationName.isEmpty
        case 1:
            return !profile.city.isEmpty && !profile.state.isEmpty
        case 2:
            return true
        default:
            return false
        }
    }
    
    func submitProfile() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated"
            return false
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            lazy var db = Firestore.firestore()
            
            // Create organization profile document
            let orgData: [String: Any] = [
                "userId": uid,
                "accountType": accountType.rawValue,
                "organizationName": profile.organizationName,
                "addressLine1": profile.addressLine1,
                "city": profile.city,
                "state": profile.state,
                "zipCode": profile.zipCode,
                "website": profile.website,
                "phoneNumber": profile.phoneNumber,
                "bio": profile.bio,
                "denomination": profile.denomination,
                "category": profile.category,
                "verificationStatus": "pending",
                "createdAt": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date()),
                "schemaVersion": 1
            ]
            
            // Save to organizations collection
            try await db.collection("organizations").document(uid).setData(orgData)
            
            // Update user document with organization reference.
            // Write ALL three onboarding flags so every code path that checks
            // onboarding status considers this account fully onboarded.
            try await db.document("users/\(uid)").setData([
                "organizationId": uid,
                "organizationName": profile.organizationName,
                "isOrganizationAccount": true,
                "accountType": accountType.rawValue,
                "churchBusinessOnboardingComplete": true,
                "hasCompletedOnboarding": true,
                "onboardingCompleted": true,
                "onboardingComplete": true,
                "schemaVersion": 1
            ], merge: true)
            
            // Track analytics (simplified)
            dlog("✅ Organization profile created: \(accountType.rawValue)")
            
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Main View

struct AMENChurchBusinessOnboardingView: View {
    @StateObject private var vm: ChurchBusinessOnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(accountType: AMENAccountType) {
        _vm = StateObject(wrappedValue: ChurchBusinessOnboardingViewModel(accountType: accountType))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    ProgressBar(currentStep: vm.currentStep, totalSteps: vm.totalSteps)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    
                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            Group {
                                switch vm.currentStep {
                                case 0: BasicInfoStep(vm: vm)
                                case 1: LocationStep(vm: vm)
                                case 2: AdditionalInfoStep(vm: vm)
                                default: EmptyView()
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    }
                    
                    Spacer()
                }
                
                // Fixed bottom CTA
                VStack {
                    Spacer()
                    NavigationButtons(vm: vm, dismiss: dismiss)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .background(
                            LinearGradient(
                                colors: [Color.white.opacity(0), Color.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 100)
                            .allowsHitTesting(false)
                        )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.currentStep > 0 {
                        Button(action: { vm.previousStep() }) {
                            Image(systemName: "chevron.left")
                                .font(.systemScaled(17, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(vm.accountType == .church ? "Church Setup" : "Business Setup")
                        .font(AMENFont.semiBold(17))
                        .foregroundColor(.black)
                }
            }
        }
    }
}

// MARK: - Progress Bar

private struct ProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.black : Color(white: 0.88))
                    .frame(height: 4)
                    .frame(maxWidth: index == currentStep ? 32 : .infinity)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }
}

// MARK: - Step 1: Basic Info

private struct BasicInfoStep: View {
    @ObservedObject var vm: ChurchBusinessOnboardingViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.accountType == .church ? "Tell us about your church" : "Tell us about your organization")
                    .font(AMENFont.bold(26))
                    .foregroundColor(.black)
                
                Text("This information helps members find and connect with you.")
                    .font(AMENFont.regular(15))
                    .foregroundColor(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Form fields
            VStack(spacing: 16) {
                FormField(
                    label: vm.accountType == .church ? "Church Name" : "Organization Name",
                    placeholder: vm.accountType == .church ? "First Baptist Church" : "Your Ministry Name",
                    text: $vm.profile.organizationName
                )
                
                if vm.accountType == .church {
                    FormField(
                        label: "Denomination (Optional)",
                        placeholder: "Baptist, Methodist, Non-denominational...",
                        text: $vm.profile.denomination
                    )
                } else {
                    FormField(
                        label: "Category (Optional)",
                        placeholder: "Christian Media, Ministry, Publisher...",
                        text: $vm.profile.category
                    )
                }
                
                FormField(
                    label: "Phone Number (Optional)",
                    placeholder: "(555) 123-4567",
                    text: $vm.profile.phoneNumber,
                    keyboardType: .phonePad
                )
            }
        }
    }
}

// MARK: - Step 2: Location

private struct LocationStep: View {
    @ObservedObject var vm: ChurchBusinessOnboardingViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Where are you located?")
                    .font(AMENFont.bold(26))
                    .foregroundColor(.black)
                
                Text("Help people in your community discover you.")
                    .font(AMENFont.regular(15))
                    .foregroundColor(Color(white: 0.45))
            }
            
            // Form fields
            VStack(spacing: 16) {
                FormField(
                    label: "Address (Optional)",
                    placeholder: "123 Main Street",
                    text: $vm.profile.addressLine1
                )
                
                FormField(
                    label: "City",
                    placeholder: "City",
                    text: $vm.profile.city
                )
                
                HStack(spacing: 12) {
                    FormField(
                        label: "State",
                        placeholder: "State",
                        text: $vm.profile.state
                    )
                    
                    FormField(
                        label: "ZIP (Optional)",
                        placeholder: "12345",
                        text: $vm.profile.zipCode,
                        keyboardType: .numberPad
                    )
                }
            }
            
            // Info card
            InfoCard(
                icon: "mappin.and.ellipse",
                title: "Why location matters",
                description: "Members can find churches and ministries near them. You'll appear in location-based discovery."
            )
        }
    }
}

// MARK: - Step 3: Additional Info

private struct AdditionalInfoStep: View {
    @ObservedObject var vm: ChurchBusinessOnboardingViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Almost done!")
                    .font(AMENFont.bold(26))
                    .foregroundColor(.black)
                
                Text("Add a few more details to complete your profile.")
                    .font(AMENFont.regular(15))
                    .foregroundColor(Color(white: 0.45))
            }
            
            // Form fields
            VStack(spacing: 16) {
                FormField(
                    label: "Website (Optional)",
                    placeholder: "https://yourchurch.com",
                    text: $vm.profile.website,
                    keyboardType: .URL
                )
                
                FormTextEditor(
                    label: "About (Optional)",
                    placeholder: vm.accountType == .church 
                        ? "Share your mission, service times, and what makes your church unique..."
                        : "Share your mission and what your organization does...",
                    text: $vm.profile.bio
                )
            }
            
            // Verification notice
            VerificationNoticeCard(accountType: vm.accountType)
        }
    }
}

// MARK: - Form Components

private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AMENFont.semiBold(14))
                .foregroundColor(.black)
            
            TextField(placeholder, text: $text)
                .font(AMENFont.regular(16))
                .padding(14)
                .background(Color(white: 0.96))
                .cornerRadius(12)
                .keyboardType(keyboardType)
                .autocapitalization(keyboardType == .URL ? .none : .words)
        }
    }
}

private struct FormTextEditor: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AMENFont.semiBold(14))
                .foregroundColor(.black)
            
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(AMENFont.regular(16))
                        .foregroundColor(Color(white: 0.65))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
                
                TextEditor(text: $text)
                    .font(AMENFont.regular(16))
                    .padding(10)
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(white: 0.96))
                    .cornerRadius(12)
            }
        }
    }
}

private struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(20))
                .foregroundColor(Color(red: 0.30, green: 0.50, blue: 0.90))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.black)
                
                Text(description)
                    .font(AMENFont.regular(14))
                    .foregroundColor(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(red: 0.30, green: 0.50, blue: 0.90).opacity(0.08))
        .cornerRadius(16)
    }
}

private struct VerificationNoticeCard: View {
    let accountType: AMENAccountType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: accountType == .church ? "checkmark.seal.fill" : "star.fill")
                    .font(.systemScaled(18))
                    .foregroundColor(accountType == .church ? .black : Color(red: 0.85, green: 0.15, blue: 0.15))
                
                Text("Verification")
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(.black)
            }
            
            Text(accountType == .church 
                ? "Your church will be reviewed for verification. Once approved, you'll receive a verified badge (black checkmark)."
                : "Your business will be reviewed for verification. Once approved, you'll receive a verified badge (red checkmark).")
                .font(AMENFont.regular(14))
                .foregroundColor(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(white: 0.96))
        .cornerRadius(16)
    }
}

// MARK: - Navigation Buttons

private struct NavigationButtons: View {
    @ObservedObject var vm: ChurchBusinessOnboardingViewModel
    let dismiss: DismissAction
    @State private var showingConfirmation = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Error message
            if let error = vm.errorMessage {
                Text(error)
                    .font(AMENFont.regular(13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Primary CTA
            Button(action: {
                handlePrimaryAction()
            }) {
                ZStack {
                    Capsule()
                        .fill(canProceed ? Color.black : Color(white: 0.88))
                    
                    if vm.isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Text(primaryButtonLabel)
                            .font(AMENFont.semiBold(17))
                            .foregroundColor(canProceed ? .white : Color(white: 0.55))
                    }
                }
                .frame(height: 54)
            }
            .disabled(!canProceed || vm.isSubmitting)
            
            // Skip button (only on optional steps)
            if vm.currentStep > 0 && vm.currentStep < vm.totalSteps - 1 {
                Button(action: { vm.nextStep() }) {
                    Text("Skip for now")
                        .font(AMENFont.regular(15))
                        .foregroundColor(Color(white: 0.45))
                }
            }
        }
        .alert("Profile Complete", isPresented: $showingConfirmation) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Your \(vm.accountType == .church ? "church" : "business") profile has been submitted for verification.")
        }
    }
    
    private var canProceed: Bool {
        vm.canProceedFromStep(vm.currentStep)
    }
    
    private var primaryButtonLabel: String {
        if vm.currentStep < vm.totalSteps - 1 {
            return "Continue"
        } else {
            return "Complete Setup"
        }
    }
    
    private func handlePrimaryAction() {
        if vm.currentStep < vm.totalSteps - 1 {
            vm.nextStep()
        } else {
            // Final step - submit
            Task {
                let success = await vm.submitProfile()
                if success {
                    showingConfirmation = true
                }
            }
        }
    }
}

// MARK: - Previews

struct AMENChurchBusinessOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AMENChurchBusinessOnboardingView(accountType: .church)
                .previewDisplayName("Church Setup")
            
            AMENChurchBusinessOnboardingView(accountType: .business)
                .previewDisplayName("Business Setup")
        }
    }
}
