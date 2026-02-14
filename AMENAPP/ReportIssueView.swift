//
//  ReportIssueView.swift
//  AMENAPP
//
//  Issue reporting UI for Berean AI
//

import SwiftUI

struct ReportIssueView: View {
    let message: BereanMessage
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataManager = BereanDataManager.shared
    
    @State private var selectedIssueType: BereanIssueReport.IssueType = .inaccurate
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle background matching Berean aesthetic
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 0.96, green: 0.95, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if showSuccess {
                    successView
                } else {
                    formView
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(white: 0.3))
                    }
                }
            }
        }
    }
    
    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Help Us Improve")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color(white: 0.2))
                    
                    Text("Your feedback helps Berean AI provide better responses for everyone.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(white: 0.4))
                        .lineSpacing(4)
                }
                .padding(.top, 20)
                
                // Message preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reported Message")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.3))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                        )
                        .lineLimit(4)
                }
                
                // Issue type selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Issue Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    VStack(spacing: 8) {
                        ForEach(BereanIssueReport.IssueType.allCases, id: \.self) { type in
                            IssueTypeButton(
                                type: type,
                                isSelected: selectedIssueType == type
                            ) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedIssueType = type
                                }
                                
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        }
                    }
                }
                
                // Description
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details (Optional)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.4))
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    TextEditor(text: $description)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.3))
                        .frame(height: 120)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(white: 0.85), lineWidth: 1)
                                )
                        )
                        .scrollContentBackground(.hidden)
                    
                    Text("Help us understand the issue better")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.5))
                }
                
                // Submit button
                Button {
                    submitReport()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Submit Report")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color.orange.opacity(0.3), radius: 10, y: 4)
                    )
                }
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.6 : 1.0)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.1))
                        )
                }
            }
            .padding(20)
        }
    }
    
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.green.opacity(0.2),
                                Color.green.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(Color.green)
                    .symbolEffect(.bounce)
            }
            
            VStack(spacing: 12) {
                Text("Report Submitted")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color(white: 0.2))
                
                Text("Thank you for helping us improve Berean AI. We'll review your feedback carefully.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.3))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                try await dataManager.reportIssue(
                    message: message,
                    issueType: selectedIssueType,
                    description: description.isEmpty ? "No additional details provided" : description
                )
                
                await MainActor.run {
                    isSubmitting = false
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSuccess = true
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to submit report. Please try again."
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Issue Type Button

struct IssueTypeButton: View {
    let type: BereanIssueReport.IssueType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.orange : Color(white: 0.4))
                    .frame(width: 32)
                
                Text(type.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(white: 0.2) : Color(white: 0.4))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.orange.opacity(0.4) : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
