import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

struct ProfileBannerCrop: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1
}

struct ProfileBannerFocalPoint: Codable, Equatable {
    var x: Double = 0.5
    var y: Double = 0.42
}

enum ProfileBannerStatus: String, Codable, Equatable {
    case pending
    case approved
    case rejected
}

struct ProfileBanner: Identifiable, Codable, Equatable {
    let id: String
    let ownerUid: String
    var imageURL: String?
    var storagePath: String?
    var status: ProfileBannerStatus
    var crop: ProfileBannerCrop
    var focalPoint: ProfileBannerFocalPoint
    var dominantColors: [String]
    var blurHash: String?
    var createdAt: Date
    var updatedAt: Date

    var isVisiblePublicly: Bool { status == .approved }

    static func decode(from data: [String: Any], ownerUid: String, viewerOwnsProfile: Bool) -> ProfileBanner? {
        guard let raw = data["profileBanner"] as? [String: Any] else { return nil }
        let status = ProfileBannerStatus(rawValue: raw["status"] as? String ?? "") ?? .pending
        guard status == .approved || viewerOwnsProfile else { return nil }

        let cropData = raw["crop"] as? [String: Any] ?? [:]
        let focalData = raw["focalPoint"] as? [String: Any] ?? [:]
        let createdAt = (raw["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (raw["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return ProfileBanner(
            id: raw["id"] as? String ?? UUID().uuidString,
            ownerUid: raw["ownerUid"] as? String ?? ownerUid,
            imageURL: raw["imageURL"] as? String,
            storagePath: raw["storagePath"] as? String,
            status: status,
            crop: ProfileBannerCrop(
                x: cropData["x"] as? Double ?? 0,
                y: cropData["y"] as? Double ?? 0,
                width: cropData["width"] as? Double ?? 1,
                height: cropData["height"] as? Double ?? 1
            ),
            focalPoint: ProfileBannerFocalPoint(
                x: focalData["x"] as? Double ?? 0.5,
                y: focalData["y"] as? Double ?? 0.42
            ),
            dominantColors: raw["dominantColors"] as? [String] ?? [],
            blurHash: raw["blurHash"] as? String,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func firestoreData() -> [String: Any] {
        [
            "id": id,
            "ownerUid": ownerUid,
            "imageURL": imageURL as Any,
            "storagePath": storagePath as Any,
            "status": status.rawValue,
            "crop": ["x": crop.x, "y": crop.y, "width": crop.width, "height": crop.height],
            "focalPoint": ["x": focalPoint.x, "y": focalPoint.y],
            "dominantColors": dominantColors,
            "blurHash": blurHash as Any,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

@MainActor
final class ProfileBannerService: ObservableObject {
    static let shared = ProfileBannerService()

    enum ProfileBannerServiceError: LocalizedError {
        case notSignedIn
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "You must be signed in to update your banner."
            case .invalidImage: return "Choose a JPEG, PNG, HEIC, or WebP image under 8 MB."
            }
        }
    }

    func uploadPendingBanner(imageData: Data, ownerUid: String? = nil) async throws -> ProfileBanner {
        guard let uid = ownerUid ?? Auth.auth().currentUser?.uid else { throw ProfileBannerServiceError.notSignedIn }
        guard let image = UIImage(data: imageData), let compressed = image.jpegData(compressionQuality: 0.82) else {
            throw ProfileBannerServiceError.invalidImage
        }
        guard compressed.count <= 8 * 1024 * 1024 else { throw ProfileBannerServiceError.invalidImage }

        let bannerId = UUID().uuidString
        let storagePath = "profileBanners/\(uid)/\(bannerId).jpg"
        let ref = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(compressed, metadata: metadata)
        let url = try await ref.downloadURL()
        let now = Date()
        let banner = ProfileBanner(
            id: bannerId,
            ownerUid: uid,
            imageURL: url.absoluteString,
            storagePath: storagePath,
            status: .pending,
            crop: ProfileBannerCrop(),
            focalPoint: ProfileBannerFocalPoint(),
            dominantColors: [],
            blurHash: nil,
            createdAt: now,
            updatedAt: now
        )

        try await Firestore.firestore().collection("users").document(uid).updateData([
            "profileBanner": banner.firestoreData(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        return banner
    }

    func removeBanner(ownerUid: String? = nil) async throws {
        guard let uid = ownerUid ?? Auth.auth().currentUser?.uid else { throw ProfileBannerServiceError.notSignedIn }
        try await Firestore.firestore().collection("users").document(uid).updateData([
            "profileBanner": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
}

struct ProfileBannerView: View {
    let banner: ProfileBanner?
    let viewerOwnsProfile: Bool
    let collapseProgress: CGFloat
    var onEdit: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var bannerHeight: CGFloat = 138

    private var shouldRender: Bool { banner != nil || viewerOwnsProfile }

    var body: some View {
        if shouldRender {
            ZStack(alignment: .topTrailing) {
                bannerSurface

                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: banner == nil ? "plus" : "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(liquidGlassCapsule)
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(banner == nil ? "Add optional profile banner" : "Edit profile banner")
                    .padding(10)
                }
            }
            .frame(height: max(116, bannerHeight - collapseProgress * 28))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(reduceTransparency ? 0.2 : 0.65), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 18, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .scaleEffect(1 - collapseProgress * 0.018, anchor: .top)
            .opacity(1 - collapseProgress * 0.28)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: collapseProgress)
        }
    }

    @ViewBuilder
    private var bannerSurface: some View {
        if let imageURL = banner?.imageURL, let url = URL(string: imageURL), banner?.status != .rejected {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .overlay(readabilityOverlay)
                case .failure:
                    cleanFallback(label: "Banner unavailable")
                case .empty:
                    cleanFallback(label: "Loading banner")
                        .overlay(ProgressView().tint(.primary))
                @unknown default:
                    cleanFallback(label: "Profile banner")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if banner?.status == .pending, viewerOwnsProfile {
                    statusChip("Pending review", systemImage: "clock")
                        .padding(12)
                }
            }
        } else {
            cleanFallback(label: viewerOwnsProfile ? "Optional banner" : "")
        }
    }

    private var readabilityOverlay: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.04), Color.black.opacity(0.14), Color.white.opacity(0.46)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func cleanFallback(label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.96, blue: 1.0).opacity(0.95), .white, Color(red: 1.0, green: 0.94, blue: 0.89).opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.88)

            if !label.isEmpty {
                statusChip(label, systemImage: "sparkles")
                    .padding(12)
            }
        }
    }

    private func statusChip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(liquidGlassCapsule)
    }

    private var liquidGlassCapsule: some View {
        Capsule()
            .fill(reduceTransparency ? Color.white : Color.white.opacity(0.42))
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(reduceTransparency ? 0 : 1)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.82), Color.white.opacity(0.26), Color.black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.11), radius: 12, y: 5)
    }
}

