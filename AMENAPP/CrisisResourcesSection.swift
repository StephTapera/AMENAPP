//
//  CrisisResourcesSection.swift
//  AMENAPP
//
//  Created by Steph on 2/2/26.
//

import SwiftUI

// MARK: - Crisis Resources Section
struct CrisisResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Crisis Resources")
                    .font(.custom("OpenSans-Bold", size: 20))
            }
            .padding(.horizontal)
            
            // 988 Suicide & Crisis Lifeline
            CrisisHotlineCard(
                icon: "phone.fill",
                iconColor: .red,
                title: "988 Suicide & Crisis Lifeline",
                subtitle: "24/7 Free & Confidential Support",
                phoneNumber: "988",
                description: "Call or text 988 for free, confidential support anytime.",
                gradientColors: [Color.red, Color.orange]
            )
            
            // Crisis Text Line
            CrisisHotlineCard(
                icon: "message.fill",
                iconColor: .blue,
                title: "Crisis Text Line",
                subtitle: "Text HOME to 741741",
                phoneNumber: "741741",
                description: "Free 24/7 support via text message.",
                gradientColors: [Color.blue, Color.cyan]
            )
            
            // NAMI Helpline
            CrisisResourceCard(
                icon: "brain.head.profile",
                iconColor: .purple,
                title: "NAMI Helpline",
                subtitle: "Mental Health Support & Resources",
                phoneNumber: "1-800-950-6264",
                hours: "Mon-Fri, 10am-10pm ET",
                description: "Information, referrals, and support from trained volunteers."
            )
            
            // SAMHSA National Helpline
            CrisisResourceCard(
                icon: "heart.text.square.fill",
                iconColor: .pink,
                title: "SAMHSA National Helpline",
                subtitle: "Treatment Referral & Information",
                phoneNumber: "1-800-662-4357",
                hours: "24/7 Support",
                description: "Free, confidential treatment referral and information service."
            )
            
            // Emergency Services Reminder
            EmergencyReminderCard()
        }
    }
}

// MARK: - Crisis Hotline Card (Featured Style)
struct CrisisHotlineCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let phoneNumber: String
    let description: String
    let gradientColors: [Color]
    
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [iconColor.opacity(0.6), iconColor.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
            }
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.95))
                .lineSpacing(3)
            
            // Call button
            Button {
                callPhoneNumber(phoneNumber)
            } label: {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 15))
                        Text(phoneNumber.count <= 3 ? "Call \(phoneNumber)" : "Call Now")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                )
            }
        }
        .padding(18)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glass overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
                
                // Shimmer effect
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmerPhase)
                .blur(radius: 25)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: gradientColors[0].opacity(0.3), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
    }
    
    private func callPhoneNumber(_ number: String) {
        let cleanNumber = number.replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel://\(cleanNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Crisis Resource Card (Standard Style)
struct CrisisResourceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let phoneNumber: String
    let hours: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(iconColor)
                    Text(hours)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(iconColor.opacity(0.1))
                )
                
                Spacer()
                
                Button {
                    callPhoneNumber(phoneNumber)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 12))
                        Text("Call")
                            .font(.custom("OpenSans-Bold", size: 13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(iconColor)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
    
    private func callPhoneNumber(_ number: String) {
        let cleanNumber = number.replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel://\(cleanNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Emergency Reminder Card
struct EmergencyReminderCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("In Case of Emergency")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                
                Text("If you or someone else is in immediate danger, call 911")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

#Preview {
    ScrollView {
        CrisisResourcesSection()
    }
}
