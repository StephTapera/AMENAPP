// CreateSpaceSheet.swift — AMEN App
// Sheet for creating a new Space/Community via AI-assisted generation

import SwiftUI

struct CreateSpaceSheet: View {
    @ObservedObject var vm: SpacesViewModel
    @Environment(\.dismiss) private var dismiss

    // Phase 1 inputs
    @State private var descriptionInput = ""

    // AI-generated values
    @State private var aiName        = ""
    @State private var aiDescription = ""
    @State private var aiTopics: [String] = []

    // Phase 2 editable
    @State private var editableName        = ""
    @State private var editableDescription = ""

    // State flags
    @State private var isGenerating = false
    @State private var isCreating   = false
    @State private var showPreview  = false
    @State private var errorMessage: String? = nil

    private let background    = Color(red: 0.039, green: 0.039, blue: 0.059)
    private let accentPurple  = Color(red: 0.6,   green: 0.35,  blue: 1.0)
    private let accentPurple2 = Color(red: 0.45,  green: 0.2,   blue: 0.85)

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if !showPreview {
                            phase1View
                        } else {
                            phase2View
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal:   .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: showPreview)
                }
            }
            .navigationTitle("New Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.white.opacity(0.65))
                }
                if showPreview {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showPreview = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.systemScaled(13, weight: .semibold))
                                Text("Back")
                            }
                            .font(AMENFont.regular(16))
                            .foregroundStyle(accentPurple)
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Phase 1: Describe

    private var phase1View: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Heading
            VStack(alignment: .leading, spacing: 6) {
                Text("What's your community about?")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.white)

                Text("Describe it in your own words and let AI name it.")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Description text editor
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    )

                if descriptionInput.isEmpty {
                    Text("e.g. A place for fathers to share how they are raising their kids in the faith, discuss scripture, prayer victories…")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $descriptionInput)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white)
                    .tint(accentPurple)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(minHeight: 160)
            }

            // Character count
            HStack {
                Spacer()
                Text("\(descriptionInput.count) / 400")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(descriptionInput.count > 380 ? Color.orange : .white.opacity(0.3))
            }

            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.systemScaled(13))
                    Text(error)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.orange)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                )
            }

            // Generate button
            Button {
                generateWithAI()
            } label: {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                    Text(isGenerating ? "Generating…" : "Generate with AI")
                        .font(AMENFont.semiBold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: descriptionInput.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.08)]
                                    : [accentPurple, accentPurple2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: accentPurple.opacity(descriptionInput.isEmpty ? 0 : 0.45),
                            radius: 10, y: 4
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(descriptionInput.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
        }
    }

    // MARK: - Phase 2: Preview & Edit

    private var phase2View: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Here's your community")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.white)
                Text("Refine any details before creating.")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Preview card
            VStack(alignment: .leading, spacing: 16) {

                // Editable name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Community Name")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .kerning(0.5)

                    TextField("Community name", text: $editableName)
                        .font(AMENFont.bold(18))
                        .foregroundStyle(.white)
                        .tint(accentPurple)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(accentPurple.opacity(0.3), lineWidth: 1)
                                )
                        )
                }

                // Editable description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .kerning(0.5)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        TextEditor(text: $editableDescription)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.white.opacity(0.85))
                            .tint(accentPurple)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .frame(minHeight: 80)
                    }
                }

                // Topic pills
                if !aiTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Topics")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.white.opacity(0.45))
                            .textCase(.uppercase)
                            .kerning(0.5)

                        FlowLayoutTopics(topics: aiTopics, accentColor: accentPurple)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            // Error message
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.systemScaled(13))
                    Text(error)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.orange)
                }
            }

            // Create button
            Button {
                createCommunity()
            } label: {
                HStack(spacing: 10) {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                    Text(isCreating ? "Creating…" : "Create Community")
                        .font(AMENFont.semiBold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: editableName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.08)]
                                    : [accentPurple, accentPurple2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: accentPurple.opacity(editableName.isEmpty ? 0 : 0.45),
                            radius: 10, y: 4
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(editableName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
        }
    }

    // MARK: - Actions

    private func generateWithAI() {
        guard !descriptionInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorMessage = nil
        isGenerating = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let result = try await vm.aiGenerateSpaceDetails(from: descriptionInput)
                await MainActor.run {
                    aiName              = result.name
                    aiDescription       = result.description
                    aiTopics            = result.topics
                    editableName        = result.name
                    editableDescription = result.description
                    isGenerating        = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showPreview = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isGenerating  = false
                    errorMessage  = "Could not generate details. Please try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func createCommunity() {
        guard !editableName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        errorMessage = nil
        isCreating   = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                _ = try await vm.createSpace(
                    name:        editableName.trimmingCharacters(in: .whitespaces),
                    description: editableDescription.trimmingCharacters(in: .whitespaces),
                    topics:      aiTopics
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating   = false
                    errorMessage = "Could not create community. Please try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - FlowLayoutTopics

/// Simple wrapping HStack for topic pills in the preview card.
private struct FlowLayoutTopics: View {
    let topics: [String]
    let accentColor: Color

    var body: some View {
        // SwiftUI doesn't have a native FlowLayout before iOS 16 ViewThatFits;
        // use a simple wrapping approach via a LazyVGrid of flexible columns.
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 200), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(topics, id: \.self) { topic in
                Text(topic)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .strokeBorder(accentColor.opacity(0.3), lineWidth: 0.75)
                            )
                    )
                    .lineLimit(1)
            }
        }
    }
}
