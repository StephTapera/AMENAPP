//
//  CommunityCovenantView.swift
//  AMENAPP
//
//  Safe Space Authentication Layer
//  Community standards agreement for faith-based platform
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CommunityCovenantView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAgreed = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    let onComplete: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.pink)
                        
                        Text("Community Covenant")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundColor(.primary)
                        
                        Text("Welcome to AMEN! Before you join our community, please read and agree to these standards.")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Covenant Principles
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Our Commitment")
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundColor(.primary)
                        
                        Text("AMEN is a faith-based community built on love, respect, and authenticity. By joining, I commit to:")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                        
                        covenantPrinciple(
                            icon: "heart.fill",
                            color: .pink,
                            title: "Love & Respect",
                            description: "I will treat others with Christ-like love and respect, even when we disagree."
                        )
                        
                        covenantPrinciple(
                            icon: "checkmark.shield.fill",
                            color: .blue,
                            title: "Truth & Grace",
                            description: "I will speak truth in love, avoiding gossip, slander, and false information."
                        )
                        
                        covenantPrinciple(
                            icon: "hands.sparkles.fill",
                            color: .purple,
                            title: "Encouragement",
                            description: "I will build others up, not tear them down. I will celebrate victories and support struggles."
                        )
                        
                        covenantPrinciple(
                            icon: "shield.lefthalf.filled",
                            color: .green,
                            title: "Safe Space",
                            description: "I will help maintain a safe environment free from harassment, bullying, and hate speech."
                        )
                        
                        covenantPrinciple(
                            icon: "book.fill",
                            color: .orange,
                            title: "Biblical Integrity",
                            description: "I will honor God's Word and not misrepresent Scripture or promote false teachings."
                        )
                        
                        covenantPrinciple(
                            icon: "person.3.fill",
                            color: .red,
                            title: "Community First",
                            description: "I will report harmful content and trust the moderation team to keep our community safe."
                        )
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // What's Not Allowed
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What's Not Allowed")
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundColor(.primary)
                        
                        Text("To keep AMEN safe and welcoming, we don't allow:")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                        
                        notAllowedItem("Hate speech, bullying, or harassment")
                        notAllowedItem("Sexual content or inappropriate material")
                        notAllowedItem("Violence, threats, or dangerous activities")
                        notAllowedItem("Spam, scams, or misleading information")
                        notAllowedItem("False teachings or misrepresenting the Gospel")
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Re-affirmation Note
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Periodic Re-affirmation")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundColor(.primary)
                        }
                        
                        Text("We'll ask you to re-affirm these standards every 90 days to keep our community values top of mind.")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.08))
                    )
                    
                    // Agreement Checkbox
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hasAgreed.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 24))
                                .foregroundColor(hasAgreed ? .green : .gray)
                            
                            Text("I have read and agree to uphold these community standards")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(hasAgreed ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(hasAgreed ? Color.green : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // Continue Button
                Button {
                    submitAgreement()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text("Continue to AMEN")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hasAgreed ? Color.pink : Color.gray)
                )
                .disabled(!hasAgreed || isSubmitting)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .interactiveDismissDisabled()
    }
    
    private func covenantPrinciple(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
        }
    }
    
    private func notAllowedItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)
            
            Text(text)
                .font(.custom("OpenSans-Medium", size: 15))
                .foregroundColor(.primary)
        }
    }
    
    private func submitAgreement() {
        guard hasAgreed else { return }
        
        isSubmitting = true
        
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                let db = Firestore.firestore()
                
                // Save agreement to Firestore
                try await db.collection("users").document(userId)
                    .collection("communityStandards").document("agreement").setData([
                        "agreedAt": FieldValue.serverTimestamp(),
                        "version": "1.0",
                        "nextReaffirmation": Calendar.current.date(byAdding: .day, value: 90, to: Date())!
                    ])
                
                // Mark in user profile
                try await db.collection("users").document(userId).updateData([
                    "hasAgreedToCommunityStandards": true,
                    "communityStandardsAgreedAt": FieldValue.serverTimestamp()
                ])
                
                print("✅ Community Covenant agreement saved")
                
                await MainActor.run {
                    isSubmitting = false
                    onComplete()
                }
                
            } catch {
                print("❌ Failed to save agreement: \(error)")
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to save agreement. Please try again."
                    showError = true
                }
            }
        }
    }
}
