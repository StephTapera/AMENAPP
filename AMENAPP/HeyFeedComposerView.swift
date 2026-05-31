import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HeyFeedComposerView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedType: HeyFeedRequest.HeyFeedRequestType = .prayer
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @ObservedObject private var service = HeyFeedService.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private func intentForType(_ type: HeyFeedRequest.HeyFeedRequestType) -> HeyFeedIntent {
        switch type {
        case .prayer: return .prayerRequest
        case .question: return .question
        case .fellowship: return .fellowship
        case .study: return .biblicalStudy
        case .testimony: return .testimony
        case .care: return .prayerRequest
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    postPreviewCard
                    requestTypeSection
                    Spacer(minLength: 24)
                    submitButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to Hey Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
        .task {
            service.startListening()
        }
        .onDisappear {
            service.stopListening()
        }
    }

    // MARK: - Post Preview Card

    private var postPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    categoryBadge(for: post.category)
                }

                Text(post.content)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func categoryBadge(for category: Post.PostCategory) -> some View {
        Text(category.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.06))
            )
    }

    // MARK: - Request Type Section

    private var requestTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(HeyFeedRequest.HeyFeedRequestType.allCases, id: \.self) { type in
                    requestTypePill(type)
                }
            }
        }
    }

    private func requestTypePill(_ type: HeyFeedRequest.HeyFeedRequestType) -> some View {
        let isSelected = selectedType == type

        return Button {
            withAnimation(reduceMotion ? nil : Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.systemScaled(14, weight: .medium))
                Text(type.displayName)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.black)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.04), radius: isSelected ? 8 : 4, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.72), value: isSelected)
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            guard !isSubmitting else { return }
            submitRequest()
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .frame(height: 52)
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 5)

                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.systemScaled(16, weight: .semibold))
                        Text("Submit to Hey Feed")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.7 : 1.0)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isSubmitting)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.systemScaled(26, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Added to Hey Feed")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    // MARK: - Actions

    private func submitRequest() {
        guard let postId = post.firebaseId else {
            dlog("HeyFeedComposerView: post has no firebaseId, cannot submit")
            return
        }
        isSubmitting = true
        let intent = intentForType(selectedType)

        Task {
            do {
                try await service.submitRequest(
                    postId: postId,
                    requestType: selectedType,
                    intent: intent
                )
                await MainActor.run {
                    isSubmitting = false
                    withAnimation(reduceMotion ? nil : Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                        showSuccess = true
                    }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                dlog("HeyFeedComposerView: submitRequest failed — \(error)")
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}
