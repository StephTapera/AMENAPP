// ONELiquidCameraView.swift
// ONE — Unified Liquid Glass camera capture surface.
// P2-C | Glass surfaces: capture button, format strip, top bar, privacy pill.
//        Matte rule: viewfinder content itself has NO glassEffect.
// Requires iOS 26 for glassEffect on controls.

import SwiftUI
import AVFoundation

// MARK: - Camera Session Manager

@MainActor
final class ONECameraSessionManager: NSObject, ObservableObject {
    @Published var authStatus: AVAuthorizationStatus = .notDetermined
    @Published var isCapturing = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back

    var onPhoto: ((Data) -> Void)?

    func setup() async {
        authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authStatus = granted ? .authorized : .denied
        }
        guard authStatus == .authorized else { return }
        await configureSession(position: .back)
    }

    func start() {
        guard authStatus == .authorized, !session.isRunning else { return }
        Task.detached { [session] in session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        Task.detached { [session] in session.stopRunning() }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func flip() async {
        let next: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        await configureSession(position: next)
        currentPosition = next
    }

    private func configureSession(position: AVCaptureDevice.Position) async {
        let s = session
        await Task.detached {
            s.beginConfiguration()
            s.inputs.forEach { s.removeInput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                let input  = try? AVCaptureDeviceInput(device: device),
                s.canAddInput(input)
            else {
                s.commitConfiguration()
                return
            }
            s.addInput(input)

            if !s.outputs.contains(where: { $0 is AVCapturePhotoOutput }) {
                let out = AVCapturePhotoOutput()
                if s.canAddOutput(out) { s.addOutput(out) }
            }
            s.commitConfiguration()
        }.value
    }
}

extension ONECameraSessionManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.onPhoto?(data)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

private final class ONECameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees this cast; guard surfaces any future regression cleanly.
        guard let pl = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("ONECameraPreviewUIView: layer is not AVCaptureVideoPreviewLayer — layerClass override broken")
        }
        return pl
    }
}

private struct ONECameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> ONECameraPreviewUIView {
        let view = ONECameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: ONECameraPreviewUIView, context: Context) {}
}

// MARK: - ONELiquidCameraView

@available(iOS 26.0, *)
struct ONELiquidCameraView: View {
    var onCapture: (Data, ONEMomentType, ONEPrivacyContract) -> Void = { _, _, _ in }

    @StateObject private var cameraManager = ONECameraSessionManager()
    @StateObject private var provenanceService = ProvenanceServiceBox()

