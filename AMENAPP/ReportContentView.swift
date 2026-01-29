//
//  ReportContentView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI

struct ReportContentView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var functionsService = CloudFunctionsService.shared
    
    let contentType: String
    let contentId: String
    let contentPreview: String
    
    @State private var selectedReason: ContentReportReason?
    @State private var additionalDetails = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.red)
                        
                        Text("Report Content")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("Help us keep AMEN safe and positive")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    
                    // Content Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reporting this \(contentType):")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        Text(contentPreview)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Reason Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why are you reporting this?")
                            .font(.custom("OpenSans-Bold", size: 17))
                        
                        ForEach(ContentReportReason.allCases, id: \.self) { reason in
                            ReportReasonButton(
                                reason: reason,
                                isSelected: selectedReason == reason
                            ) {
                                selectedReason = reason
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Additional Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional Details (Optional)")
                            .font(.custom("OpenSans-Bold", size: 17))
                        
                        TextEditor(text: $additionalDetails)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                        
                        Text("Provide any additional context that might help our review")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Submit Button
                    Button {
                        submitReport()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Submitting...")
                            } else {
                                Image(systemName: "flag.fill")
                                Text("Submit Report")
                            }
                        }
                        .font(.custom("OpenSans-SemiBold", size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedReason != nil ? Color.red : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(selectedReason == nil || isSubmitting)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Report Submitted", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for helping keep AMEN safe. We'll review this report and take appropriate action.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        Task {
            isSubmitting = true
            
            do {
                try await functionsService.reportContent(
                    contentType: contentType,
                    contentId: contentId,
                    reason: reason.rawValue,
                    details: additionalDetails
                )
                
                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
                
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Report Reason Button

struct ReportReasonButton: View {
    let reason: ContentReportReason
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .blue : .gray)
                
                Image(systemName: reason.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .blue : .gray)
                    .frame(width: 24)
                
                Text(reason.displayName)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ReportContentView(
        contentType: "post",
        contentId: "123",
        contentPreview: "This is a sample post that is being reported for review."
    )
}
