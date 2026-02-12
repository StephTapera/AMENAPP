//
//  OnboardingAdvancedComponents.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

// MARK: - Conversation Starters Step (Dating)
struct ConversationStartersStep: View {
    @Binding var selectedStarters: Set<String>
    let gradientColors: [Color]
    
    let starters = [
        "What's your testimony?",
        "Favorite Christian book?",
        "Dream mission trip destination?",
        "What ministry are you passionate about?",
        "Coffee or tea after church?",
        "Favorite biblical character?",
        "What does your prayer life look like?",
        "Ideal Sunday afternoon?",
        "What brings you closer to God?",
        "Favorite way to serve others?"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conversation Starters")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Pick topics you'd love to discuss (choose 3-5)")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(starters, id: \.self) { starter in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedStarters.contains(starter) {
                                    selectedStarters.remove(starter)
                                } else {
                                    selectedStarters.insert(starter)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedStarters.contains(starter) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selectedStarters.contains(starter) ? gradientColors[0] : .secondary)
                                
                                Text(starter)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedStarters.contains(starter) ? gradientColors[0].opacity(0.1) : Color.gray.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(selectedStarters.contains(starter) ? gradientColors[0] : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Counter
            HStack {
                Spacer()
                Text("\(selectedStarters.count) selected")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(selectedStarters.count >= 3 ? gradientColors[0] : .secondary)
            }
        }
    }
}

// MARK: - Mentor/Mentee Toggle Step (Friends)
struct MentorMenteeStep: View {
    @Binding var mentorPreference: MentorPreference
    @Binding var experienceAreas: Set<String>
    let gradientColors: [Color]
    
    let areas = [
        "New Believer Support",
        "Bible Study",
        "Prayer Life",
        "Ministry Leadership",
        "Marriage & Relationships",
        "Parenting",
        "Career & Purpose",
        "Spiritual Gifts",
        "Overcoming Struggles",
        "Faith & Daily Life"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mentorship")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Connect with others for spiritual growth")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            // Mentor preference selection
            VStack(spacing: 12) {
                MentorOptionCard(
                    icon: "person.fill.checkmark",
                    title: "Looking for a Mentor",
                    description: "I want guidance from a more experienced believer",
                    isSelected: mentorPreference == .seekingMentor,
                    gradientColors: gradientColors
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mentorPreference = .seekingMentor
                    }
                }
                
                MentorOptionCard(
                    icon: "person.fill.badge.plus",
                    title: "Open to Mentoring",
                    description: "I'm willing to share my experience and help others grow",
                    isSelected: mentorPreference == .willingToMentor,
                    gradientColors: gradientColors
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mentorPreference = .willingToMentor
                    }
                }
                
                MentorOptionCard(
                    icon: "person.2.fill",
                    title: "Peer-to-Peer Only",
                    description: "Looking for friends at a similar stage in their faith journey",
                    isSelected: mentorPreference == .peerToPeer,
                    gradientColors: gradientColors
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mentorPreference = .peerToPeer
                    }
                }
            }
            
            // Experience areas (if willing to mentor)
            if mentorPreference == .willingToMentor {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Areas I can help with:")
                        .font(.custom("OpenSans-Bold", size: 16))
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(areas, id: \.self) { area in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if experienceAreas.contains(area) {
                                        experienceAreas.remove(area)
                                    } else {
                                        experienceAreas.insert(area)
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(area)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(experienceAreas.contains(area) ? .white : .primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                    
                                    if experienceAreas.contains(area) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: 70)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(experienceAreas.contains(area) ?
                                              LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing) :
                                              LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            
            Spacer()
        }
    }
}

struct MentorOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? gradientColors[0] : .secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? gradientColors[0].opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? gradientColors[0] : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum MentorPreference {
    case seekingMentor
    case willingToMentor
    case peerToPeer
}