struct SmartProfileBannerPicker: View {
    @Binding var banner: ProfileBanner?
    var onChanged: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profile Banner")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.secondary)
                Spacer()
                if isUploading {
                    ProgressView()
                }
            }

            ProfileBannerView(banner: banner, viewerOwnsProfile: true, collapseProgress: 0, onEdit: nil)
                .padding(.horizontal, -16)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(banner == nil ? "Add optional banner" : "Change banner", systemImage: "photo.on.rectangle")
                        .font(AMENFont.bold(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.82)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .disabled(isUploading)

                if banner != nil {
                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.82)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                    .accessibilityLabel("Remove profile banner")
                }
            }

            Text(helperText)
                .font(AMENFont.regular(12))
                .foregroundStyle(errorMessage == nil ? .secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await uploadSelectedBanner(newItem) }
        }
        .confirmationDialog("Remove profile banner?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove Banner", role: .destructive) {
                Task { await removeBanner() }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var helperText: String {
        if let errorMessage { return errorMessage }
        switch banner?.status {
        case .pending: return "Your banner is visible to you while moderation reviews it. Public profiles keep showing the last approved banner or no banner."
        case .approved: return "Banners are optional. Liquid Glass controls adapt over the image without covering it."
        case .rejected: return "This banner was rejected and is not public. Choose another image or remove it."
        case nil: return "Optional. Leave this blank for the clean white profile header."
        }
    }

    private func uploadSelectedBanner(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        errorMessage = nil
        isUploading = true
        defer { isUploading = false; selectedItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ProfileBannerService.ProfileBannerServiceError.invalidImage
            }
            banner = try await ProfileBannerService.shared.uploadPendingBanner(imageData: data)
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBanner() async {
        errorMessage = nil
        isUploading = true
        defer { isUploading = false }

        do {
            try await ProfileBannerService.shared.removeBanner()
            banner = nil
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
