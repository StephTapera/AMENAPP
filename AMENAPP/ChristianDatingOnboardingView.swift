//
//  ChristianDatingOnboardingView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct ChristianDatingOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    var onComplete: (() -> Void)? = nil
    @State private var currentStep = 0
    @State private var selectedGender = ""
    @State private var selectedAgeRange = ""
    @State private var selectedDenomination = ""
    @State private var churchName = ""
    @State private var churchCity = ""
    @State private var selectedInterests: Set<String> = []
    @State private var selectedDealBreakers: Set<String> = []
    @State private var selectedPriorities: Set<String> = []
    @State private var selectedMeetingPreference = ""
    @State private var selectedFaithLevel = ""
    @State private var phoneNumber = ""
    @State private var emergencyContact = ""
    @State private var agreedToVerification = false
    @State private var bio = ""
    @State private var agreedToGuidelines = false
    @State private var showMainView = false
    @State private var showSafetyGuidelines = false
    
    let totalSteps = 9
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.pink, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 6)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal)
                .padding(.top)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case 0:
                            WelcomeStep()
                        case 1:
                            SafetyStep(agreedToGuidelines: $agreedToGuidelines)
                        case 2:
                            DatingVerificationStep(phoneNumber: $phoneNumber, emergencyContact: $emergencyContact, agreedToVerification: $agreedToVerification)
                        case 3:
                            BasicInfoStep(selectedGender: $selectedGender, selectedAgeRange: $selectedAgeRange)
                        case 4:
                            FaithStep(selectedDenomination: $selectedDenomination, selectedFaithLevel: $selectedFaithLevel)
                        case 5:
                            ChurchInfoStep(churchName: $churchName, churchCity: $churchCity)
                        case 6:
                            PrioritiesStep(selectedPriorities: $selectedPriorities, selectedDealBreakers: $selectedDealBreakers)
                        case 7:
                            MeetingSafetyStep(selectedMeetingPreference: $selectedMeetingPreference)
                        case 8:
                            InterestsStep(selectedInterests: $selectedInterests, bio: $bio)
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                
                // Bottom buttons matching the photo design
                VStack(spacing: 16) {
                    if currentStep < totalSteps - 1 {
                        // Continue button - rounded capsule like photo
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentStep += 1
                            }
                        } label: {
                            HStack {
                                if !canProceed() {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 16))
                                }
                                
                                Text(canProceed() ? "Continue" : "Complete all fields")
                                    .font(.custom("OpenSans-Bold", size: 17))
                                
                                if canProceed() {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: canProceed() ? [.pink, .purple] : [.gray, .gray],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .shadow(color: canProceed() ? .pink.opacity(0.3) : .gray.opacity(0.2), radius: 12, y: 4)
                        }
                        .disabled(!canProceed())
                        .animation(.easeInOut(duration: 0.2), value: canProceed())
                    } else {
                        // Get Started button
                        Button {
                            if let onComplete = onComplete {
                                // If there's a completion callback, call it and dismiss
                                onComplete()
                                dismiss()
                            } else {
                                // Otherwise, show the main view (old behavior)
                                showMainView = true
                            }
                        } label: {
                            Text("Get Started")
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.pink, .purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                                .shadow(color: .pink.opacity(0.3), radius: 12, y: 4)
                        }
                        .disabled(selectedInterests.isEmpty)
                        .opacity(selectedInterests.isEmpty ? 0.5 : 1.0)
                    }
                    
                    if currentStep > 0 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentStep -= 1
                            }
                        } label: {
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Christian Dating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSafetyGuidelines = true
                    } label: {
                        Image(systemName: "shield.checkmark.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.pink)
                    }
                }
            }
            .fullScreenCover(isPresented: $showMainView) {
                ChristianDatingView()
            }
            .sheet(isPresented: $showSafetyGuidelines) {
                SafetyGuidelinesView(type: .dating)
            }
        }
    }
    
    private func canProceed() -> Bool {
        switch currentStep {
        case 1:
            return agreedToGuidelines
        case 2:
            return !phoneNumber.isEmpty && !emergencyContact.isEmpty && agreedToVerification
        case 3:
            return !selectedGender.isEmpty && !selectedAgeRange.isEmpty
        case 4:
            return !selectedDenomination.isEmpty && !selectedFaithLevel.isEmpty
        case 5:
            return !churchName.isEmpty && !churchCity.isEmpty
        case 6:
            return selectedPriorities.count >= 2
        case 7:
            return !selectedMeetingPreference.isEmpty
        default:
            return true
        }
    }
}

