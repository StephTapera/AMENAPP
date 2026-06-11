//
//  ProfilePhotoEditView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  View for editing profile photo with camera/library options
//  Redesigned with iOS 26 Liquid Glass design language (2026-06-08)
//

import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision

// MARK: - Supporting Types

enum FaceDetectionState: Equatable {
    case idle, running, faceFound, noFace
}

enum PhotoQualityWarning: Hashable {
    case lowResolution, largeFile
}

// MARK: - Zoomable Circle View

struct ZoomableCircleView: View {
    let image: UIImage
    let diameter: CGFloat
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: diameter * zoomScale, height: diameter * zoomScale)
            .offset(panOffset)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(1.0, min(3.0, value))
                        },
                    DragGesture()
                        .onChanged { value in
                            let maxOffset = max(0, (diameter * zoomScale - diameter) / 2)
                            panOffset = CGSize(
                                width:  max(-maxOffset, min(maxOffset, value.translation.width)),
                                height: max(-maxOffset, min(maxOffset, value.translation.height))
                            )
                        }
                )
            )
    }
}

// MARK: - Recent Photo Thumbnail

struct RecentPhotoThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    let onSelect: (UIImage) -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button {
            guard let thumb = thumbnail else { return }
            onSelect(thumb)
        } label: {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(ProgressView().scaleEffect(0.55))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.white.opacity(0.35),
                        lineWidth: isSelected ? 3 : 1.5
                    )
            )
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
        .task {
            thumbnail = await fetchThumbnail()
        }
    }

    private func fetchThumbnail() async -> UIImage? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            // Use .fastFormat so the handler is called exactly once (no multi-call risk)
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill,
                options: opts
            ) { img, info in
                // Guard against the double-call that .opportunistic can produce
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                cont.resume(returning: img)
            }
        }
    }
}

// MARK: - Glass Badge

struct GlassBadge: View {
    let icon: String
    let text: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

// MARK: - Main View

struct ProfilePhotoEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var socialService = SocialService.shared
    @StateObject private var userService = UserService()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var rawPickedImage: UIImage?      // straight from picker — goes to crop
    @State private var selectedImage: UIImage?       // cropped result — goes to upload
    @State private var showCropView = false
    @State private var isUploading = false
    @State private var showCamera = false
    @State private var showDeleteConfirmation = false
    @State private var showSuccessMessage = false
    @State private var showPhotoPermissionAlert = false
    @State private var showCameraPermissionAlert = false
    @State private var photoPermissionDenied = false
    @State private var cameraPermissionDenied = false

    // Animation state
    @State private var photoCircleScale: CGFloat = 0.85
    @State private var bannerVisible = false
    @State private var bannerOffset: CGFloat = 20
    @State private var tipsVisible = false

    // A. Face detection
    @State private var faceDetectionState: FaceDetectionState = .idle

    // B. Pinch-to-zoom
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    // C. Quality warnings
    @State private var qualityWarnings: Set<PhotoQualityWarning> = []

    // D. Recent photos
    @State private var recentAssets: [PHAsset] = []
    @State private var selectedRecentAsset: PHAsset?

