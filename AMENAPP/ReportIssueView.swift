//
//  ReportIssueView.swift
//  AMENAPP
//
//  Created by Assistant on 2/3/26.
//

import SwiftUI

// MARK: - Report Issue View

struct ReportIssueView: View {
    let message: BereanMessage
    @Binding var isPresented: Bool
    
    @StateObject private var dataManager = BereanDataManager.shared
    @State private var selectedIssueType: BereanIssueReport.IssueType = .inaccurate
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @FocusState private var isDescriptionFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.05)
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
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                    .disabled(isSubmitting)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !showSuccess {
                        Button("Submit") {
                            submitReport()
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                        .fontWeight(.semibold)
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    }
                }
            }
        }
    }
    
    private var formView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Message preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Message")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                    
                    Text(message.content)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(5)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                
                // Issue type selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Issue Type")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                    
                    ForEach(BereanIssueReport.IssueType.allCases, id: \.self) { issueType in
                        IssueTypeCard(
                            issueType: issueType,
                            isSelected: selectedIssueType == issueType
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedIssueType = issueType
                            }
                        }
                    }
                }
                
                // Description
                VStack(alignment: .leading, spacing: 12) {
                    Text("Description")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                    
                    Text("Please provide details about the issue")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    TextEditor(text: $description)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 150)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .focused($isDescriptionFocused)
                }
                
                // Disclaimer
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                    
                    Text("Your feedback helps improve Berean AI. We'll review this report and take appropriate action.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .lineSpacing(3)
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.5, green: 0.6, blue: 0.9).opacity(0.1))
                )
            }
            .padding(20)
        }
        .disabled(isSubmitting)
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                        
                        Text("Submitting report...")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(white: 0.1))
                            .shadow(color: .black.opacity(0.3), radius: 20)
                    )
                }
            }
        }
    }
    
    private var successView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.2),
                                Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
            }
            
            VStack(spacing: 12) {
                Text("Report Submitted")
                    .font(.custom("Georgia", size: 28))
                    .fontWeight(.light)
                    .foregroundStyle(.white)
                
                Text("Thank you for helping improve Berean AI. We'll review your feedback and take action if needed.")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button {
                isPresented = false
            } label: {
                Text("Done")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                            .shadow(color: Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.3), radius: 15, y: 5)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    private func submitReport() {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSubmitting = true
        
        Task {
            do {
                try await dataManager.reportIssue(
                    message: message,
                    issueType: selectedIssueType,
                    description: description
                )
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                await MainActor.run {
                    isSubmitting = false
                    
                    withAnimation(.smooth(duration: 0.4)) {
                        showSuccess = true
                    }
                }
            } catch {
                print("❌ Failed to submit report: \(error)")
                
                await MainActor.run {
                    isSubmitting = false
                    
                    // Show error (you could add an error state)
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Issue Type Card

struct IssueTypeCard: View {
    let issueType: BereanIssueReport.IssueType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: issueType.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color(red: 1.0, green: 0.7, blue: 0.5) : .white.opacity(0.6))
                    .frame(width: 32)
                
                Text(issueType.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.white)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.5))
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ?
                                    Color(red: 1.0, green: 0.7, blue: 0.5).opacity(0.5) :
                                    Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ReportIssueView(
        message: BereanMessage(
            content: "This is a test message from Berean AI with some example content.",
            role: .assistant,
            timestamp: Date()
        ),
        isPresented: .constant(true)
    )
}
