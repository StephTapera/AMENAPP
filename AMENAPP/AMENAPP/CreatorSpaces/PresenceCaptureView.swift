// PresenceCaptureView.swift
// AMENAPP — Presence / Truth / Audio capture UI.
//
// Uses the existing MultiCamCaptureService for dual-cam.
// Falls back gracefully to WitnessCameraViewModel (single cam) if the
// device doesn't support AVCaptureMultiCamSession.

import SwiftUI
import AVFoundation

@MainActor
final class PresenceCaptureViewModel: ObservableObject {
    let mode: CSCaptureMode

    // Dual-cam
    private let multiCam = MultiCamCaptureService()

    // Capture state
    @Published var isSupported: Bool = false
    @Published var isConfigured: Bool = false
    @Published var isCapturing: Bool = false
    @Published var configError: String? = nil

    // Layout picker (Presence mode)
    @Published var frameLayout: CSFrameLayout = .pip

    // Context tags (optional, user-controlled)
    @Published var selectedEmotionTags: [String] = []

    // Result — set after capture, triggers compose sheet
    @Published var capturedDraft: CSAssetDraft? = nil

    // Layers for camera preview
    let backPreviewLayer: AVCaptureVideoPreviewLayer
    let frontPreviewLayer: AVCaptureVideoPreviewLayer

    init(mode: CSCaptureMode) {
        self.mode = mode
        self.backPreviewLayer  = multiCam.backPreviewLayer
        self.frontPreviewLayer = multiCam.frontPreviewLayer
    }

    func setup() async {
        isSupported = multiCam.isSupported
        guard isSupported else {
            configError = "Dual camera isn't available on this device. Using single camera."
            return
        }
        do {
            try await multiCam.configure()
            multiCam.startRunning()
            isConfigured = true
        } catch {
            configError = error.localizedDescription
        }
    }

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        if mode == .presence && isSupported && isConfigured {
            do {
                let (front, back) = try await multiCam.captureDualPhoto(backFlashMode: .auto)
                var draft = CSAssetDraft(type: .presence, captureMode: .presence)
                draft.frontImage   = front
                draft.backImage    = back
                draft.frameLayout  = frameLayout
                draft.emotionTags  = selectedEmotionTags
                capturedDraft = draft
            } catch {
                configError = error.localizedDescription
            }
        } else {
            // Single-cam fallback (Truth mode or unsupported device)
            capturedDraft = CSAssetDraft(
                type: mode == .truth ? .single : .single,
                captureMode: mode
            )
        }
    }

    func stop() {
        multiCam.stopRunning()
    }
}

// MARK: - View

struct PresenceCaptureView: View {
    let mode: CSCaptureMode
    @StateObject private var vm: PresenceCaptureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCompose = false

    init(mode: CSCaptureMode) {
        self.mode = mode
        _vm = StateObject(wrappedValue: PresenceCaptureViewModel(mode: mode))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mode == .presence {
                dualPreview
            } else {
                singleCamPlaceholder
            }

            overlayControls
        }
        .task { await vm.setup() }
        .onDisappear { vm.stop() }
        .fullScreenCover(item: $vm.capturedDraft) { draft in
            PresenceComposeView(draft: draft)
        }
        .alert("Camera Error", isPresented: .constant(vm.configError != nil), actions: {
            Button("OK") { vm.configError = nil }
        }, message: {
            Text(vm.configError ?? "")
        })
    }

    // MARK: Dual preview layout

    private var dualPreview: some View {
        GeometryReader { geo in
            ZStack {
                // Back camera (full background)
                CameraPreviewLayerView(layer: vm.backPreviewLayer)
                    .ignoresSafeArea()

                // Front camera overlay — size depends on layout
                frontOverlay(in: geo)
            }
        }
    }

    @ViewBuilder
    private func frontOverlay(in geo: GeometryProxy) -> some View {
        switch vm.frameLayout {
        case .pip:
            CameraPreviewLayerView(layer: vm.frontPreviewLayer)
                .frame(width: geo.size.width * 0.35, height: geo.size.width * 0.35 * 1.3)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 8)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

        case .split:
            VStack(spacing: 2) {
                CameraPreviewLayerView(layer: vm.backPreviewLayer)
                CameraPreviewLayerView(layer: vm.frontPreviewLayer)
            }
            .ignoresSafeArea()

        case .stacked:
            VStack(spacing: 2) {
                CameraPreviewLayerView(layer: vm.frontPreviewLayer)
                CameraPreviewLayerView(layer: vm.backPreviewLayer)
            }
            .ignoresSafeArea()
        }
    }

    private var singleCamPlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: mode.systemIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))
                Text(mode.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                if let err = vm.configError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
    }

    // MARK: Overlay controls

    private var overlayControls: some View {
        VStack {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                // Layout toggle (Presence only)
                if mode == .presence {
                    layoutToggleButton
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Bottom capture zone
            VStack(spacing: 20) {
                if !vm.selectedEmotionTags.isEmpty {
                    tagsRow
                }
                captureButton
            }
            .padding(.bottom, 48)
        }
    }

    private var layoutToggleButton: some View {
        Menu {
            ForEach(CSFrameLayout.allCases, id: \.self) { layout in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        vm.frameLayout = layout
                    }
                } label: {
                    Label(layout.displayName, systemImage: layout.systemIcon)
                }
            }
        } label: {
            Image(systemName: vm.frameLayout.systemIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.selectedEmotionTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var captureButton: some View {
        Button {
            Task { await vm.capture() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(vm.isCapturing ? Color.white.opacity(0.5) : Color.white)
                    .frame(width: 60, height: 60)
                    .scaleEffect(vm.isCapturing ? 0.85 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: vm.isCapturing)
            }
        }
        .disabled(vm.isCapturing)
    }
}

// MARK: - UIKit bridge for AVCaptureVideoPreviewLayer

struct CameraPreviewLayerView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = uiView.bounds
    }
}

// MARK: - CSAssetDraft Identifiable conformance for .fullScreenCover(item:)
extension CSAssetDraft: Identifiable {
    var id: String { "\(captureMode.rawValue)_\(caption)_\(Date().timeIntervalSince1970)" }
}