// MARK: - Safety Step (NEW)
struct SafetyStep: View {
    @Binding var agreedToGuidelines: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkmark.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.pink)
                    
                    Text("Your Safety First")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("We're committed to creating a safe and respectful Christian dating community.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                SafetyFeatureRow(
                    icon: "checkmark.shield.fill",
                    title: "ID Verification",
                    description: "All users verify their identity"
                )
                
                SafetyFeatureRow(
                    icon: "eye.slash.fill",
                    title: "Privacy Controls",
                    description: "Control who sees your profile"
                )
                
                SafetyFeatureRow(
                    icon: "exclamationmark.bubble.fill",
                    title: "Report & Block",
                    description: "Easy tools to report concerns"
                )
                
                SafetyFeatureRow(
                    icon: "person.badge.shield.checkmark.fill",
                    title: "Faith-Based Moderation",
                    description: "Christian values guide our community"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.pink.opacity(0.05))
            )
            
            Toggle(isOn: $agreedToGuidelines) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I agree to the Community Guidelines")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    
                    Text("Treat others with respect, honesty, and Christ-like love")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.pink)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(agreedToGuidelines ? Color.pink.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
            )
            
            Spacer()
        }
    }
}

// MARK: - Safety Feature Row
struct SafetyFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.pink)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Priorities Step (NEW)
struct PrioritiesStep: View {
    @Binding var selectedPriorities: Set<String>
    @Binding var selectedDealBreakers: Set<String>
    
    let priorities = [
        "Strong Faith Foundation",
        "Active in Church",
        "Wants Children",
        "Career Focused",
        "Family Oriented",
        "Ministry Involvement"
    ]
    
    let dealBreakers = [
        "Must be born again",
        "No smoking/drinking",
        "Shared denomination",
        "Same political views",
        "Local only (no long-distance)"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Matters Most?")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("This helps us find your most compatible matches")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Priorities (Select at least 2)")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                ForEach(priorities, id: \.self) { priority in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedPriorities.contains(priority) {
                                selectedPriorities.remove(priority)
                            } else {
                                selectedPriorities.insert(priority)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedPriorities.contains(priority) ? "heart.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selectedPriorities.contains(priority) ? .pink : .gray)
                            
                            Text(priority)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedPriorities.contains(priority) ? Color.pink.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedPriorities.contains(priority) ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Non-Negotiables (Optional)")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                ForEach(dealBreakers, id: \.self) { dealBreaker in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedDealBreakers.contains(dealBreaker) {
                                selectedDealBreakers.remove(dealBreaker)
                            } else {
                                selectedDealBreakers.insert(dealBreaker)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedDealBreakers.contains(dealBreaker) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18))
                                .foregroundStyle(selectedDealBreakers.contains(dealBreaker) ? .pink : .gray)
                            
                            Text(dealBreaker)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Welcome Step
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
            }
            
            VStack(spacing: 12) {
                Text("Welcome to Christian Dating")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Connect with fellow believers who share your faith and values. Let's create your profile in just a few steps.")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
    }
}

// MARK: - Basic Info Step
struct BasicInfoStep: View {
    @Binding var selectedGender: String
    @Binding var selectedAgeRange: String
    
    let genders = ["Male", "Female"]
    let ageRanges = ["18-24", "25-29", "30-34", "35-39", "40-49", "50+"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Basic Information")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Help us match you with compatible believers")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("I am")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                HStack(spacing: 12) {
                    ForEach(genders, id: \.self) { gender in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedGender = gender
                            }
                        } label: {
                            Text(gender)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(selectedGender == gender ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedGender == gender ? 
                                              LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing) :
                                              LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                        )
                                )
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Age Range")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ageRanges, id: \.self) { age in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedAgeRange = age
                            }
                        } label: {
                            Text(age)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(selectedAgeRange == age ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedAgeRange == age ?
                                              LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing) :
                                              LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                        )
                                )
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Faith Step
struct FaithStep: View {
    @Binding var selectedDenomination: String
    @Binding var selectedFaithLevel: String
    
    let denominations = [
        "Non-Denominational",
        "Baptist",
        "Catholic",
        "Pentecostal",
        "Methodist",
        "Presbyterian",
        "Lutheran",
        "Anglican/Episcopal",
        "Orthodox",
        "Other"
    ]
    
