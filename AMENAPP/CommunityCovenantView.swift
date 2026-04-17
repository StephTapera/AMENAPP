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
                    VStack(spacing: 16) {
                        AmenOnboardingHeroIcon(
                            systemName: "heart.text.square.fill",
                            size: 88,
                            accent: ONB.accent
                        )

                        Text("Community Covenant")
                            .font(AMENFont.bold(28))
                            .foregroundColor(ONB.inkPrimary)

                        Text("Welcome to AMEN! Before you join our community, please read and agree to these standards.")
                            .font(AMENFont.regular(16))
                            .foregroundColor(ONB.inkSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    Rectangle()
                        .fill(ONB.glassBorder)
                        .frame(height: 0.5)
                        .padding(.vertical, 8)
                    
                    // Covenant Principles
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Our Commitment")
                            .font(AMENFont.bold(22))
                            .foregroundColor(ONB.inkPrimary)

                        Text("AMEN is a faith-based community built on love, respect, and authenticity. By joining, I commit to:")
                            .font(AMENFont.regular(15))
                            .foregroundColor(ONB.inkSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 8) {
                            AmenOnboardingInfoRow(
                                icon: "heart.fill",
                                title: "Love & Respect",
                                subtitle: "I will treat others with Christ-like love and respect, even when we disagree.",
                                accent: ONB.accent
                            )
                            AmenOnboardingInfoRow(
                                icon: "checkmark.shield.fill",
                                title: "Truth & Grace",
                                subtitle: "I will speak truth in love, avoiding gossip, slander, and false information.",
                                accent: ONB.accent
                            )
                            AmenOnboardingInfoRow(
                                icon: "hands.sparkles.fill",
                                title: "Encouragement",
                                subtitle: "I will build others up, not tear them down. I will celebrate victories and support struggles.",
                                accent: ONB.accent
                            )
                            AmenOnboardingInfoRow(
                                icon: "shield.lefthalf.filled",
                                title: "Safe Space",
                                subtitle: "I will help maintain a safe environment free from harassment, bullying, and hate speech.",
                                accent: ONB.accent
                            )
                            AmenOnboardingInfoRow(
                                icon: "book.fill",
                                title: "Biblical Integrity",
                                subtitle: "I will honor God's Word and not misrepresent Scripture or promote false teachings.",
                                accent: ONB.accentGold
                            )
                            AmenOnboardingInfoRow(
                                icon: "person.3.fill",
                                title: "Community First",
                                subtitle: "I will report harmful content and trust the moderation team to keep our community safe.",
                                accent: ONB.accent
                            )
                        }
                    }

                    Rectangle()
                        .fill(ONB.glassBorder)
                        .frame(height: 0.5)
                        .padding(.vertical, 8)
                    
                    // What's Not Allowed
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What's Not Allowed")
                            .font(AMENFont.bold(22))
                            .foregroundColor(ONB.inkPrimary)

                        Text("To keep AMEN safe and welcoming, we don't allow:")
                            .font(AMENFont.regular(15))
                            .foregroundColor(ONB.inkSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 8) {
                            notAllowedItem("Hate speech, bullying, or harassment")
                            notAllowedItem("Sexual content or inappropriate material")
                            notAllowedItem("Violence, threats, or dangerous activities")
                            notAllowedItem("Spam, scams, or misleading information")
                            notAllowedItem("False teachings or misrepresenting the Gospel")
                        }
                    }

                    Rectangle()
                        .fill(ONB.glassBorder)
                        .frame(height: 0.5)
                        .padding(.vertical, 8)
                    
                    // Re-affirmation Note
                    ONBGlassCard(padding: .init(top: 14, leading: 16, bottom: 14, trailing: 16), cornerRadius: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(ONB.accent)
                                Text("Periodic Re-affirmation")
                                    .font(AMENFont.bold(16))
                                    .foregroundColor(ONB.inkPrimary)
                            }

                            Text("We'll ask you to re-affirm these standards every 90 days to keep our community values top of mind.")
                                .font(AMENFont.regular(14))
                                .foregroundColor(ONB.inkSecondary)
                                .lineSpacing(4)
                        }
                    }
                    
                    // Agreement Checkbox
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            hasAgreed.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                                .font(.systemScaled(24))
                                .foregroundColor(hasAgreed ? ONB.accent : ONB.inkTertiary)

                            Text("I have read and agree to uphold these community standards")
                                .font(AMENFont.semiBold(15))
                                .foregroundColor(ONB.inkPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            hasAgreed ? ONB.accent.opacity(0.55) : ONB.glassBorder,
                                            lineWidth: hasAgreed ? 1.5 : 1
                                        )
                                )
                        )
                        .shadow(color: ONB.glassShadow, radius: 6, y: 2)
                        .scaleEffect(hasAgreed ? 1.0 : 0.995)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 120) // Space for bottom button
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 30)
                    
                    ONBPrimaryButton(
                        title: "I Agree, Continue",
                        isLoading: isSubmitting,
                        trailingIcon: "arrow.right",
                        action: {
                        if !hasAgreed {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                hasAgreed = true
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            // Wait for animation to complete before submitting
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                submitAgreement()
                            }
                        } else {
                            submitAgreement()
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: -4)
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .interactiveDismissDisabled()
    }
    
    private func notAllowedItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.systemScaled(16))
                .foregroundColor(.red)

            Text(text)
                .font(AMENFont.medium(15))
                .foregroundColor(ONB.inkPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ONB.glassBorder, lineWidth: 0.75))
        )
        .shadow(color: ONB.glassShadow, radius: 4, y: 1)
    }
    
    private func submitAgreement() {
        guard hasAgreed else { return }
        
        isSubmitting = true
        
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                lazy var db = Firestore.firestore()
                
                // Save agreement to Firestore
                try await db.collection("users").document(userId)
                    .collection("communityStandards").document("agreement").setData([
                        "agreedAt": FieldValue.serverTimestamp(),
                        "version": "1.0",
                        "nextReaffirmation": Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date(timeIntervalSinceNow: 90 * 86400)
                    ])
                
                // Mark in user profile
                try await db.collection("users").document(userId).updateData([
                    "hasAgreedToCommunityStandards": true,
                    "communityStandardsAgreedAt": FieldValue.serverTimestamp()
                ])
                
                dlog("✅ Community Covenant agreement saved")
                
                await MainActor.run {
                    isSubmitting = false
                    onComplete()
                }
                
            } catch {
                dlog("❌ Failed to save agreement: \(error)")
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to save agreement. Please try again."
                    showError = true
                }
            }
        }
    }
}
