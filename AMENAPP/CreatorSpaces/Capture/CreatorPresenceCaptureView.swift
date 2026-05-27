import SwiftUI

struct CreatorPresenceCaptureView: View {
    @StateObject private var controller = CreatorPresenceCaptureController()
    @State private var layout: CreatorFrameLayout = .pip
    @State private var mode: CreatorPresenceCaptureMode = .photo
    @State private var isUploading = false
    @State private var uploadResult: CreatorPresenceUploadResult?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if controller.isConfigured {
                CreatorPresencePreviewView(session: controller.session)
                    .ignoresSafeArea()
                    .accessibilityLabel("Presence camera preview")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 42, weight: .semibold))
                    Text(controller.errorMessage ?? "Preparing camera")
                        .font(AMENFont.semiBold(16))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(24)
            }

            PresenceCaptureHUD(
                isDualCameraActive: controller.isDualCameraActive,
                isThermalConstrained: controller.isThermalConstrained,
                isUploading: isUploading,
                layout: $layout,
                mode: $mode,
                onCapture: { Task { await captureAndUpload() } }
            )
            .padding(18)
        }
        .navigationTitle("Presence Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await controller.requestAndConfigure()
            controller.start()
        }
        .onDisappear { controller.stop() }
        .alert("Presence Post", isPresented: Binding(get: { uploadResult != nil }, set: { if !$0 { uploadResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Captured and queued for provenance and moderation.")
        }
        .alert("Capture unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func captureAndUpload() async {
        guard !isUploading else { return }
        guard mode == .photo else {
            errorMessage = "Video capture is gated for the next capture workstream. Photo Presence Posts are available now."
            return
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let capture = try await controller.capturePhoto()
            uploadResult = try await CreatorPresenceCaptureUploadService.shared.upload(capture, layout: layout)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PresenceCaptureHUD: View {
    let isDualCameraActive: Bool
    let isThermalConstrained: Bool
    let isUploading: Bool
    @Binding var layout: CreatorFrameLayout
    @Binding var mode: CreatorPresenceCaptureMode
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                statusPill(
                    isDualCameraActive ? "Dual camera" : "Single camera",
                    systemImage: isDualCameraActive ? "camera.on.rectangle" : "camera",
                    isWarning: !isDualCameraActive
                )
                if isThermalConstrained {
                    statusPill("Cooling", systemImage: "thermometer.high", isWarning: true)
                }
                Spacer()
            }

            Picker("Mode", selection: $mode) {
                ForEach(CreatorPresenceCaptureMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isUploading)

            Picker("Layout", selection: $layout) {
                ForEach(CreatorFrameLayout.allCases, id: \.self) { layout in
                    Text(layout.rawValue.uppercased()).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isUploading || !isDualCameraActive)

            Button(action: onCapture) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                    Circle()
                        .stroke(Color.black.opacity(0.22), lineWidth: 3)
                        .frame(width: 54, height: 54)
                    if isUploading {
                        ProgressView()
                            .tint(.black)
                    }
                }
            }
            .disabled(isUploading || isThermalConstrained)
            .accessibilityLabel("Capture Presence Post")
        }
        .padding(16)
        .amenGlassSurface(shape: .rounded(28), background: .balanced, placement: .floating)
    }

    private func statusPill(_ text: String, systemImage: String, isWarning: Bool) -> some View {
        Label(text, systemImage: systemImage)
            .font(AMENFont.semiBold(12))
            .foregroundStyle(isWarning ? Color.orange : Color.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .amenGlassSurface(shape: .capsule, background: .quiet, placement: .inline)
    }
}

#Preview {
    NavigationStack { CreatorPresenceCaptureView() }
}
