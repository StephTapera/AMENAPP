//
//  AI_PREMIUM_INTEGRATION_CODE.swift
//  Code snippets to add to AIBibleStudyView.swift
//

// MARK: - 1. Add at top of AIBibleStudyView struct

@StateObject private var premiumManager = PremiumManager.shared

// MARK: - 2. Replace hasProAccess variable

// ❌ REMOVE THIS:
@State private var hasProAccess = false

// ✅ REPLACE WITH THIS COMPUTED PROPERTY:
var hasProAccess: Bool {
    premiumManager.hasProAccess
}

// MARK: - 3. Add Usage Indicator to Header

// Add this after the header view, before tabs
if !premiumManager.hasProAccess {
    UsageLimitBanner(
        messagesRemaining: premiumManager.freeMessagesRemaining,
        totalMessages: premiumManager.FREE_MESSAGES_PER_DAY,
        onUpgrade: { showProUpgrade = true }
    )
    .transition(.move(edge: .top).combined(with: .opacity))
}

// MARK: - 4. Update sendMessage() with Usage Check

private func sendMessage() {
    guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    // ✅ ADD THIS: Check if user can send message
    guard premiumManager.canSendMessage() else {
        // Show paywall when limit reached
        HapticManager.notification(type: .warning)
        showProUpgrade = true
        return
    }

    HapticManager.selection()

    let messageText = userInput
    userInput = ""
    isInputFocused = false

    // Add user message
    let userMessage = AIStudyMessage(text: messageText, isUser: true)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        messages.append(userMessage)
    }

    // ✅ ADD THIS: Increment message count
    premiumManager.incrementMessageCount()

    // Start processing AI response
    isProcessing = true

    // Rest of your existing code...
}

// MARK: - 5. Update Pro Sheet

// ❌ REMOVE OLD SHEET:
.sheet(isPresented: $showProUpgrade) {
    ProUpgradeSheet(hasProAccess: $hasProAccess)
}

// ✅ REPLACE WITH NEW SHEET:
.sheet(isPresented: $showProUpgrade) {
    PremiumUpgradeView()
}

// MARK: - 6. Add Usage Limit Banner Component

struct UsageLimitBanner: View {
    let messagesRemaining: Int
    let totalMessages: Int
    let onUpgrade: () -> Void

    var progressPercent: Double {
        let used = Double(totalMessages - messagesRemaining)
        return used / Double(totalMessages)
    }

    var statusColor: Color {
        if messagesRemaining > 5 {
            return .green
        } else if messagesRemaining > 2 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: "message.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(statusColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(messagesRemaining) free messages left today")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)

                    Text("Reset tomorrow • Upgrade for unlimited")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // Upgrade button
                Button(action: onUpgrade) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))

                        Text("Upgrade")
                            .font(.custom("OpenSans-Bold", size: 13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.4, blue: 0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)

                    // Progress
                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geometry.size.width * progressPercent, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
        }
        .background(
            Rectangle()
                .fill(.black.opacity(0.4))
                .background(.ultraThinMaterial.opacity(0.3))
        )
    }
}

// MARK: - 7. Add onAppear to Load Premium Status

.onAppear {
    // Existing onAppear code...

    // ✅ ADD THIS: Check premium status on appear
    Task {
        await premiumManager.checkSubscriptionStatus()
    }
}

// MARK: - 8. Optional: Add Premium Badge to Pro Users

// In headerView, add this badge for premium users:
if premiumManager.hasProAccess {
    HStack(spacing: 6) {
        Image(systemName: "sparkles")
            .font(.system(size: 14))
            .symbolEffect(.variableColor.iterative, options: .repeating)

        Text("PRO")
            .font(.custom("OpenSans-Bold", size: 13))
    }
    .foregroundStyle(
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
    )
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
        Capsule()
            .fill(Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.2))
    )
    .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3), radius: 8, y: 2)
}

// MARK: - Complete Integration Summary

/*

INTEGRATION STEPS:

1. ✅ Add PremiumManager.swift to project
2. ✅ Add PremiumUpgradeView.swift to project
3. ✅ Add @StateObject private var premiumManager in AIBibleStudyView
4. ✅ Replace @State hasProAccess with computed property
5. ✅ Add UsageLimitBanner after header
6. ✅ Add usage check in sendMessage()
7. ✅ Replace ProUpgradeSheet with PremiumUpgradeView
8. ✅ Add premium status check in onAppear

BUILD STATUS: Ready to test!

NEXT STEPS:
- Set up products in App Store Connect
- Test with sandbox account
- Add to files in Xcode
- Build and test

*/
