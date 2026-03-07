//
//  FollowThroughInteractions.swift
//  AMENAPP
//
//  Feature B: Smart follow-through loop
//  - Prayer: "I prayed" button + one-tap encouragement message
//  - Testimony: "Reflect" prompt for structured responses
//  - Gentle in-app reminders (opt-in, respects quiet hours)
//  - Privacy-first: no forced interactions
//

import SwiftUI
import FirebaseAuth

// MARK: - PrayerFollowThroughBar
//
// A subtle action bar shown at the bottom of a PrayerPostCard.
// Shows: "🙏 I prayed", count of people who prayed, optional "Send encouragement"
// The bar is only shown when viewing someone else's prayer request.

struct PrayerFollowThroughBar: View {
    let post: Post
    
    @State private var hasPrayed: Bool = false
    @State private var prayCount: Int = 0
    @State private var isInFlight: Bool = false
    @State private var showEncouragementSheet: Bool = false
    @State private var encouragementSent: Bool = false
    
    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var isOwnPost: Bool { post.authorId == currentUserId }
    
    var body: some View {
        // Only show for other users' prayer requests
        if !isOwnPost, post.topicTag == "Prayer Request" {
            HStack(spacing: 12) {
                // "I prayed" button
                Button {
                    togglePrayed()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasPrayed ? "hands.and.sparkles.fill" : "hands.and.sparkles")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(hasPrayed ? Color.indigo : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        
                        if prayCount > 0 {
                            Text("\(prayCount)")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(hasPrayed ? Color.indigo : .secondary)
                                .contentTransition(.numericText())
                        }
                        
                        Text(hasPrayed ? "Prayed" : "I prayed")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(hasPrayed ? Color.indigo : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(hasPrayed ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .strokeBorder(hasPrayed ? Color.indigo.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isInFlight)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hasPrayed)
                
                // "Encourage" button — shows after praying or always
                if hasPrayed && !encouragementSent {
                    Button {
                        showEncouragementSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 14))
                                .foregroundStyle(.pink)
                            Text("Encourage")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.pink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.pink.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else if encouragementSent {
                    Text("Encouragement sent ✓")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .sheet(isPresented: $showEncouragementSheet) {
                EncouragementSheet(post: post, onSent: {
                    withAnimation { encouragementSent = true }
                })
                .presentationDetents([.height(320)])
            }
            .task {
                await loadPrayedState()
            }
        }
    }
    
    // MARK: - Actions
    
    private func togglePrayed() {
        guard !isInFlight else { return }
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        isInFlight = true
        let postId = post.id.uuidString
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            hasPrayed.toggle()
            prayCount += hasPrayed ? 1 : -1
        }
        
        Task {
            do {
                if hasPrayed {
                    try await PrayerFollowThroughService.shared.commitToPray(prayerId: postId)
                }
                // Note: uncommitting is not in the service yet — optimistic is fine
            } catch {
                // Rollback optimistic update on failure
                await MainActor.run {
                    withAnimation {
                        hasPrayed.toggle()
                        prayCount += hasPrayed ? 1 : -1
                    }
                    let errHaptic = UINotificationFeedbackGenerator()
                    errHaptic.notificationOccurred(.error)
                }
            }
            await MainActor.run { isInFlight = false }
        }
    }
    
    private func loadPrayedState() async {
        guard let userId = currentUserId else { return }
        let postId = post.id.uuidString
        
        // Check if user has already committed to pray via the service commitments
        let hasCommitment = PrayerFollowThroughService.shared.myPrayerCommitments
            .contains { $0.prayerId == postId && $0.intercessorId == userId }
        
        await MainActor.run {
            hasPrayed = hasCommitment
            // Use amenCount as a proxy for "prayed count" (mapped to hands.sparkles interactions)
            prayCount = max(0, post.amenCount)
        }
    }
}

// MARK: - EncouragementSheet

private struct EncouragementSheet: View {
    let post: Post
    let onSent: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMessage: String = ""
    @State private var isSending = false
    
    private let quickMessages = [
        "Praying for you today 🙏",
        "God sees you and is with you ✨",
        "Standing with you in prayer 💙",
        "Your faith is an encouragement to all of us",
        "Believing God for your breakthrough!"
    ]
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Send a word of encouragement")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // Quick messages
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(quickMessages, id: \.self) { message in
                            Button {
                                selectedMessage = message
                            } label: {
                                HStack {
                                    Text(message)
                                        .font(.custom("OpenSans-Regular", size: 15))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                    
                                    if selectedMessage == message {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.indigo)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedMessage == message
                                              ? Color.indigo.opacity(0.1)
                                              : Color(.secondarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(selectedMessage == message
                                                              ? Color.indigo.opacity(0.4)
                                                              : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedMessage)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Send button
                Button {
                    sendEncouragement()
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        } else {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14))
                        }
                        Text(isSending ? "Sending..." : "Send Encouragement")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(selectedMessage.isEmpty ? Color.gray : Color.indigo)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedMessage.isEmpty || isSending)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Encourage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func sendEncouragement() {
        guard !selectedMessage.isEmpty, !isSending else { return }
        isSending = true
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        Task {
            do {
                try await PrayerFollowThroughService.shared.sendEncouragement(
                    to: post.id.uuidString,
                    message: selectedMessage
                )
                await MainActor.run {
                    onSent()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    let errHaptic = UINotificationFeedbackGenerator()
                    errHaptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - TestimonyReflectPrompt
//
// Shown below a testimony card for viewers (not the author).
// Offers "Ask a question" or "Reflect" structured response types.
// Gentle update reminder shown to testimony AUTHORS after 7+ days.

struct TestimonyReflectPrompt: View {
    let post: Post
    
    @State private var showReflectSheet = false
    @State private var hasResponded = false
    
    private var isOwnPost: Bool { post.authorId == Auth.auth().currentUser?.uid }
    
    var body: some View {
        Group {
            if isOwnPost {
                // Author: gentle "Share an update?" nudge (only if 7+ days old)
                if shouldShowUpdateNudge {
                    authorUpdateNudge
                }
            } else if !hasResponded {
                // Viewer: reflect/ask prompt
                viewerReflectRow
            }
        }
        .sheet(isPresented: $showReflectSheet) {
            ReflectSheet(post: post, onSubmitted: {
                withAnimation { hasResponded = true }
            })
            .presentationDetents([.height(400)])
        }
    }
    
    private var shouldShowUpdateNudge: Bool {
        let daysSincePost = Calendar.current.dateComponents([.day], from: post.createdAt, to: Date()).day ?? 0
        return daysSincePost >= 7
    }
    
    private var authorUpdateNudge: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Text("Any update you'd like to share?")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showReflectSheet = true
            } label: {
                Text("Share")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
    
    private var viewerReflectRow: some View {
        AISparkleSearchButton {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            showReflectSheet = true
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - ReflectSheet

struct ReflectSheet: View {
    let post: Post
    let onSubmitted: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ResponseType = .reflect
    @State private var responseText = ""
    @State private var isSubmitting = false
    @FocusState private var isTextFocused: Bool
    
    enum ResponseType: String, CaseIterable {
        case reflect = "Reflect"
        case ask = "Ask a question"
        
        var icon: String {
            switch self {
            case .reflect: return "lightbulb"
            case .ask: return "questionmark.bubble"
            }
        }
        
        var placeholder: String {
            switch self {
            case .reflect: return "What does this testimony stir in you?"
            case .ask: return "What would you like to ask?"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Type selector
                HStack(spacing: 8) {
                    ForEach(ResponseType.allCases, id: \.self) { type in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                selectedType = type
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 13))
                                Text(type.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                            }
                            .foregroundStyle(selectedType == type ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedType == type ? Color.black : Color.gray.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
                // Text input with animated border while submitting
                TextField(selectedType.placeholder, text: $responseText, axis: .vertical)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .lineLimit(4...8)
                    .focused($isTextFocused)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.clear, lineWidth: 0)
                            .overlay(
                                isSubmitting ? AnyView(SpinningBorderOverlay(cornerRadius: 14)) : AnyView(EmptyView())
                            )
                    )
                    .padding(.horizontal)
                    .contentGuardrail(text: $responseText, context: .comment)
                
                Spacer()
                
                Button {
                    submitResponse()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8).tint(.white)
                        }
                        Text(isSubmitting ? "Submitting..." : "Submit")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? Color.gray
                                  : Color.black)
                    )
                }
                .buttonStyle(.plain)
                .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle(selectedType == .reflect ? "Reflect" : "Ask a Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isTextFocused = true }
        }
    }
    
    private func submitResponse() {
        let text = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        Task {
            do {
                // Submit as a comment on the post with a type tag
                let taggedContent = selectedType == .ask
                    ? "❓ \(text)"
                    : "💡 \(text)"
                _ = try await CommentService.shared.addComment(
                    postId: String(post.firestoreId.prefix(8)),
                    content: taggedContent,
                    post: post
                )
                await MainActor.run {
                    onSubmitted()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    let errHaptic = UINotificationFeedbackGenerator()
                    errHaptic.notificationOccurred(.error)
                    print("❌ Failed to submit reflect/ask: \(error)")
                }
            }
        }
    }
}

// MARK: - AISparkleSearchButton
//
// Black-and-white AI sparkle-search icon button.
// Replaces the "Reflect or ask a question" text label.
// Animates on press: scale down + rotate sparkle.

struct AISparkleSearchButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Image("amen-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .blendMode(.multiply)
                .scaleEffect(isPressed ? 0.80 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.52), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - SpinningBorderOverlay
//
// Animating conic-gradient-style spinning border that wraps the text input
// while the reflection/question is being submitted ("thinking" state).

struct SpinningBorderOverlay: View {
    let cornerRadius: CGFloat

    @State private var rotation: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.5),
                        Color.black,
                        Color.black.opacity(0.5),
                        Color.black.opacity(0.0)
                    ]),
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: 2
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}
