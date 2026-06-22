//
//  ReportUnsafeAIResponseSheet.swift
//  AMENAPP
//
//  Phase H3 / App Review Guideline 1.2 — the visible sheet a user
//  presents from an AI response (Berean chat message, Daily Verse,
//  Berean Pulse card, etc.) to report it as unsafe / objectionable.
//
//  The sheet collects a reason from a fixed allowlist and an optional
//  free-form note (capped at 500 chars). It calls
//  AIUnsafeResponseReporter.submit(...) which forwards to the
//  reportUnsafeAIResponse Cloud Function (Auth + App Check enforced).
//
//  This sheet exists separately from the Berean *safety filter* — the
//  safety filter blocks bad output server-side BEFORE the user sees it;
//  this report is for output that slipped through and that the user
//  considers unsafe in hindsight.

import SwiftUI

struct ReportUnsafeAIResponseSheet: View {
    let messageId: String
    let conversationId: String?
    let surface: AIUnsafeResponseReporter.Surface

    /// Called with the server-assigned reportId after a successful
    /// submission. The host typically dismisses the sheet and shows a
    /// brief confirmation.
    let onSubmitted: (_ reportId: String) -> Void

    @State private var selectedReason: AIUnsafeResponseReporter.Reason = .unsafeAdvice
    @State private var details: String = ""
    @State private var submitting: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let detailsCap = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell us what felt unsafe. Our team reviews every report and the AI response will be re-evaluated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(AIUnsafeResponseReporter.Reason.allCases) { reason in
                            Text(reason.label).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextEditor(text: $details)
                        .frame(minHeight: 96)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Optional details (\(detailsCap)-char max)")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Spacer()
                        Text("\(details.count) / \(detailsCap)")
                            .font(.caption)
                            .foregroundStyle(details.count > detailsCap ? .red : .secondary)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Don't paste sensitive personal information.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Report response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(submitting || details.count > detailsCap)
                    .accessibilityLabel("Submit report")
                }
            }
        }
    }

    private func submit() async {
        guard !submitting else { return }
        submitting = true
        errorMessage = nil
        do {
            let trimmedDetails: String? = {
                let t = details.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }()
            let reportId = try await AIUnsafeResponseReporter.shared.submit(
                messageId: messageId,
                reason: selectedReason,
                details: trimmedDetails,
                conversationId: conversationId,
                surface: surface
            )
            onSubmitted(reportId)
            dismiss()
        } catch let err as AIUnsafeResponseReporter.ReportError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = "Could not submit your report. Please retry."
        }
        submitting = false
    }
}
