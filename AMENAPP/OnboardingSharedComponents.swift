//
//  OnboardingSharedComponents.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI
import PhotosUI

// MARK: - Photo Upload Step
struct PhotoUploadStep: View {
    @Binding var selectedPhotos: [UIImage]
    @State private var photosPickerItems: [PhotosPickerItem] = []
    let maxPhotos: Int = 5
    let gradientColors: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Your Photos")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(gradientColors[0])
                    
                    Text("Add at least 1 photo. Profiles with photos get 5x more connections!")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Photo Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(0..<maxPhotos, id: \.self) { index in
                    if index < selectedPhotos.count {
                        // Display selected photo
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: selectedPhotos[index])
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            
                            // Remove button
                            Button {
                                let indexToRemove = index
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedPhotos.remove(at: indexToRemove)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(.black.opacity(0.5))
                                            .frame(width: 26, height: 26)
                                    )
                            }
                            .padding(8)
                            
                            // Primary badge
                            if index == 0 {
                                VStack {
                                    Spacer()
                                    
                                    Text("Profile Photo")
                                        .font(.custom("OpenSans-Bold", size: 11))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                                        )
                                        .padding(8)
                                }
                            }
                        }
                    } else {
                        // Add photo button
                        PhotosPicker(selection: $photosPickerItems, maxSelectionCount: maxPhotos - selectedPhotos.count, matching: .images) {
                            VStack(spacing: 12) {
                                Image(systemName: index == 0 ? "camera.fill" : "photo.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundStyle(gradientColors[0].opacity(0.5))
                                
                                Text(index == 0 ? "Add Photo" : "Add More")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 160)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                    .foregroundStyle(gradientColors[0].opacity(0.3))
                            )
                        }
                        .onChange(of: photosPickerItems) { oldValue, newValue in
                            Task {
                                for item in newValue {
                                    if let data = try? await item.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        selectedPhotos.append(image)
                                    }
                                }
                                photosPickerItems = []
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Verification Step
struct VerificationStep: View {
    @Binding var phoneNumber: String
    @Binding var email: String
    @Binding var isPhoneVerified: Bool
    @Binding var isEmailVerified: Bool
    let gradientColors: [Color]
    
    @State private var verificationCode = ""
    @State private var showCodeInput = false
    @State private var isVerifying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Verify Your Account")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Help us keep our community safe and authentic")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                // Email Verification
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    HStack {
                        TextField("your.email@example.com", text: $email)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disabled(isEmailVerified)
                        
                        if isEmailVerified {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isEmailVerified ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                    
                    if !isEmailVerified && !email.isEmpty {
                        Button {
                            sendEmailVerification()
                        } label: {
                            Text("Send Verification Code")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(gradientColors[0])
                        }
                    }
                }
                
                // Phone Verification
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone Number (Optional)")
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    HStack {
                        TextField("(555) 123-4567", text: $phoneNumber)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .disabled(isPhoneVerified)
                        
                        if isPhoneVerified {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isPhoneVerified ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                    
                    if !isPhoneVerified && !phoneNumber.isEmpty {
                        Button {
                            sendPhoneVerification()
                        } label: {
                            Text("Send SMS Code")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(gradientColors[0])
                        }
                    }
                }
                
                // Code Input (when verification sent)
                if showCodeInput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verification Code")
                            .font(.custom("OpenSans-Bold", size: 15))
                        
                        HStack(spacing: 12) {
                            TextField("Enter 6-digit code", text: $verificationCode)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .textContentType(.oneTimeCode)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                )
                            
                            Button {
                                verifyCode()
                            } label: {
                                if isVerifying {
                                    ProgressView()
                                        .tint(gradientColors[0])
                                } else {
                                    Text("Verify")
                                        .font(.custom("OpenSans-Bold", size: 14))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(
                                            Capsule()
                                                .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                                        )
                                }
                            }
                            .disabled(verificationCode.count < 6)
                        }
                    }
                }
            }
            
            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Verified badge on your profile")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Increased trust from the community")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Account recovery options")
                        .font(.custom("OpenSans-Regular", size: 14))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(gradientColors[0].opacity(0.05))
            )
            
            Spacer()
        }
    }
    
    private func sendEmailVerification() {
        showCodeInput = true
        // Simulate sending verification
        // In production: call API to send verification email
    }
    
    private func sendPhoneVerification() {
        showCodeInput = true
        // Simulate sending verification
        // In production: call API to send SMS
    }
    
    private func verifyCode() {
        isVerifying = true
        
        // Simulate verification
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isEmailVerified = true
                isPhoneVerified = !phoneNumber.isEmpty
                showCodeInput = false
                isVerifying = false
                
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Location Services Step
struct LocationServicesStep: View {
    @Binding var locationPermissionGranted: Bool
    @Binding var searchRadius: Double
    let gradientColors: [Color]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Enable Location")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Find connections near you")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            // Location illustration
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(gradientColors[0].opacity(0.1))
                    .frame(height: 180)
                
                VStack(spacing: 16) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(gradientColors[0].opacity(0.6))
                    
                    Text("Connect with believers nearby")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                }
            }
            
            if !locationPermissionGranted {
                Button {
                    requestLocationPermission()
                } label: {
                    HStack {
                        Image(systemName: "location.circle.fill")
                        Text("Enable Location Services")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    )
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Location enabled")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.green)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            }
            
            // Search radius slider
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Radius: \(Int(searchRadius)) miles")
                    .font(.custom("OpenSans-Bold", size: 15))
                
                Slider(value: $searchRadius, in: 1...100, step: 1)
                    .tint(gradientColors[0])
                
                HStack {
                    Text("1 mi")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("100 mi")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
            
            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.secondary)
                
                Text("Your exact location is never shared. Only approximate distance is shown.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
            )
            
            Spacer()
        }
    }
    
    private func requestLocationPermission() {
        // Request location permission
        // In production: Use CLLocationManager
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            locationPermissionGranted = true
        }
    }
}

