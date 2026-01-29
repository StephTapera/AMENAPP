//
//  FindFriendsOnboardingView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct FindFriendsOnboardingView: View {
    @Environment(\.dismiss) var dismiss
    var onComplete: (() -> Void)? = nil
    @State private var currentStep = 0
    @State private var selectedAgeGroup = ""
    @State private var churchName = ""
    @State private var churchCity = ""
    @State private var selectedInterests: Set<String> = []
    @State private var selectedActivities: Set<String> = []
    @State private var selectedFriendshipGoals: Set<String> = []
    @State private var selectedMeetingPreference = ""
    @State private var phoneNumber = ""
    @State private var agreedToVerification = false
    @State private var bio = ""
    @State private var agreedToGuidelines = false
    @State private var showMainView = false
    @State private var showSafetyGuidelines = false
    
    let totalSteps = 8
    
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
                                    colors: [.blue, .cyan],
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
                            FriendsWelcomeStep()
                        case 1:
                            FriendsSafetyStep(agreedToGuidelines: $agreedToGuidelines)
                        case 2:
                            FriendsVerificationStep(phoneNumber: $phoneNumber, agreedToVerification: $agreedToVerification)
                        case 3:
                            FriendsInfoStep(selectedAgeGroup: $selectedAgeGroup, selectedInterests: $selectedInterests)
                        case 4:
                            FriendsChurchInfoStep(churchName: $churchName, churchCity: $churchCity)
                        case 5:
                            FriendshipGoalsStep(selectedFriendshipGoals: $selectedFriendshipGoals)
                        case 6:
                            FriendsMeetingSafetyStep(selectedMeetingPreference: $selectedMeetingPreference)
                        case 7:
                            FriendsActivitiesStep(selectedActivities: $selectedActivities, bio: $bio)
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                
                // Bottom buttons
                VStack(spacing: 16) {
                    if currentStep < totalSteps - 1 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentStep += 1
                            }
                        } label: {
                            Text("Continue")
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)
                        }
                        .disabled(!canProceed())
                        .opacity(canProceed() ? 1.0 : 0.5)
                    } else {
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
                                                colors: [.blue, .cyan],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)
                        }
                        .disabled(selectedActivities.isEmpty)
                        .opacity(selectedActivities.isEmpty ? 0.5 : 1.0)
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
            .navigationTitle("Find Friends")
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
                            .foregroundStyle(.blue)
                    }
                }
            }
            .fullScreenCover(isPresented: $showMainView) {
                FindFriendsView()
            }
            .sheet(isPresented: $showSafetyGuidelines) {
                SafetyGuidelinesView(type: .friends)
            }
        }
    }
    
    private func canProceed() -> Bool {
        switch currentStep {
        case 1:
            return agreedToGuidelines
        case 2:
            return !phoneNumber.isEmpty && agreedToVerification
        case 3:
            return !selectedAgeGroup.isEmpty && !selectedInterests.isEmpty
        case 4:
            return !churchName.isEmpty && !churchCity.isEmpty
        case 5:
            return !selectedFriendshipGoals.isEmpty
        case 6:
            return !selectedMeetingPreference.isEmpty
        default:
            return true
        }
    }
}

// MARK: - Friends Safety Step (NEW)
struct FriendsSafetyStep: View {
    @Binding var agreedToGuidelines: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkmark.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    
                    Text("Safe Connections")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("We're building a safe space for authentic Christian friendships.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                SafetyFeatureRow(
                    icon: "checkmark.shield.fill",
                    title: "Verified Profiles",
                    description: "All users go through verification"
                )
                
                SafetyFeatureRow(
                    icon: "person.2.badge.shield.checkmark",
                    title: "Group Activities",
                    description: "Meet in safe group settings first"
                )
                
                SafetyFeatureRow(
                    icon: "exclamationmark.bubble.fill",
                    title: "Report Tools",
                    description: "Easy reporting of concerns"
                )
                
                SafetyFeatureRow(
                    icon: "hand.raised.fill",
                    title: "Respectful Community",
                    description: "Biblical values guide all interactions"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.05))
            )
            
            Toggle(isOn: $agreedToGuidelines) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I agree to the Community Guidelines")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    
                    Text("Be respectful, authentic, and build genuine friendships")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(agreedToGuidelines ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
            )
            
            Spacer()
        }
    }
}

// MARK: - Friendship Goals Step (NEW)
struct FriendshipGoalsStep: View {
    @Binding var selectedFriendshipGoals: Set<String>
    