    let faithLevels = [
        "New Believer",
        "Growing in Faith",
        "Mature Believer",
        "Church Leader"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Faith Background")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("This helps us understand your spiritual journey")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                
                // Selection status indicator
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: selectedDenomination.isEmpty ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(selectedDenomination.isEmpty ? Color.secondary : Color.green)
                        Text("Denomination")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(selectedDenomination.isEmpty ? Color.secondary : Color.green)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: selectedFaithLevel.isEmpty ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(selectedFaithLevel.isEmpty ? Color.secondary : Color.green)
                        Text("Faith Journey")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(selectedFaithLevel.isEmpty ? Color.secondary : Color.green)
                    }
                }
                .padding(.top, 4)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Church Denomination")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                ForEach(denominations, id: \.self) { denomination in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDenomination = denomination
                        }
                    } label: {
                        HStack {
                            Text(denomination)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(selectedDenomination == denomination ? .white : .primary)
                            
                            Spacer()
                            
                            if selectedDenomination == denomination {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedDenomination == denomination ?
                                      LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing) :
                                      LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Faith Journey")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                ForEach(faithLevels, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFaithLevel = level
                        }
                    } label: {
                        HStack {
                            Text(level)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(selectedFaithLevel == level ? .white : .primary)
                            
                            Spacer()
                            
                            if selectedFaithLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedFaithLevel == level ?
                                      LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing) :
                                      LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Interests Step
struct InterestsStep: View {
    @Binding var selectedInterests: Set<String>
    @Binding var bio: String
    
    let interests = [
        "Worship Music",
        "Bible Study",
        "Prayer",
        "Missions",
        "Youth Ministry",
        "Volunteering",
        "Church Events",
        "Hiking",
        "Coffee",
        "Reading",
        "Cooking",
        "Fitness"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Interests")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Select at least 3 interests to help us find your match")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(interests, id: \.self) { interest in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedInterests.contains(interest) {
                                selectedInterests.remove(interest)
                            } else {
                                selectedInterests.insert(interest)
                            }
                        }
                    } label: {
                        HStack {
                            Text(interest)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedInterests.contains(interest) ? .white : .primary)
                            
                            if selectedInterests.contains(interest) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedInterests.contains(interest) ?
                                      LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing) :
                                      LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell us about yourself (Optional)")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                TextField("Share a little about your faith journey...", text: $bio, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .padding()
                    .lineLimit(4...6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
            
            Spacer()
        }
    }
}

// MARK: - Safety Guidelines View (Full Sheet)

struct SafetyGuidelinesView: View {
    @Environment(\.dismiss) var dismiss
    let type: GuidelineType
    
    enum GuidelineType {
        case dating
        case friends
        
        var title: String {
            switch self {
            case .dating: return "Christian Dating Safety"
            case .friends: return "Find Friends Safety"
            }
        }
        