// MARK: - Privacy & Safety Step
struct PrivacySafetyStep: View {
    @Binding var agreedToGuidelines: Bool
    let gradientColors: [Color]
    
    let guidelines = [
        SafetyGuideline(icon: "checkmark.shield.fill", title: "Verified Profiles", description: "We verify all accounts to keep our community authentic"),
        SafetyGuideline(icon: "person.fill.checkmark", title: "Be Authentic", description: "Share genuine thoughts from your heart, not AI-generated content"),
        SafetyGuideline(icon: "eye.slash.fill", title: "Report & Block", description: "Easily report inappropriate behavior or block users"),
        SafetyGuideline(icon: "lock.fill", title: "Private Messaging", description: "Your conversations are private and secure"),
        SafetyGuideline(icon: "person.badge.shield.checkmark.fill", title: "Meet Safely", description: "Always meet in public places for first meetings"),
        SafetyGuideline(icon: "hand.raised.fill", title: "Trust Your Instincts", description: "If something feels off, report it immediately"),
        SafetyGuideline(icon: "heart.fill", title: "Honor God", description: "Treat others with respect and Christ-like love")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 28))
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Safety First")
                        .font(.custom("OpenSans-Bold", size: 24))
                }
                
                Text("Your safety is our top priority")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(guidelines) { guideline in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: guideline.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(gradientColors[0])
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(guideline.title)
                                    .font(.custom("OpenSans-Bold", size: 15))
                                
                                Text(guideline.description)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.05))
                        )
                    }
                }
            }
            .frame(maxHeight: 400)
            
            // Agreement checkbox
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    agreedToGuidelines.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: agreedToGuidelines ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundStyle(agreedToGuidelines ? gradientColors[0] : .secondary)
                    
                    Text("I agree to follow these safety guidelines and community standards")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(agreedToGuidelines ? gradientColors[0] : Color.gray.opacity(0.3), lineWidth: 2)
            )
        }
    }
}

struct SafetyGuideline: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// MARK: - Ice Breaker Questions Step
struct IceBreakerQuestionsStep: View {
    @Binding var answers: [String: String]
    let gradientColors: [Color]
    
    let questions = [
        IceBreakerQuestion(id: "verse", question: "What's your favorite Bible verse?", placeholder: "e.g., Philippians 4:13"),
        IceBreakerQuestion(id: "worship", question: "Favorite worship song?", placeholder: "e.g., Way Maker by Sinach"),
        IceBreakerQuestion(id: "hobby", question: "How do you spend your free time?", placeholder: "e.g., Hiking, reading, serving..."),
        IceBreakerQuestion(id: "fun_fact", question: "A fun fact about you?", placeholder: "Share something unique!")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ice Breaker Questions")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(gradientColors[0])
                    
                    Text("Help others start conversations with you")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(questions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.question)
                                .font(.custom("OpenSans-Bold", size: 15))
                            
                            TextField(question.placeholder, text: Binding(
                                get: { answers[question.id] ?? "" },
                                set: { answers[question.id] = $0 }
                            ))
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                            )
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct IceBreakerQuestion: Identifiable {
    let id: String
    let question: String
    let placeholder: String
}

#Preview {
    PhotoUploadStep(selectedPhotos: .constant([]), gradientColors: [.pink, .purple])
}