    let friendshipGoals = [
        "Prayer Partners",
        "Bible Study Buddy",
        "Accountability Partner",
        "Activity Friends",
        "Mentorship",
        "Small Group Connection",
        "Ministry Collaboration",
        "Just Hang Out"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What are you looking for?")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Select what types of friendships you're interested in")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(friendshipGoals, id: \.self) { goal in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedFriendshipGoals.contains(goal) {
                                selectedFriendshipGoals.remove(goal)
                            } else {
                                selectedFriendshipGoals.insert(goal)
                            }
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(goal)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedFriendshipGoals.contains(goal) ? .white : .primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 40)
                            
                            if selectedFriendshipGoals.contains(goal) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedFriendshipGoals.contains(goal) ?
                                      LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
                                      LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Friends Welcome Step
struct FriendsWelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
            }
            
            VStack(spacing: 12) {
                Text("Find Your Faith Community")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Build meaningful friendships with local believers who share your interests. Let's find your community!")
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

// MARK: - Friends Info Step
struct FriendsInfoStep: View {
    @Binding var selectedAgeGroup: String
    @Binding var selectedInterests: Set<String>
    
    let ageGroups = ["18-24", "25-34", "35-44", "45-54", "55+"]
    let interests = [
        "Bible Study",
        "Prayer Group",
        "Worship",
        "Ministry",
        "Sports",
        "Music",
        "Arts & Crafts",
        "Outdoor Activities",
        "Book Club",
        "Volunteering"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About You")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Help us connect you with the right community")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Age Group")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ageGroups, id: \.self) { age in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedAgeGroup = age
                            }
                        } label: {
                            Text(age)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(selectedAgeGroup == age ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedAgeGroup == age ?
                                              LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
                                              LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                        )
                                )
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Interests (Select at least 2)")
                    .font(.custom("OpenSans-Bold", size: 16))
                
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
                                          LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
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

// MARK: - Friends Activities Step
struct FriendsActivitiesStep: View {
    @Binding var selectedActivities: Set<String>
    @Binding var bio: String
    
    let activities = [
        "Group Bible Study",
        "Community Events",
        "Prayer Partners",
        "Church Activities",
        "Coffee Meetups",
        "Game Nights",
        "Hiking Groups",
        "Service Projects"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What activities interest you?")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Select at least 2 activities you'd like to participate in")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(activities, id: \.self) { activity in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if selectedActivities.contains(activity) {
                                selectedActivities.remove(activity)
                            } else {
                                selectedActivities.insert(activity)
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(activity)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(selectedActivities.contains(activity) ? .white : .primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            
                            if selectedActivities.contains(activity) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedActivities.contains(activity) ?
                                      LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
                                      LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Introduce yourself (Optional)")
                    .font(.custom("OpenSans-Bold", size: 16))
                
                TextField("Share what you're looking for in a friend...", text: $bio, axis: .vertical)
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

// MARK: - Friends Verification Step (NEW)
struct FriendsVerificationStep: View {
    @Binding var phoneNumber: String
    @Binding var agreedToVerification: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    Text("Verification")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("We verify all users to ensure a trusted community for making friends.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.blue)
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
            .tint(.blue)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(agreedToVerification ? Color.green.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
            )
            
            Spacer()
        }
    }
}

// MARK: - Friends Church Info Step (NEW)
struct FriendsChurchInfoStep: View {
    @Binding var churchName: String
    @Binding var churchCity: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                    
                    Text("Your Church Community")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Connect with friends from your church or nearby congregations")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cross.fill")
                            .foregroundStyle(.blue)
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
                            .foregroundStyle(.blue)
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
            
            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Find friends at your church")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connect with nearby believers")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Join local faith communities")
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

// MARK: - Friends Meeting Safety Step (NEW)
struct FriendsMeetingSafetyStep: View {
    @Binding var selectedMeetingPreference: String
    
    let meetingPreferences = [
        "Group meetups first",
        "Church events & activities",
        "Public coffee shops",
        "Community service together",
        "Online chat first"
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
                
                Text("How would you prefer to meet new friends? Choose what feels safest and most comfortable for you.")
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
                                .foregroundStyle(selectedMeetingPreference == preference ? .blue : .gray)
                            
                            Text(preference)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedMeetingPreference == preference ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedMeetingPreference == preference ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            
            // Safety Tips
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text("Friendship Safety Tips")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    FriendSafetyTipRow(text: "Meet in groups or public places first")
                    FriendSafetyTipRow(text: "Tell someone where you're going")
                    FriendSafetyTipRow(text: "Get to know people gradually")
                    FriendSafetyTipRow(text: "Trust your instincts always")
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

struct FriendSafetyTipRow: View {
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
    FindFriendsOnboardingView()
}