// MARK: - Review Step
struct ReviewStep: View {
    let profileData: ProfileData
    let gradientColors: [Color]
    let onEdit: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review Your Profile")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Make sure everything looks good before we match you")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 16) {
                    // Photos
                    if !profileData.photos.isEmpty {
                        ReviewSection(title: "Photos", icon: "photo.fill", gradientColors: gradientColors) {
                            onEdit("photos")
                        } content: {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(profileData.photos.enumerated()), id: \.offset) { index, photo in
                                        Image(uiImage: photo)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(gradientColors[0].opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    
                    // Basic Info
                    ReviewSection(title: "Basic Info", icon: "person.fill", gradientColors: gradientColors) {
                        onEdit("basic")
                    } content: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let gender = profileData.gender {
                                ReviewInfoRow(label: "Gender", value: gender)
                            }
                            if let age = profileData.ageRange {
                                ReviewInfoRow(label: "Age", value: age)
                            }
                            if let location = profileData.location {
                                ReviewInfoRow(label: "Location", value: location)
                            }
                        }
                    }
                    
                    // Faith Background
                    if let denomination = profileData.denomination {
                        ReviewSection(title: "Faith", icon: "cross.fill", gradientColors: gradientColors) {
                            onEdit("faith")
                        } content: {
                            ReviewInfoRow(label: "Denomination", value: denomination)
                        }
                    }
                    
                    // Interests
                    if !profileData.interests.isEmpty {
                        ReviewSection(title: "Interests", icon: "star.fill", gradientColors: gradientColors) {
                            onEdit("interests")
                        } content: {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(profileData.interests), id: \.self) { interest in
                                    Text(interest)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(gradientColors[0])
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(gradientColors[0].opacity(0.1))
                                        )
                                }
                            }
                        }
                    }
                    
                    // Bio
                    if let bio = profileData.bio, !bio.isEmpty {
                        ReviewSection(title: "About Me", icon: "text.quote", gradientColors: gradientColors) {
                            onEdit("bio")
                        } content: {
                            Text(bio)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Ice Breakers
                    if !profileData.iceBreakerAnswers.isEmpty {
                        ReviewSection(title: "Ice Breakers", icon: "lightbulb.fill", gradientColors: gradientColors) {
                            onEdit("icebreakers")
                        } content: {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(profileData.iceBreakerAnswers.keys.sorted()), id: \.self) { key in
                                    if let answer = profileData.iceBreakerAnswers[key], !answer.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(questionForKey(key))
                                                .font(.custom("OpenSans-Bold", size: 13))
                                                .foregroundStyle(.secondary)
                                            Text(answer)
                                                .font(.custom("OpenSans-Regular", size: 14))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Verification Status
                    ReviewSection(title: "Verification", icon: "checkmark.shield.fill", gradientColors: gradientColors) {
                        onEdit("verification")
                    } content: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: profileData.isEmailVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(profileData.isEmailVerified ? .green : .secondary)
                                Text("Email")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                Spacer()
                                Text(profileData.isEmailVerified ? "Verified" : "Not Verified")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(profileData.isEmailVerified ? .green : .secondary)
                            }
                            
                            if profileData.isPhoneVerified {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Phone")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                    Spacer()
                                    Text("Verified")
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func questionForKey(_ key: String) -> String {
        switch key {
        case "verse": return "Favorite Bible verse"
        case "worship": return "Favorite worship song"
        case "hobby": return "Free time activities"
        case "fun_fact": return "Fun fact"
        default: return key
        }
    }
}

struct ReviewSection<Content: View>: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let onEdit: () -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(gradientColors[0])
                }
                
                Spacer()
                
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(gradientColors[0])
                }
            }
            
            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

struct ReviewInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Onboarding Success Screen
struct OnboardingSuccessScreen: View {
    let gradientColors: [Color]
    let onComplete: () -> Void
    @State private var showConfetti = false
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success animation
            ZStack {
                // Confetti effect
                ForEach(0..<20, id: \.self) { index in
                    Circle()
                        .fill(gradientColors[index % gradientColors.count].opacity(0.6))
                        .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 4...8))
                        .offset(
                            x: showConfetti ? CGFloat.random(in: -150...150) : 0,
                            y: showConfetti ? CGFloat.random(in: -200...0) : 0
                        )
                        .opacity(showConfetti ? 0 : 1)
                        .animation(.easeOut(duration: Double.random(in: 0.5...1.0)).delay(Double(index) * 0.05), value: showConfetti)
                }
                
                // Main icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(scale)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(scale)
                }
            }
            
            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(.primary)
                    .opacity(opacity)
                
                Text("Your profile is complete and ready to connect with others")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .opacity(opacity)
            }
            
            VStack(spacing: 12) {
                SuccessFeatureRow(icon: "person.2.fill", text: "Start browsing profiles", gradientColors: gradientColors)
                SuccessFeatureRow(icon: "heart.fill", text: "Send likes and messages", gradientColors: gradientColors)
                SuccessFeatureRow(icon: "sparkles", text: "Get personalized matches", gradientColors: gradientColors)
            }
            .opacity(opacity)
            
            Spacer()
            
            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Text("Start Connecting")
                        .font(.custom("OpenSans-Bold", size: 18))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: gradientColors[0].opacity(0.4), radius: 20, y: 8)
            }
            .padding(.horizontal, 32)
            .opacity(opacity)
        }
        .padding()
        .onAppear {
            // Animate entrance
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                scale = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                opacity = 1.0
            }
            
            // Trigger confetti
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showConfetti = true
                
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

struct SuccessFeatureRow: View {
    let icon: String
    let text: String
    let gradientColors: [Color]
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(gradientColors[0])
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(gradientColors[0].opacity(0.1))
        )
        .padding(.horizontal, 32)
    }
}

// MARK: - Profile Data Model
struct ProfileData {
    var photos: [UIImage] = []
    var gender: String?
    var ageRange: String?
    var location: String?
    var denomination: String?
    var interests: Set<String> = []
    var bio: String?
    var iceBreakerAnswers: [String: String] = [:]
    var isEmailVerified: Bool = false
    var isPhoneVerified: Bool = false
    var conversationStarters: Set<String> = []
    var mentorPreference: MentorPreference?
}

// MARK: - FlowLayout Helper
// FlowLayout is now imported from FlowLayout.swift

#Preview {
    OnboardingSuccessScreen(gradientColors: [.pink, .purple]) {
        print("Complete")
    }
}
