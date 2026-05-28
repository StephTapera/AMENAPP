import SwiftUI
import FirebaseFunctions
import FirebaseAuth

struct AnonCrisisPostComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var isPosting = false
    @State private var postedSuccessfully = false

    private let functions = Functions.functions()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                safetyBanner
                composerField
                privacyNote
                Spacer()
                if postedSuccessfully { successView }
            }
            .padding(16)
            .navigationTitle("Anonymous Crisis Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isPosting ? "Sharing..." : "Post") {
                        Task { await post() }
                    }
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(!content.trimmingCharacters(in: .whitespaces).isEmpty ? Color(red: 0.40, green: 0.70, blue: 0.95) : AmenTheme.Colors.textTertiary)
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || isPosting)
                }
            }
        }
    }

    private var safetyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.circle.fill").foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95)).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("You are not alone").font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("Your identity is fully protected. Resources will be automatically added to your post.")
                    .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(Color(red: 0.40, green: 0.70, blue: 0.95).opacity(0.1))
        .cornerRadius(10)
    }

    private var composerField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share what you're going through")
                .font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
            TextEditor(text: $content)
                .font(.custom("OpenSans-Regular", size: 15))
                .frame(minHeight: 150)
                .padding(8)
                .background(AmenTheme.Colors.surfaceInput)
                .cornerRadius(10)
                .accessibilityLabel("Crisis post content")
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green).font(.caption)
            Text("Your identity is hashed and never stored with this post. Only opted-in community members will see it.")
                .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .padding(10).background(Color.green.opacity(0.06)).cornerRadius(8)
    }

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("Posted Anonymously").font(.custom("OpenSans-Bold", size: 18)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Resources have been added automatically. The community is here for you.")
                .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textSecondary).multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(red: 0.40, green: 0.70, blue: 0.95)).cornerRadius(12)
        }
        .padding(20)
    }

    private func post() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isPosting = true
        defer { isPosting = false }
        _ = try? await functions.httpsCallable("createAnonCrisisPost").call(["userId": uid, "content": content])
        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { postedSuccessfully = true }
    }
}
