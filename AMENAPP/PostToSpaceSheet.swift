// PostToSpaceSheet.swift — AMEN App
// Sheet for composing and submitting a post to a Space/Community

import SwiftUI
import FirebaseAuth

struct PostToSpaceSheet: View {
    let space: AMENSpace
    @ObservedObject var feedVM: SpaceFeedViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var postText      = ""
    @State private var selectedType: SpacePost.ContentType = .text
    @State private var isPosting     = false
    @State private var errorMessage: String? = nil

    // Simulated confidence score (static for now; could be wired to an AI call)
    private let confidenceScore: Int = 94

    private let background    = Color(red: 0.039, green: 0.039, blue: 0.059)
    private let accentPurple  = Color(red: 0.6,   green: 0.35,  blue: 1.0)
    private let accentPurple2 = Color(red: 0.45,  green: 0.2,   blue: 0.85)

    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespaces).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Content type picker
                    contentTypePicker
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    Divider()
                        .background(Color.white.opacity(0.06))

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Text editor or photo placeholder
                            if selectedType == .text {
                                textComposer
                            } else {
                                photoPlaceholder
                            }

                            // AI confidence card
                            aiConfidenceCard

                            // Error
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 13))
                                    Text(error)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.orange)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }

                    // Bottom post button
                    postButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                        .padding(.top, 12)
                        .background(
                            background
                                .overlay(
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, background],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(height: 1)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                )
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Post to")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(space.name)
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content Type Picker

    private var contentTypePicker: some View {
        HStack(spacing: 0) {
            ForEach([SpacePost.ContentType.text, .photo], id: \.self) { type in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedType = type
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: type == .text ? "text.bubble" : "photo")
                            .font(.system(size: 13, weight: .medium))
                        Text(type == .text ? "Text" : "Photo")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(selectedType == type ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedType == type
                                  ? LinearGradient(colors: [accentPurple, accentPurple2],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [.clear, .clear],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Text Composer

    private var textComposer: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            postText.isEmpty
                                ? Color.white.opacity(0.08)
                                : accentPurple.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: postText.isEmpty)

            if postText.isEmpty {
                Text("Share something with this community…")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $postText)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white)
                .tint(accentPurple)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 150)
        }
    }

    // MARK: - Photo Placeholder

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1.5)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(accentPurple.opacity(0.6))
                            Text("Photo upload coming soon")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    )
            )
            .frame(height: 180)
    }

    // MARK: - AI Confidence Card

    private var aiConfidenceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentPurple.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentPurple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("This looks like it belongs here")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(confidenceScore)% community match")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            // Compact confidence bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 52, height: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentPurple, Color(red: 0.35, green: 0.8, blue: 0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 52 * CGFloat(confidenceScore) / 100, height: 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentPurple.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Post Button

    private var postButton: some View {
        Button {
            submitPost()
        } label: {
            HStack(spacing: 10) {
                if isPosting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isPosting ? "Posting…" : "Post")
                    .font(AMENFont.semiBold(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        canPost
                            ? LinearGradient(colors: [accentPurple, accentPurple2],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.08)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing)
                    )
                    .shadow(color: accentPurple.opacity(canPost ? 0.45 : 0), radius: 10, y: 4)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!canPost)
    }

    // MARK: - Submit

    private func submitPost() {
        let trimmed = postText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let spaceId = space.id else { return }
        errorMessage = nil
        isPosting    = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await feedVM.postToSpace(
                    spaceId:   spaceId,
                    text:      trimmed,
                    mediaURLs: [],
                    type:      selectedType
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isPosting    = false
                    errorMessage = "Couldn't post. Please try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