    let currentImageURL: String?
    let onPhotoUpdated: (String?) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                // Background — neutral, no jarring red
                Color(.secondarySystemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 36) {
                        // ── Photo Circle ──────────────────────────────────
                        photoCircleSection
                            .padding(.top, 52)

                        // ── Selected-photo banner ─────────────────────────
                        if selectedImage != nil {
                            selectedPhotoBanner
                        }

                        // ── D. Recent Photos Quick-Select ─────────────────
                        if !recentAssets.isEmpty {
                            recentPhotosRow
                        }

                        // ── Action Buttons ────────────────────────────────
                        actionButtonsRow
                            .padding(.horizontal, 24)

                        // ── Remove Photo (destructive, only when applicable) ──
                        if currentImageURL != nil && selectedImage == nil {
                            removePhotoButton
                                .padding(.horizontal, 24)
                        }

                        // ── Frosted Tips Card ─────────────────────────────
                        tipsFrostedCard
                            .padding(.horizontal, 24)

                        Spacer(minLength: 48)
                    }
                }

                // ── Success Banner Overlay ────────────────────────────────
                if showSuccessMessage {
                    VStack {
                        Spacer()
                        successBanner
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // ── Transparent nav bar ──────────────────────────────────────
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    pillNavButton(label: "Cancel", isAccent: false) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isUploading {
                        ProgressView()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    } else {
                        pillNavButton(
                            label: "Save",
                            isAccent: selectedImage != nil
                        ) {
                            uploadPhoto()
                        }
                        .disabled(selectedImage == nil)
                    }
                }
            }
            // ── Modals ───────────────────────────────────────────────────
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $rawPickedImage)
            }
            .fullScreenCover(isPresented: $showCropView) {
                if let raw = rawPickedImage {
                    ProfilePhotoCropView(
                        image: raw,
                        onCrop: { cropped in
                            zoomScale = 1.0
                            panOffset = .zero
                            selectedImage = cropped
                            showCropView = false
                        },
                        onCancel: {
                            rawPickedImage = nil
                            showCropView = false
                        }
                    )
                }
            }
            .sheet(isPresented: $showPhotoPermissionAlert) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    EmptyView()
                }
            }
            .alert("Photo Library Access Required", isPresented: $photoPermissionDenied) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") { openAppSettings() }
            } message: {
                Text("Please allow access to your photo library in Settings to choose a profile photo.")
            }
            .alert("Camera Access Required", isPresented: $cameraPermissionDenied) {
                Button("Cancel", role: .cancel) { }
                Button("Open Settings") { openAppSettings() }
            } message: {
                Text("Please allow camera access in Settings to take a profile photo.")
            }
            .alert("Remove Photo?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) { deletePhoto() }
            } message: {
                Text("Are you sure you want to remove your profile photo?")
            }
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            Task {
                if let data = try? await newPhoto?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        zoomScale = 1.0
                        panOffset = .zero
                        rawPickedImage = uiImage
                        showCropView = true
                    }
                }
            }
        }
        .onChange(of: rawPickedImage) { _, raw in
            // Camera path: ImagePicker sets rawPickedImage directly
            if raw != nil && !showCropView {
                zoomScale = 1.0
                panOffset = .zero
                showCropView = true
            }
        }
        .onChange(of: selectedImage) { _, newImage in
            if let newImage {
                withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.7))) {
                    photoCircleScale = 1.0
                }
                withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.7)).delay(0.1)) {
                    bannerVisible = true
                    bannerOffset = 0
                }
                // A + C: run face detection and quality checks concurrently
                Task {
                    async let _ = runFaceDetection(on: newImage)
                    async let _ = checkImageQuality(newImage)
                }
            } else {
                photoCircleScale = 0.85
                bannerVisible = false
                bannerOffset = 20
                faceDetectionState = .idle
                qualityWarnings = []
            }
        }
        .onAppear {
            // Tips stagger
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(Motion.adaptive(.easeOut(duration: 0.22))) {
                    tipsVisible = true
                }
            }
            // D: load recent photos
            Task { await loadRecentPhotos() }
        }
    }

    // MARK: - Photo Circle

    private var photoCircleSection: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                // Circle container
                Group {
                    if let selectedImage {
                        // B. Zoomable circle when a new photo is selected
                        ZoomableCircleView(
                            image: selectedImage,
                            diameter: 180,
                            zoomScale: $zoomScale,
                            panOffset: $panOffset
                        )
                    } else if let urlString = currentImageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 180, height: 180)
                                    .clipShape(Circle())
                            default:
                                glassPlaceholderCircle
                            }
                        }
                        .frame(width: 180, height: 180)
                    } else {
                        glassPlaceholderCircle
                    }
                }
                // Gradient stroke ring
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
                .scaleEffect(photoCircleScale)

                // Camera badge
                cameraBadge
                    .offset(x: 4, y: 4)
            }
            .frame(width: 180, height: 180)

            // Zoom hint + face/quality badges (only when photo is selected)
            if selectedImage != nil {
                Text("Pinch to zoom · Drag to reposition")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                // A. Face detection badge
                faceBadge
                    .transition(.scale(scale: 0.8).combined(with: .opacity))

                // C. Quality badges
                ForEach(Array(qualityWarnings), id: \.self) { warning in
                    qualityBadge(for: warning)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }

    // Placeholder circle — glass + breathe symbol
    private var glassPlaceholderCircle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 180, height: 180)

            if #available(iOS 18, *) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.systemScaled(72))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.breathe)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.systemScaled(72))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var cameraBadge: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)

            Image(systemName: "camera.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selected Photo Banner

    private var selectedPhotoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(15))
                .foregroundStyle(.green)
            Text("Photo selected — tap Save to update")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .opacity(bannerVisible ? 1 : 0)
        .offset(y: bannerOffset)
        .animation(
            Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.7)),
            value: bannerVisible
        )
    }

    // MARK: - Action Buttons Row

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            // Library button
            Button {
                requestPhotoLibraryPermission()
            } label: {
                glassActionLabel(icon: "photo.on.rectangle", text: "Library")
            }
            .buttonStyle(LocalGlassPillButtonStyle())

            // Camera button
            Button {
                requestCameraPermission()
            } label: {
                glassActionLabel(icon: "camera.fill", text: "Camera")
            }
            .buttonStyle(LocalGlassPillButtonStyle())
        }
    }

    private func glassActionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .semibold))
            Text(text)
                .font(AMENFont.semiBold(15))
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
    }

    // MARK: - Remove Photo Button

    private var removePhotoButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.systemScaled(15, weight: .semibold))
                Text("Remove Photo")
                    .font(AMENFont.semiBold(15))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.08), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Frosted Tips Card

    private var tipsFrostedCard: some View {
        let tips: [(icon: String, text: String, color: Color)] = [
            ("checkmark.circle.fill", "Use a clear, recent photo of yourself", .green),
            ("checkmark.circle.fill", "Face should be clearly visible", .green),
            ("checkmark.circle.fill", "Good lighting works best", .green),
            ("xmark.circle.fill",    "Avoid group photos", .red)
        ]

        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.systemScaled(15))
                    .foregroundStyle(.orange)
                Text("Photo Tips")
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
            }

            Divider()
                .opacity(0.4)

            // Staggered tip rows
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    HStack(spacing: 10) {
                        Image(systemName: tip.icon)
                            .font(.systemScaled(13))
                            .foregroundStyle(tip.color)
                            .frame(width: 18)

                        Text(tip.text)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(tipsVisible ? 1 : 0)
                    .offset(y: tipsVisible ? 0 : 8)
                    .animation(
                        Motion.adaptive(Motion.appearEase)
                            .delay(Double(index) * 0.08),
                        value: tipsVisible
                    )
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Success Banner

    private var successBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(18))
                .foregroundStyle(.green)
            Text("Profile photo updated!")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    // MARK: - Pill Nav Button

    private func pillNavButton(label: String, isAccent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(isAccent ? Color.accentColor : Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Handling

    private func requestPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            showPhotoPermissionAlert = true

        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        showPhotoPermissionAlert = true
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } else {
                        photoPermissionDenied = true
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            }

        case .denied, .restricted:
            photoPermissionDenied = true
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)

        @unknown default:
            photoPermissionDenied = true
        }
    }

    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            showCamera = true

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    } else {
                        cameraPermissionDenied = true
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
            }

        case .denied, .restricted:
            cameraPermissionDenied = true
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)

        @unknown default:
            cameraPermissionDenied = true
        }
    }

    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }

    // MARK: - Actions

    private func uploadPhoto() {
        guard let selectedImage = selectedImage else { return }

        isUploading = true

        // B. Apply zoom/pan crop before upload
        let finalImage = (zoomScale > 1.001 || panOffset.width != 0 || panOffset.height != 0)
            ? applyZoomCrop(to: selectedImage, diameter: 180)
            : selectedImage

        Task {
            do {
                let imageURL = try await socialService.uploadProfilePicture(finalImage)

                await MainActor.run {
                    isUploading = false

                    withAnimation {
                        showSuccessMessage = true
                    }

                    onPhotoUpdated(imageURL)

                    NotificationCenter.default.post(
                        name: Notification.Name("profilePhotoUpdated"),
                        object: nil,
                        userInfo: ["profileImageURL": imageURL]
                    )
                    dlog("✅ Posted profilePhotoUpdated notification with URL: \(imageURL)")

                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    dlog("❌ Error uploading photo: \(error)")

                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - B. Zoom/Pan Crop

    /// Renders the currently-visible portion of `image` given zoomScale + panOffset into a
    /// square UIImage matching the circle diameter at screen resolution.
    private func applyZoomCrop(to image: UIImage, diameter: CGFloat) -> UIImage {
        let scale = UIScreen.main.scale
        let outputSize = CGSize(width: diameter * scale, height: diameter * scale)

        UIGraphicsBeginImageContextWithOptions(outputSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        // Clip to circle
        ctx.addEllipse(in: CGRect(origin: .zero, size: outputSize))
        ctx.clip()

        // Destination rect: scaled image centered + panned
        let scaledSide = diameter * zoomScale * scale
        let drawX = (outputSize.width  - scaledSide) / 2 + panOffset.width  * scale
        let drawY = (outputSize.height - scaledSide) / 2 + panOffset.height * scale
        image.draw(in: CGRect(x: drawX, y: drawY, width: scaledSide, height: scaledSide))

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    // MARK: - A. Face Detection

    private func runFaceDetection(on image: UIImage) async {
        await MainActor.run {
            withAnimation { faceDetectionState = .running }
        }

        guard let cgImage = image.cgImage else {
            await MainActor.run {
                withAnimation { faceDetectionState = .noFace }
            }
            return
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
                        let faces = request.results as? [VNFaceObservation] ?? []
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    faceDetectionState = faces.isEmpty ? .noFace : .faceFound
                }
            }
        } catch {
            await MainActor.run {
                withAnimation { faceDetectionState = .noFace }
            }
        }
    }

    // MARK: - C. Quality Check

    private func checkImageQuality(_ image: UIImage) async {
        var warnings: Set<PhotoQualityWarning> = []

        let pixelWidth = image.size.width * image.scale
        if pixelWidth < 200 {
            warnings.insert(.lowResolution)
        }

        if let data = image.jpegData(compressionQuality: 0.9), data.count > 5_000_000 {
            warnings.insert(.largeFile)
        }

        await MainActor.run {
            withAnimation {
                qualityWarnings = warnings
            }
        }
    }

    // MARK: - D. Recent Photos Fetch

    private func loadRecentPhotos() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 5
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d", PHAssetMediaType.image.rawValue
        )

        let result = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        await MainActor.run { recentAssets = assets }
    }

    // MARK: - A. Face Badge

    @ViewBuilder
    private var faceBadge: some View {
        switch faceDetectionState {
        case .idle:
            EmptyView()
        case .running:
            GlassBadge(icon: "face.smiling",
                       text: "Checking for face…",
                       iconColor: .secondary)
        case .faceFound:
            GlassBadge(icon: "checkmark.circle.fill",
                       text: "Face detected",
                       iconColor: .green)
        case .noFace:
            GlassBadge(icon: "exclamationmark.triangle.fill",
                       text: "No face found — community photos work best with a face visible",
                       iconColor: .yellow)
        }
    }

    // MARK: - C. Quality Badge

    @ViewBuilder
    private func qualityBadge(for warning: PhotoQualityWarning) -> some View {
        switch warning {
        case .lowResolution:
            GlassBadge(icon: "exclamationmark.triangle.fill",
                       text: "Low resolution — try a higher quality photo",
                       iconColor: .orange)
        case .largeFile:
            GlassBadge(icon: "info.circle.fill",
                       text: "Large photo — will be compressed on upload",
                       iconColor: .blue)
        }
    }

    // MARK: - D. Recent Photos Row

    private var recentPhotosRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recents")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentAssets, id: \.localIdentifier) { asset in
                        RecentPhotoThumbnail(
                            asset: asset,
                            isSelected: selectedRecentAsset?.localIdentifier == asset.localIdentifier
                        ) { image in
                            selectedRecentAsset = asset
                            zoomScale = 1.0
                            panOffset = .zero
                            rawPickedImage = image
                            showCropView = true
                        }
                    }

                    // Library shortcut at end
                    Button {
                        requestPhotoLibraryPermission()
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .background(
                                Circle()
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
        }
    }

    private func deletePhoto() {
        isUploading = true

        Task {
            do {
                try await socialService.deleteProfilePicture()

                await MainActor.run {
                    isUploading = false

                    withAnimation {
                        showSuccessMessage = true
                    }

                    onPhotoUpdated(nil)

                    NotificationCenter.default.post(
                        name: Notification.Name("profilePhotoUpdated"),
                        object: nil,
                        userInfo: ["profileImageURL": ""]
                    )
                    dlog("✅ Posted profilePhotoUpdated notification (photo removed)")

                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    dlog("❌ Error deleting photo: \(error)")

                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Glass Pill Button Style

private struct LocalGlassPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(
                Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.88)),
                value: configuration.isPressed
            )
    }
}

// MARK: - Image Picker (Camera)

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ProfilePhotoEditView(
        currentImageURL: nil,
        onPhotoUpdated: { _ in }
    )
}
