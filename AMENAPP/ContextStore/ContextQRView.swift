// ContextQRView.swift
// AMEN Universal Migration & Context System — Wave 5 (qr-engineer)
//
// GlassKit view for the Context QR surface. Shows the user's public-context QR
// code, a share sheet action, and a scan affordance for reading another user's code.
//
// HARD INVARIANTS (C60 + frozen contracts):
//   • When service.isAvailableForCurrentUser is false (minor / C60 denial), renders
//     a clear "Context QR is not available for this account" state. The QR image is
//     NEVER rendered for minors — not blurred, not greyed-out, just absent.
//   • Gated on contextSystemEnabled && contextQREnabled. Nothing user-visible unless
//     both flags are true.
//   • The share action uses UIActivityViewController (system share sheet). It shares
//     the QR image only — no raw facet values are placed in the pasteboard/share.
//   • Single-layer glass only — no glass-on-glass.
//   • All animations through Motion.adaptive. No bare .animation() calls.
//   • No spiritual ranking anywhere.

import SwiftUI
import UIKit

struct ContextQRView: View {

    @StateObject private var service = ContextQRService.shared
    @StateObject private var flags   = AMENFeatureFlags.shared

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var qrImage:     UIImage?     = nil
    @State private var isGenerating              = false
    @State private var generationError: String?  = nil
    @State private var showScanner               = false
    @State private var resolvedProfile: ContextQRProfile? = nil
    @State private var showShareSheet            = false
    @State private var showResolvedSheet         = false

    // MARK: - Body

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextQREnabled {
                mainContent
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Context QR")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIfNeeded() }
    }

    // MARK: - Main content (flags on, availability checked inside)

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                if service.isAvailableForCurrentUser {
                    availableContent
                } else {
                    minorDeniedState
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showScanner) {
            ContextQRScannerView(
                onScanned: { token in
                    showScanner = false
                    Task { await resolveScannedToken(token) }
                },
                onCancel: { showScanner = false }
            )
        }
        .sheet(isPresented: $showResolvedSheet) {
            if let profile = resolvedProfile {
                ContextQRResolvedProfileView(profile: profile) {
                    showResolvedSheet = false
                }
            }
        }
    }

    // MARK: - C60 minor denied state (NEVER renders QR; clear message only)

    private var minorDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Context QR is not available for this account")
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Context QR is not available for this account")

            Text("Context QR codes are available for adult accounts only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Available content (adult, flags on)

    private var availableContent: some View {
        VStack(spacing: 20) {
            explanationHeader
            qrCard
            actionRow
            footnote
        }
    }

    // MARK: - Explanation header

    private var explanationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("PUBLIC CONTEXT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            Text("Your Context QR")
                .font(.largeTitle.weight(.bold))
            Text("Shares only the facets you've made public. Scan someone else's code to see their public profile. You can revoke access any time by changing your facets' visibility.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - QR card

    private var qrCard: some View {
        VStack(spacing: 16) {
            if isGenerating {
                qrLoadingState
            } else if let error = generationError {
                qrErrorState(error)
            } else if let image = qrImage {
                qrImageView(image)
            } else {
                qrEmptyState
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
    }

    private var qrLoadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 220)
        .accessibilityLabel("Generating your Context QR code")
    }

    private func qrErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await generate() }
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel("Try generating the QR code again")
        }
        .frame(minHeight: 220)
        .accessibilityElement(children: .combine)
    }

    private func qrImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous))
            .accessibilityLabel("Your Context QR code. Tap Share to share it.")
    }

    private var qrEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Your QR code will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 220)
        .accessibilityLabel("QR code not yet generated")
    }

    // MARK: - Action row (share + scan)

    private var actionRow: some View {
        HStack(spacing: 12) {
            // Share button — enabled only when a QR image is ready
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(qrImage == nil)
            .accessibilityLabel("Share your Context QR code")
            .accessibilityHint(qrImage == nil ? "Generate a QR code first." : "Opens the system share sheet.")
            .background(
                Group {
                    if let image = qrImage {
                        ShareSheet(activityItems: [image], isPresented: $showShareSheet)
                    }
                }
            )

            // Scan affordance
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.76))) {
                    showScanner = true
                }
            } label: {
                Label("Scan", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Scan another person's Context QR code")
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text("Only facets you've set to Public are encoded. Changing or privatising a facet takes effect immediately on the next scan — older printed codes resolve current visibility, not the state at print time.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Data loading

    private func loadIfNeeded() async {
        await service.refreshMinorStatus()
        guard service.isAvailableForCurrentUser else { return }
        if qrImage == nil, !isGenerating {
            await generate()
        }
    }

    private func generate() async {
        guard !isGenerating else { return }
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
            isGenerating = true
            generationError = nil
        }
        defer {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                isGenerating = false
            }
        }
        do {
            let image = try await service.generateQRCode()
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                qrImage = image
            }
        } catch let error as ContextQRError {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                generationError = error.localizedDescription
            }
        } catch {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                generationError = error.localizedDescription
            }
        }
    }

    private func resolveScannedToken(_ token: String) async {
        do {
            let profile = try await service.resolveToken(token)
            withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.76))) {
                resolvedProfile = profile
                showResolvedSheet = true
            }
        } catch let error as ContextQRError {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8))) {
                generationError = error.localizedDescription
            }
        } catch {
            // Non-fatal; let the user try again.
        }
    }
}