        var color: Color {
            switch self {
            case .dating: return .pink
            case .friends: return .blue
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "shield.checkmark.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(type.color)
                        
                        Text("Your Safety is Our Priority")
                            .font(.custom("OpenSans-Bold", size: 26))
                        
                        Text("We're committed to creating a safe, respectful, and Christ-centered community for all members.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(type.color.opacity(0.08))
                    )
                    
                    // Community Guidelines
                    GuidelineSection(
                        title: "Community Guidelines",
                        icon: "list.bullet.rectangle.portrait.fill",
                        color: type.color,
                        items: [
                            "Treat all members with Christ-like love and respect",
                            "Be honest and authentic in your profile",
                            "No harassment, bullying, or inappropriate behavior",
                            "Keep conversations appropriate and faith-focused",
                            "Report any concerning behavior immediately",
                            "Respect others' boundaries and privacy"
                        ]
                    )
                    
                    // Safety Tips
                    GuidelineSection(
                        title: "Safety Tips",
                        icon: "lightbulb.fill",
                        color: .orange,
                        items: [
                            "Meet in public places for first meetings",
                            "Tell a friend or family member where you're going",
                            "Don't share personal information too quickly",
                            "Trust your instincts - if something feels off, it probably is",
                            "Take your time getting to know someone",
                            "Never send money to someone you haven't met"
                        ]
                    )
                    
                    // Privacy & Data
                    GuidelineSection(
                        title: "Privacy & Data Protection",
                        icon: "lock.shield.fill",
                        color: .green,
                        items: [
                            "Your data is encrypted and secure",
                            "Control who can see your profile",
                            "Block or report users anytime",
                            "We never sell your information",
                            "Delete your account and data anytime",
                            "ID verification for all users"
                        ]
                    )
                    
                    // What We Don't Allow
                    GuidelineSection(
                        title: "What We Don't Allow",
                        icon: "xmark.shield.fill",
                        color: .red,
                        items: [
                            "Fake profiles or catfishing",
                            "Solicitation or spam",
                            "Hate speech or discrimination",
                            "Sexual harassment or inappropriate content",
                            "Minors (must be 18+)",
                            "Commercial or promotional activity"
                        ]
                    )
                    
                    // Report & Support
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(type.color)
                            
                            Text("Report Concerns")
                                .font(.custom("OpenSans-Bold", size: 20))
                        }
                        
                        Text("If you experience or witness anything that violates our guidelines, please report it immediately. Our team reviews all reports within 24 hours.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                        
                        Button {
                            // Open support email or form
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                Text("Contact Support")
                                    .font(.custom("OpenSans-Bold", size: 15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(type.color)
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(type.color.opacity(0.3), lineWidth: 2)
                    )
                }
                .padding()
            }
            .navigationTitle("Safety & Guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Guideline Section
struct GuidelineSection: View {
    let title: String
    let icon: String
    let color: Color
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 20))
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(color)
                            .padding(.top, 2)
                        
                        Text(item)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .lineSpacing(4)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.05))
        )
    }
}

// MARK: - Dating Verification Step (NEW - For Safety)
struct DatingVerificationStep: View {
    @Binding var phoneNumber: String
    @Binding var emergencyContact: String
    @Binding var agreedToVerification: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    Text("Verification & Safety")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("We verify all users to ensure a safe community. This information is kept private and secure.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.pink)
                        Text("Phone Number (for verification)")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    
                    TextField("(555) 123-4567", text: $phoneNumber)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .keyboardType(.phonePad)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    
                    Text("We'll send a verification code to confirm your identity")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundStyle(.pink)
                        Text("Emergency Contact Name")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    
                    TextField("John Doe", text: $emergencyContact)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    
                    Text("A trusted person we can contact in case of emergencies")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.05))
            )
            
            Toggle(isOn: $agreedToVerification) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I agree to verification")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    
                    Text("I understand my information will be verified and kept secure")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.pink)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(agreedToVerification ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
            )
            
            Spacer()
        }
    }
}

// MARK: - Church Info Step (NEW)
struct ChurchInfoStep: View {
    @Binding var churchName: String
    @Binding var churchCity: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    
                    Text("Your Church Home")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Connect with others who attend your church or nearby congregations")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cross.fill")
                            .foregroundStyle(.pink)
                        Text("Church Name")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    
                    TextField("Grace Community Church", text: $churchName)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.pink)
                        Text("City/Town")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    
                    TextField("Los Angeles, CA", text: $churchCity)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.05))
            )
            
            // Benefits of sharing church info
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Match with people from your church")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Find believers in your area")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Build community-based connections")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.05))
            )
            
            Spacer()
        }
    }
}

// MARK: - Meeting Safety Step (NEW)
struct MeetingSafetyStep: View {
    @Binding var selectedMeetingPreference: String
    
    let meetingPreferences = [
        "Group settings first",
        "Public places only",
        "Coffee & conversation",
        "Church events together",
        "Virtual first, then in-person"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    
                    Text("Meeting Preferences")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("How would you prefer to meet someone new? This helps ensure safe, comfortable first meetings.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(meetingPreferences, id: \.self) { preference in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMeetingPreference = preference
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedMeetingPreference == preference ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(selectedMeetingPreference == preference ? .pink : .gray)
                            
                            Text(preference)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedMeetingPreference == preference ? Color.pink.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedMeetingPreference == preference ? Color.pink.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            
            // Safety Tips
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text("Safety Tips")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    SafetyTipRow(text: "Always meet in public places first")
                    SafetyTipRow(text: "Tell a friend where you're going")
                    SafetyTipRow(text: "Keep first meetings short and casual")
                    SafetyTipRow(text: "Trust your instincts")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.05))
            )
            
            Spacer()
        }
    }
}

struct SafetyTipRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ChristianDatingOnboardingView()
}
