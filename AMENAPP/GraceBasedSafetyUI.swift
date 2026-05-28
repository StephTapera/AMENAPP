//
//  GraceBasedSafetyUI.swift
//  AMENAPP
//
//  Created by Claude on 3/29/26.
//  Grace-based safety explanations with scripture grounding
//

import SwiftUI

// MARK: - Safety Message Models

struct SafetyMessageExplanation {
    let decision: String
    let reason: String
    let scriptureReference: String?
    let scriptureText: String?
    let actionRequired: String?
    let estimatedReviewTime: String?
}

// MARK: - Blocked Message View

struct BlockedMessageExplanationView: View {
    let reason: String
    let scriptureRef: String?
    let onUnderstand: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "hand.raised.fill")
                    .font(.systemScaled(36))
                    .foregroundStyle(Color.orange)
            }
            
            // Title
            Text("Message Not Sent")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)
            
            // Grace-based explanation
            Text(reason)
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Scripture grounding
            if let ref = scriptureRef {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 40)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                        
                        Text(ref)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(scriptureText(for: ref))
                        .font(.systemScaled(14, design: .serif))
                        .foregroundStyle(.primary)
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 20)
            }
            
            // Action button
            AmenLiquidGlassPillButton(
                title: "I Understand",
                systemImage: "checkmark",
                isLoading: false,
                isDisabled: false,
                action: { onUnderstand() }
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.vertical, 32)
    }
    
    private func scriptureText(for reference: String) -> String {
        // Map scripture references to actual text
        let scriptures: [String: String] = [
            "Ephesians 4:29": "Let no corrupting talk come out of your mouths, but only such as is good for building up, as fits the occasion, that it may give grace to those who hear.",
            "Colossians 3:8": "But now you must put them all away: anger, wrath, malice, slander, and obscene talk from your mouth.",
            "Proverbs 15:1": "A soft answer turns away wrath, but a harsh word stirs up anger.",
            "Proverbs 16:24": "Gracious words are like a honeycomb, sweetness to the soul and health to the body.",
            "James 3:10": "From the same mouth come blessing and cursing. My brothers, these things ought not to be so.",
            "Matthew 5:37": "Let what you say be simply 'Yes' or 'No'; anything more than this comes from evil."
        ]
        
        return scriptures[reference] ?? "Let your speech always be gracious, seasoned with salt."
    }
}

// MARK: - Held for Review View

struct HeldForReviewView: View {
    let reason: String
    let estimatedTime: String
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.systemScaled(36))
                    .foregroundStyle(Color.blue)
            }
            
            // Title
            Text("Message Under Review")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)
            
            // Explanation
            VStack(spacing: 12) {
                Text("We're reviewing this message to ensure it aligns with our community standards.")
                    .font(.systemScaled(16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                // Time estimate
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)
                    
                    Text("Usually takes \(estimatedTime)")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(.systemGray6))
                )
            }
            
            // Grace-based reassurance
            VStack(spacing: 8) {
                Text("Our Goal")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text("We want everyone to feel safe and respected. If your message is approved, it will be delivered automatically.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)
            
            // Action button
            AmenLiquidGlassPillButton(
                title: "Got It",
                systemImage: "checkmark",
                isLoading: false,
                isDisabled: false,
                action: { onCancel() }
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Warning Delivered View

struct WarningDeliveredView: View {
    let warningType: String
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.2), Color.yellow.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.systemScaled(36))
                    .foregroundStyle(Color.yellow)
            }
            
            // Title
            Text("Message Delivered with Caution")
                .font(.systemScaled(22, weight: .bold))
                .foregroundStyle(.primary)
            
            // Explanation
            Text("Your message was sent, but the recipient will see a gentle reminder to proceed with care.")
                .font(.systemScaled(16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Grace principle
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(.pink)
                    
                    Text("Moving Forward with Grace")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                Text("Consider reviewing your message and continuing the conversation in a way that honors both you and the recipient.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)
            
            // Action button
            AmenLiquidGlassPillButton(
                title: "Continue",
                systemImage: "arrow.forward",
                isLoading: false,
                isDisabled: false,
                action: { onContinue() }
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Safety Strike Notice (In-Chat Banner)

struct SafetyStrikeBanner: View {
    let strikeCount: Int
    let reason: String
    let onLearnMore: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: strikeCount >= 3 ? "exclamationmark.octagon.fill" : "info.circle.fill")
                .font(.systemScaled(20))
                .foregroundStyle(strikeCount >= 3 ? .red : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Community Standard Notice")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(reason)
                    .font(.systemScaled(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button {
                onLearnMore()
            } label: {
                Text("Learn More")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strikeCount >= 3 ? Color.red.opacity(0.5) : Color.orange.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Safety Education Sheet

struct SafetyEducationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let violation: String
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "book.pages.fill")
                            .font(.systemScaled(48))
                            .foregroundStyle(.blue)
                        
                        Text("Community Standards")
                            .font(.systemScaled(26, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("Building a safe and respectful community together")
                            .font(.systemScaled(15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Specific violation explanation
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What Happened")
                            .font(.systemScaled(18, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text(violationExplanation(for: violation))
                            .font(.systemScaled(15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal, 20)
                    
                    // Grace-based guidance
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Moving Forward")
                            .font(.systemScaled(18, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("We believe in restoration and growth. Here's how you can continue building meaningful connections:")
                            .font(.systemScaled(15))
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            guidanceBullet(
                                icon: "checkmark.circle.fill",
                                text: "Speak words that build up, not tear down"
                            )
                            guidanceBullet(
                                icon: "checkmark.circle.fill",
                                text: "Respect boundaries and consent"
                            )
                            guidanceBullet(
                                icon: "checkmark.circle.fill",
                                text: "Assume the best intent in others"
                            )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func guidanceBullet(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(16))
                .foregroundStyle(.green)
            
            Text(text)
                .font(.systemScaled(15))
                .foregroundStyle(.primary)
        }
    }
    
    private func violationExplanation(for violation: String) -> String {
        switch violation {
        case "harassment":
            return "Your message contained language that could make someone feel unsafe or unwelcome. We want everyone to feel respected on AMEN."
        case "sexual_content":
            return "Your message contained inappropriate or sexual content. AMEN is a space for meaningful connections built on mutual respect."
        case "spiritual_abuse":
            return "Your message used spiritual language in a manipulative way. Faith should never be weaponized to control or pressure others."
        case "scam":
            return "Your message contained patterns associated with financial scams. We protect our community from exploitation."
        default:
            return "Your message didn't align with our community standards. We're here to help you understand how to communicate in a way that honors everyone."
        }
    }
}