// MARK: - Resolved profile sheet

/// Presented when a scanned token is successfully resolved. Shows public-facet
/// summaries only — no raw values, no Tier-P data, no ranking.
struct ContextQRResolvedProfileView: View {
    let profile: ContextQRProfile
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Public profile")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text(profile.displayName)
                        .font(.title2.weight(.bold))

                    if profile.publicFacetsSummary.isEmpty {
                        Text("No public facets shared.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(profile.publicFacetsSummary, id: \.label) { facet in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(facet.label)
                                        .font(.subheadline.weight(.semibold))
                                        .frame(minWidth: 80, alignment: .leading)
                                    Text(facet.displaySummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
                    }

                    Text("This person chose to share these facets publicly. Nothing shown here is ranked.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Scanned Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
    }
}

// MARK: - Scanner stub

/// Camera-based QR scanner. Decodes `amen://context-qr?token=...` deep links.
struct ContextQRScannerView: View {
    let onScanned: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Point your camera at a Context QR code.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    // TODO(qr-scanner): Wire AVCaptureSession for live camera scanning.
                    // For now, a text field lets testers paste a token for verification.
                    TokenPasteField(onScanned: onScanned)
                }
                .padding(30)
            }
            .navigationTitle("Scan QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

/// Temporary paste-field for token testing. Replaced by live AVCaptureSession scanning.
private struct TokenPasteField: View {
    let onScanned: (String) -> Void
    @State private var tokenInput = ""

    var body: some View {
        VStack(spacing: 12) {
            TextField("Paste token here (testing)", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Token input for testing")
            Button("Resolve") {
                let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                // Accept either a raw token or a full amen://context-qr?token=... URL.
                let extracted = extractToken(from: trimmed)
                if !extracted.isEmpty { onScanned(extracted) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Resolve the pasted token")
        }
    }

    private func extractToken(from input: String) -> String {
        if input.hasPrefix("amen://context-qr?token="),
           let url = URL(string: input),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let tokenItem = components.queryItems?.first(where: { $0.name == "token" }),
           let value = tokenItem.value {
            return value
        }
        return input
    }
}

// MARK: - UIKit share sheet bridge

/// Thin SwiftUI bridge over UIActivityViewController.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented else { return }
        // Avoid presenting twice if already presenting.
        guard uiViewController.presentedViewController == nil else { return }
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in isPresented = false }
        uiViewController.present(vc, animated: true)
    }
}
