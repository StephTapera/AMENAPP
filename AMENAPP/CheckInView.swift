// CheckInView.swift
// AMENAPP
import SwiftUI
import FirebaseFirestore

struct CheckInView: View {
    let checkIn: MentorshipCheckIn
    let onComplete: () -> Void

    @State private var response: String = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @FocusState private var editorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mentor header
                    HStack(spacing: 12) {
                        MentorAvatarView(name: checkIn.mentorName, photoURL: checkIn.mentorPhotoURL, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From \(checkIn.mentorName)")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Due \(checkIn.dueDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Status badge
                        Text(checkIn.status.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(checkIn.status.color)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(checkIn.status.color.opacity(0.10)))
                    }
                    .padding(.horizontal, 18)

                    // Prompt card
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Check-in Prompt")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(0.8)
                            .textCase(.uppercase)
                        Text(checkIn.prompt)
                            .font(.system(size: 15).italic())
                            .foregroundStyle(.primary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal, 18)

                    // Response editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Response")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(0.8)
                            .textCase(.uppercase)
                            .padding(.leading, 18)

                        TextEditor(text: $response)
                            .focused($editorFocused)
                            .font(.system(size: 15))
                            .frame(minHeight: 160)
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                            .padding(.horizontal, 18)

                        Text("\(response.count) characters")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 18)
                    }

                    // Success state
                    if submitted {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.09, green: 0.64, blue: 0.29))
                            Text("Response submitted! Your mentor has been notified.")
                                .font(.system(size: 13))
                        }
                        .padding(14)
                        .background(Color(red: 0.09, green: 0.64, blue: 0.29).opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal, 18)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submitResponse() }
                    } label: {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Submit")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(
                                    response.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color(.systemGray3)
                                    : Color(red: 0.49, green: 0.23, blue: 0.93)
                                )
                        }
                    }
                    .disabled(response.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting || submitted)
                }
            }
        }
        .onAppear { editorFocused = true }
    }

    private func submitResponse() async {
        isSubmitting = true
        do {
            try await MentorshipService.shared.submitCheckInResponse(checkInId: checkIn.id, response: response)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { submitted = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onComplete()
                dismiss()
            }
        } catch {
            dlog("⚠️ CheckInView submit error: \(error)")
        }
        isSubmitting = false
    }
}
