//
//  CrisisResourcesDetailView.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

struct CrisisResourcesDetailView: View {
    @State private var selectedHotline: CrisisHotline?
    @State private var showCallConfirmation = false
    @State private var showTextConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.15))
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, options: .repeating.speed(0.8))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Crisis Resources")
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.primary)
                            
                            Text("Help is available 24/7")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("If you or someone you know is in crisis, please reach out. You're not alone, and help is always available.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Emergency Notice
                emergencyNotice
                
                // National Hotlines
                VStack(alignment: .leading, spacing: 16) {
                    Text("National Hotlines")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        ForEach(CrisisHotline.nationalHotlines) { hotline in
                            HotlineCard(hotline: hotline) {
                                selectedHotline = hotline
                                if hotline.textNumber != nil {
                                    showTextConfirmation = true
                                } else {
                                    showCallConfirmation = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Faith-Based Resources
                VStack(alignment: .leading, spacing: 16) {
                    Text("Faith-Based Support")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        ForEach(CrisisHotline.faithBasedResources) { hotline in
                            HotlineCard(hotline: hotline) {
                                selectedHotline = hotline
                                showCallConfirmation = true
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Online Resources
                VStack(alignment: .leading, spacing: 16) {
                    Text("Online Resources")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        ForEach(OnlineResource.crisisResources) { resource in
                            OnlineResourceCard(resource: resource)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Safety Tips
                safetyTipsSection
                
                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .navigationTitle("Crisis Resources")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Call \(selectedHotline?.name ?? "Hotline")?", isPresented: $showCallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Call Now") {
                if let phoneNumber = selectedHotline?.phoneNumber {
                    callPhoneNumber(phoneNumber)
                }
            }
        } message: {
            Text(selectedHotline?.description ?? "")
        }
        .alert("Text \(selectedHotline?.name ?? "Hotline")?", isPresented: $showTextConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Open Messages") {
                if let textNumber = selectedHotline?.textNumber {
                    openTextMessages(textNumber)
                }
            }
        } message: {
            Text(selectedHotline?.textInstructions ?? "")
        }
    }
    
    private var emergencyNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                
                Text("If you're in immediate danger")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
            }
            
            Text("Call 911 or go to your nearest emergency room immediately.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
            
            Button {
                callPhoneNumber("911")
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Call 911")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.red.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
    
    private var safetyTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Safety & Support Tips")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                SafetyTipRow(
                    icon: "person.2.fill",
                    title: "Talk to someone you trust",
                    description: "Share your feelings with a trusted friend or family member"
                )
                
                SafetyTipRow(
                    icon: "heart.fill",
                    title: "Take care of yourself",
                    description: "Focus on self-care activities that bring you peace"
                )
                
                SafetyTipRow(
                    icon: "book.fill",
                    title: "Turn to scripture",
                    description: "Find comfort in God's word and prayer"
                )
                
                SafetyTipRow(
                    icon: "building.columns.fill",
                    title: "Seek professional help",
                    description: "Consider therapy or counseling for ongoing support"
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
    }
    
    private func callPhoneNumber(_ number: String) {
        let cleanNumber = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let url = URL(string: "tel://\(cleanNumber)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openTextMessages(_ number: String) {
        let cleanNumber = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let url = URL(string: "sms:\(cleanNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Hotline Card

struct HotlineCard: View {
    let hotline: CrisisHotline
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(hotline.color.opacity(0.15))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: hotline.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(hotline.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hotline.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        if hotline.available247 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                
                                Text("Available 24/7")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(hotline.color)
                }
                
                Text(hotline.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                
                HStack(spacing: 12) {
                    if let phoneNumber = hotline.phoneNumber {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12))
                            Text(phoneNumber)
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(hotline.color)
                    }
                    
                    if let textNumber = hotline.textNumber {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 12))
                            Text("Text: \(textNumber)")
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(hotline.color)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Online Resource Card

struct OnlineResourceCard: View {
    let resource: OnlineResource
    
    var body: some View {
        Button {
            if let url = URL(string: resource.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(resource.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: resource.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(resource.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(resource.name)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(resource.description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(resource.color)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Safety Tip Row

struct SafetyTipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}

// MARK: - Data Models

struct CrisisHotline: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let phoneNumber: String?
    let textNumber: String?
    let textInstructions: String?
    let icon: String
    let color: Color
    let available247: Bool
    
    static let nationalHotlines = [
        CrisisHotline(
            name: "988 Suicide & Crisis Lifeline",
            description: "Free, confidential support for people in distress, prevention and crisis resources.",
            phoneNumber: "988",
            textNumber: "988",
            textInstructions: "Text 988 to connect with a crisis counselor.",
            icon: "phone.fill",
            color: .red,
            available247: true
        ),
        CrisisHotline(
            name: "Crisis Text Line",
            description: "Text-based crisis support. Text HOME to 741741 to connect with a crisis counselor.",
            phoneNumber: nil,
            textNumber: "741741",
            textInstructions: "Text HOME to 741741 from anywhere in the US to reach a crisis counselor.",
            icon: "message.fill",
            color: .orange,
            available247: true
        ),
        CrisisHotline(
            name: "SAMHSA National Helpline",
            description: "Treatment referral and information service for mental health and substance use disorders.",
            phoneNumber: "1-800-662-4357",
            textNumber: nil,
            textInstructions: nil,
            icon: "heart.circle.fill",
            color: .purple,
            available247: true
        ),
        CrisisHotline(
            name: "Veterans Crisis Line",
            description: "Confidential support for veterans, service members, and their families.",
            phoneNumber: "988",
            textNumber: "838255",
            textInstructions: "Text 838255 or press 1 after calling 988.",
            icon: "star.fill",
            color: .blue,
            available247: true
        ),
        CrisisHotline(
            name: "Domestic Violence Hotline",
            description: "Support for victims of domestic violence and abuse.",
            phoneNumber: "1-800-799-7233",
            textNumber: "88788",
            textInstructions: "Text START to 88788 for support.",
            icon: "shield.fill",
            color: .pink,
            available247: true
        )
    ]
    
    static let faithBasedResources = [
        CrisisHotline(
            name: "Christian Crisis Hotline",
            description: "Faith-based crisis counseling and prayer support.",
            phoneNumber: "1-855-382-5433",
            textNumber: nil,
            textInstructions: nil,
            icon: "cross.fill",
            color: .blue,
            available247: true
        ),
        CrisisHotline(
            name: "Focus on the Family",
            description: "Christian counseling and family support services.",
            phoneNumber: "1-855-771-4357",
            textNumber: nil,
            textInstructions: nil,
            icon: "person.3.fill",
            color: .green,
            available247: false
        )
    ]
}

struct OnlineResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let color: Color
    
    static let crisisResources = [
        OnlineResource(
            name: "MentalHealth.gov",
            description: "Comprehensive mental health information and resources",
            url: "https://www.mentalhealth.gov",
            icon: "brain.head.profile",
            color: .blue
        ),
        OnlineResource(
            name: "NAMI Support",
            description: "National Alliance on Mental Illness resources and support groups",
            url: "https://www.nami.org",
            icon: "person.2.fill",
            color: .purple
        ),
        OnlineResource(
            name: "Psychology Today",
            description: "Find therapists and counselors in your area",
            url: "https://www.psychologytoday.com/us/therapists",
            icon: "magnifyingglass",
            color: .green
        ),
        OnlineResource(
            name: "IMAlive Crisis Chat",
            description: "Free online crisis chat service",
            url: "https://www.imalive.org",
            icon: "bubble.left.and.bubble.right.fill",
            color: .orange
        )
    ]
}

#Preview {
    NavigationStack {
        CrisisResourcesDetailView()
    }
}
