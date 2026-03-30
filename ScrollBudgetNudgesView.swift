//
//  ScrollBudgetNudgesView.swift
//  AMENAPP
//
//  Supportive nudges and redirects for scroll budget enforcement
//

import SwiftUI

// MARK: - 50% Usage Banner

struct ScrollBudget50Banner: View {
    @ObservedObject private var budgetManager = ScrollBudgetManager.shared
    @State private var showBanner = false
    
    var body: some View {
        VStack(spacing: 0) {
            if showBanner {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                    
                    Text("You've used \(Int(budgetManager.todayScrollMinutes)) of \(budgetManager.dailyBudgetMinutes) minutes today")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            showBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollBudget50Reached)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showBanner = true
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    showBanner = false
                }
            }
        }
    }
}

// MARK: - 80% Usage Suggestion

struct ScrollBudget80Suggestion: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "hourglass.tophalf.filled")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            // Title
            Text("Almost at Your Limit")
                .font(.custom("OpenSans-Bold", size: 24))
            
            // Message
            Text("You've used 80% of your daily feed time. Consider switching to a calmer space?")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer().frame(height: 20)
            
            // Suggestions
            VStack(spacing: 12) {
                SuggestionButton(
                    icon: "moon.stars",
                    title: "Enter Quiet Mode",
                    subtitle: "Take a mindful break"
                ) {
                    // Switch to quiet mode (if implemented)
                    dismiss()
                }
                
                SuggestionButton(
                    icon: "note.text",
                    title: "Church Notes",
                    subtitle: "Review recent teachings"
                ) {
                    NotificationCenter.default.post(name: .navigateToChurchNotes, object: nil)
                    dismiss()
                }
            }
            .padding(.horizontal, 24)
            
            // Continue button
            Button {
                dismiss()
            } label: {
                Text("Continue Scrolling")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 12)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Soft Stop Extension Request

struct ScrollBudgetSoftStopView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var budgetManager = ScrollBudgetManager.shared
    let extensionsRemaining: Int
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            // Title
            Text("Daily Budget Reached")
                .font(.custom("OpenSans-Bold", size: 24))
            
            // Message
            Text("You've reached your \(budgetManager.dailyBudgetMinutes)-minute daily limit. Would you like 5 more minutes?")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Extensions remaining
            Text("\(extensionsRemaining) extension\(extensionsRemaining == 1 ? "" : "s") remaining today")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.orange)
            
            Spacer().frame(height: 20)
            
            // Extension button
            Button {
                if budgetManager.requestExtension() {
                    HapticManager.impact(style: .light)
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "clock")
                    Text("Continue for 5 Minutes")
                }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
            }
            .padding(.horizontal, 24)
            
            // Or take a break
            VStack(spacing: 12) {
                Text("Or take a meaningful break:")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    RedirectChip(
                        icon: "hands.sparkles",
                        title: "Prayer"
                    ) {
                        NotificationCenter.default.post(
                            name: Notification.Name("navigateToPrayer"),
                            object: nil
                        )
                        dismiss()
                    }
                    
                    RedirectChip(
                        icon: "book.closed",
                        title: "Read"
                    ) {
                        NotificationCenter.default.post(
                            name: Notification.Name("navigateToBible"),
                            object: nil
                        )
                        dismiss()
                    }
                    
                    RedirectChip(
                        icon: "note.text",
                        title: "Notes"
                    ) {
                        NotificationCenter.default.post(name: .navigateToChurchNotes, object: nil)
                        dismiss()
                    }
                }
            }
            .padding(.top, 12)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Feed Locked View

struct ScrollBudgetLockedView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var budgetManager = ScrollBudgetManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Lock icon with glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(0.15),
                                Color.red.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
            }
            
            // Title
            Text("Feed Locked Until Tomorrow")
                .font(.custom("OpenSans-Bold", size: 24))
                .multilineTextAlignment(.center)
            
            // Message
            Text("You've reached your daily feed budget. Take this time to rest and reflect.")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer().frame(height: 20)
            
            // Available features
            VStack(alignment: .leading, spacing: 16) {
                Text("Still Available")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.secondary)
                
                ScrollBudgetFeatureButton(
                    icon: "hands.sparkles",
                    title: "Prayer Requests",
                    subtitle: "Share and pray with the community"
                ) {
                    NotificationCenter.default.post(
                        name: Notification.Name("navigateToPrayer"),
                        object: nil
                    )
                    dismiss()
                }
                
                ScrollBudgetFeatureButton(
                    icon: "message",
                    title: "Messages",
                    subtitle: "Continue conversations"
                ) {
                    NotificationCenter.default.post(
                        name: Notification.Name("navigateToMessages"),
                        object: nil
                    )
                    dismiss()
                }
                
                ScrollBudgetFeatureButton(
                    icon: "book.closed",
                    title: "Bible Study",
                    subtitle: "Study Scripture with Berean AI"
                ) {
                    NotificationCenter.default.post(
                        name: Notification.Name("navigateToBible"),
                        object: nil
                    )
                    dismiss()
                }
                
                ScrollBudgetFeatureButton(
                    icon: "note.text",
                    title: "Church Notes",
                    subtitle: "Review your notes"
                ) {
                    NotificationCenter.default.post(name: .navigateToChurchNotes, object: nil)
                    dismiss()
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Compulsive Reopen Redirect

struct CompulsiveReopenRedirectView: View {
    @Environment(\.dismiss) var dismiss
    let reopenCount: Int
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Gentle hand icon
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            
            // Title
            Text("Let's Pause for a Moment")
                .font(.custom("OpenSans-Bold", size: 24))
            
            // Message
            Text("You've opened the app \(reopenCount) times in the last few minutes. Would you like to redirect this energy?")
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer().frame(height: 20)
            
            // Supportive redirects
            VStack(spacing: 12) {
                ForEach([
                    ScrollBudgetManager.RedirectOption.prayer,
                    .privateNote,
                    .psalm
                ], id: \.self) { option in
                    RedirectOptionButton(option: option) {
                        handleRedirect(option)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
    
    private func handleRedirect(_ option: ScrollBudgetManager.RedirectOption) {
        switch option {
        case .prayer:
            NotificationCenter.default.post(name: Notification.Name("navigateToPrayer"), object: nil)
        case .privateNote:
            // Navigate to private notes (if implemented)
            break
        case .psalm:
            NotificationCenter.default.post(name: Notification.Name("navigateToBible"), object: nil)
        case .churchNotes:
            NotificationCenter.default.post(name: .navigateToChurchNotes, object: nil)
        case .quietMode:
            // Enter quiet mode (if implemented)
            break
        }
        dismiss()
    }
}

// MARK: - Helper Components

struct SuggestionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct RedirectChip: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ScrollBudgetFeatureButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct RedirectOptionButton: View {
    let option: ScrollBudgetManager.RedirectOption
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview("50% Banner") {
    ScrollBudget50Banner()
}

#Preview("80% Suggestion") {
    ScrollBudget80Suggestion()
}

#Preview("Soft Stop") {
    ScrollBudgetSoftStopView(extensionsRemaining: 2)
}

#Preview("Locked") {
    ScrollBudgetLockedView()
}

#Preview("Compulsive Reopen") {
    CompulsiveReopenRedirectView(reopenCount: 3)
}