    @State private var selectedFormat: ONEMomentType = .snap
    @State private var contract: ONEPrivacyContract = .dmDefault
    @State private var provenanceLabel: ONEProvenanceLabel = ONEProvenanceLabel(
        classification: .captured, confidence: 0.95,
        c2paPayload: nil, attestedAt: Date(), processorNote: "Viewfinder"
    )
    @State private var showFormatPicker = false
    @State private var showProvenanceTip = false
    @State private var captureFlash = false
    @State private var isHoldingCapture = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            viewfinder
            controlsOverlay
        }
        .ignoresSafeArea()
        .task { await cameraManager.setup(); cameraManager.start() }
        .onDisappear { cameraManager.stop() }
        .sheet(isPresented: $showFormatPicker) {
            ONEMomentFormatPickerView(selectedFormat: $selectedFormat, contract: $contract)
        }
        .onChange(of: selectedFormat) { _, f in
            contract = ONEMomentFormatPickerView(
                selectedFormat: $selectedFormat,
                contract: $contract
            ).defaultContract(for: f)
        }
    }

    // MARK: - Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        switch cameraManager.authStatus {
        case .authorized:
            #if targetEnvironment(simulator)
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.10), Color(white: 0.05)],
                    startPoint: .top, endPoint: .bottom
                ))
            #else
            ONECameraPreview(session: cameraManager.session)
                .transition(.opacity)
            #endif

        case .denied, .restricted:
            permissionDeniedView

        default:
            Color.black
        }

        // Capture flash overlay
        if captureFlash {
            Color.white.opacity(0.7).ignoresSafeArea()
        }
    }

    // MARK: - Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            provenanceBadge
                .padding(.trailing, ONE.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, ONE.Spacing.sm)
            formatStrip
            captureCluster
                .padding(.bottom, max(40, ONE.Spacing.xxl))
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: ONE.Spacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(ONE.Colors.glassWarm).interactive(), in: Circle())
            .accessibilityLabel("Close camera")

            Spacer()

            privacyPill

            Spacer()

            Button { Task { await cameraManager.flip() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .glassEffect(.regular.tint(ONE.Colors.glassWarm).interactive(), in: Circle())
            .accessibilityLabel("Flip camera")
        }
        .padding(.horizontal, ONE.Spacing.md)
        .padding(.top, 56)                  // below status bar / notch
        .padding(.bottom, ONE.Spacing.sm)
    }

    // MARK: Privacy pill

    private var privacyPill: some View {
        HStack(spacing: ONE.Spacing.xs) {
            Image(systemName: "lock.fill").font(.system(size: 10))
            Text(contract.audience.displayLabel)
                .font(.system(size: 12, weight: .semibold))
            Text("·").foregroundStyle(.secondary)
            Text(contract.lifetime.displayLabel)
                .font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ONE.Spacing.md)
        .padding(.vertical, ONE.Spacing.sm)
        .glassEffect(.regular.tint(ONE.Colors.glassWarm).interactive(), in: Capsule())
        .accessibilityLabel("Privacy: \(contract.audience.displayLabel), \(contract.lifetime.displayLabel)")
    }

    // MARK: Provenance badge

    private var provenanceBadge: some View {
        let cls = provenanceLabel.displayClassification
        return Button {
            showProvenanceTip = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showProvenanceTip = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: cls.icon).font(.system(size: 10))
                Text(cls.displayLabel).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, ONE.Spacing.sm)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(ONE.Colors.glassCool).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cls.accessibilityLabel)
        .overlay(alignment: .topTrailing) {
            if showProvenanceTip {
                Text(cls.accessibilityLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ONE.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.75))
                    )
                    .offset(y: -32)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: showProvenanceTip)
    }

    // MARK: Format strip

    private var formatStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ONE.Spacing.sm) {
                ForEach(ONEMomentType.pickableTypes.prefix(7), id: \.self) { format in
                    formatChip(format)
                }
                Button("More ›") { showFormatPicker = true }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, ONE.Spacing.sm)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Show all format types")
            }
            .padding(.horizontal, ONE.Spacing.md)
            .padding(.vertical, ONE.Spacing.sm)
        }
        .padding(.bottom, ONE.Spacing.md)
    }

    private func formatChip(_ format: ONEMomentType) -> some View {
        let isSelected = selectedFormat == format
        return Button {
            withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                selectedFormat = format
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: format.provenanceIcon).font(.system(size: 11))
                Text(format.displayName).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.amenGold : .white.opacity(0.8))
            .padding(.horizontal, ONE.Spacing.sm)
            .padding(.vertical, 6)
            .glassEffect(
                isSelected
                    ? .regular.tint(ONE.Colors.glassWarm).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(format.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Capture cluster

    private var captureCluster: some View {
        HStack(alignment: .center, spacing: ONE.Spacing.xl) {
            // Media picker placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("Choose from library")

            // Capture button
            captureButton

            // Format picker shortcut
            Button { showFormatPicker = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.tint(ONE.Colors.glassWarm).interactive(), in: Circle())
            .accessibilityLabel("Change moment format")
        }
    }

    private var captureButton: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                .frame(width: 80, height: 80)

            Circle()
                .fill(Color.white)
                .frame(width: 66, height: 66)
                .scaleEffect(cameraManager.isCapturing ? 0.88 : 1.0)
                .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: cameraManager.isCapturing)

            // Recording ring (shown during hold)
            if isHoldingCapture {
                Circle()
                    .stroke(ONE.Colors.ephemeralRed, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.15)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHoldingCapture {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                            isHoldingCapture = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) {
                        isHoldingCapture = false
                    }
                    triggerCapture()
                }
        )
        .onTapGesture { triggerCapture() }
        .accessibilityLabel("Capture \(selectedFormat.displayName)")
        .accessibilityHint("Tap to capture, hold for video")
    }

    // MARK: Permission denied

    private var permissionDeniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: ONE.Spacing.lg) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Camera Access Needed")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Text("ONE needs camera access to capture moments.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(ONE.Colors.privateIndigo)
            }
            .padding(ONE.Spacing.xl)
        }
    }

    // MARK: - Capture trigger

    private func triggerCapture() {
        #if targetEnvironment(simulator)
        // Simulator: return synthetic image data
        let placeholder = UIImage(systemName: "photo") ?? UIImage()
        let data = placeholder.pngData() ?? Data()
        handleCapturedPhoto(data)
        #else
        cameraManager.capturePhoto()
        cameraManager.onPhoto = { data in
            handleCapturedPhoto(data)
        }
        #endif
    }

    private func handleCapturedPhoto(_ data: Data) {
        // Brief flash effect
        withAnimation(.easeOut(duration: 0.05)) { captureFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.12)) { captureFlash = false }
        }

        // Analyze provenance on background
        Task {
            let label = await provenanceService.service.analyze(imageData: data)
            provenanceLabel = label
        }

        onCapture(data, selectedFormat, contract)
    }
}

// MARK: - Provenance service box (reference type for @StateObject)

private final class ProvenanceServiceBox: ObservableObject {
    let service = ONEProvenanceLabelService()
}
