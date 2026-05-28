// CommunityCreateSheet.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Minimal community creation: name, handle (auto-slug), avatar pick (PhotosPicker).
// Creates amenCommunities/{communityId} + members/{userId} with role "owner"
// via the `createCommunity` Firebase callable (SpacesCallable.createCommunity).
//
// DEPLOY NOTE: The `createCommunity` callable must be deployed before this sheet
// can complete creation. See CONTRACT_C.md §5 for the gap flag.
//
// Does NOT set up Stripe Connect (Agent E handles that post-creation).
// Liquid Glass sheet, spring dismiss.

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - CommunityCreateSheet

@MainActor
struct CommunityCreateSheet: View {

    // MARK: - Bindings / callbacks

    @Binding var isPresented: Bool
    /// Called with the new communityId on successful creation.
    var onCreated: ((String) -> Void)? = nil

    // MARK: - Form state

    @State private var communityName: String = ""
    @State private var communityHandle: String = ""
    @State private var handleWasManuallyEdited: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarUIImage: UIImage? = nil
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    avatarPicker
                        .padding(.top, 24)

                    nameField
                    handleField

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.statusError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background {
                if reduceTransparency {
                    AmenTheme.Colors.backgroundPrimary.ignoresSafeArea()
                } else {
                    Rectangle()
                        .fill(LiquidGlassTokens.blurThin)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("New Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .accessibilityLabel("Creating community")
                    } else {
                        Button("Create") {
                            Task { await createCommunity() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                        .disabled(!isValid)
                        .accessibilityLabel("Create community")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreating)
    }

    // MARK: - Subviews — all properties are @MainActor (struct is @MainActor)

    @MainActor private var avatarPicker: some View {
        let currentImage = avatarUIImage
        return PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            ZStack {
                if let image = currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(AmenTheme.Colors.amenPurple.opacity(0.4), lineWidth: 1.5) }
                } else {
                    Circle()
                        .fill(AmenTheme.Colors.surfaceChip)
                        .frame(width: 80, height: 80)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                Text("Photo")
                                    .font(.caption2)
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                        }
                        .overlay { Circle().stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5) }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { @MainActor in
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    avatarUIImage = img
                }
            }
        }
        .accessibilityLabel("Community avatar")
        .accessibilityHint("Double-tap to select a photo from your library.")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Community Name")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            TextField("e.g. Hillside Community", text: $communityName)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5)
                }
                .onChange(of: communityName) { _, newName in
                    if !handleWasManuallyEdited {
                        communityHandle = slugify(newName)
                    }
                }
                .accessibilityLabel("Community name")
        }
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Handle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            HStack(spacing: 2) {
                Text("@")
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                TextField("hillside-community", text: $communityHandle)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: communityHandle) { _, _ in
                        handleWasManuallyEdited = true
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceInput)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                    .stroke(AmenTheme.Colors.separatorSubtle, lineWidth: 0.5)
            }
            .accessibilityLabel("Community handle")
            .accessibilityHint("Unique identifier — only letters, numbers and hyphens.")
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        communityName.trimmingCharacters(in: .whitespaces).count >= 2 &&
        communityHandle.count >= 2
    }

    // MARK: - Creation

    private func createCommunity() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "You must be signed in to create a community."
            return
        }
        guard isValid else { return }

        isCreating = true
        errorMessage = nil

        let name = communityName.trimmingCharacters(in: .whitespaces)
        let handle = communityHandle.lowercased()

        do {
            // Attempt the Cloud Function callable (createCommunity).
            // See SpacesCallable.createCommunity in SpacesCore.swift.
            let functions = Functions.functions()
            let callable = functions.httpsCallable(SpacesCallable.createCommunity.rawValue)
            let result = try await callable.call([
                "name": name,
                "handle": handle
            ])

            if let data = result.data as? [String: Any],
               let communityId = data["communityId"] as? String {
                isCreating = false
                dismiss()
                onCreated?(communityId)
                return
            }
            throw SpacesServiceError.encodingFailed

        } catch {
            // Callable not yet deployed — fall back to direct Firestore write.
            // This fallback is intentional for pre-deploy testing; the callable
            // enforces server-side validation and sets SERVER-OWNED fields.
            // Remove the fallback once the callable is deployed.
            do {
                let db = Firestore.firestore()
                let commRef = db.collection("amenCommunities").document()
                let communityId = commRef.documentID
                let now = Timestamp(date: Date())
                let communityData: [String: Any] = [
                    "name": name,
                    "handle": handle,
                    "ownerUserId": uid,
                    "createdAt": now
                ]
                try await commRef.setData(communityData)
                // Write owner membership
                try await commRef.collection("members").document(uid).setData([
                    "role": "owner",
                    "joinedAt": now
                ])
                isCreating = false
                dismiss()
                onCreated?(communityId)
            } catch let fallbackError {
                isCreating = false
                errorMessage = fallbackError.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func dismiss() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.liquidSpring) {
            isPresented = false
        }
    }

    private func slugify(_ input: String) -> String {
        input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

#if DEBUG
#Preview("CommunityCreateSheet") {
    @Previewable @State var isPresented = true
    Text("Sheet host")
        .sheet(isPresented: $isPresented) {
            CommunityCreateSheet(isPresented: $isPresented) { id in
                print("Created: \(id)")
            }
        }
}
#endif
