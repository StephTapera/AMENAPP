// AmenAccessPassQRCodeView.swift
// AMENAPP — QR Code Display for Access Passes
//
// Uses CoreImage QR generation (same pattern as ShareCardGenerator).
// Raw token encoded in URL; tokenHash never exposed to client.

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AmenAccessPassQRCodeView: View {
    let pass: AmenAccessPassSummary
    let universalLink: String
    var onRevoke: (() -> Void)?
    var onRotateToken: (() -> Void)?

    @State private var isRotating = false
    @State private var rotateError: String?
    @State private var showRevokeConfirm = false
    @State private var copyFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // QR Code
                qrSection

                // Pass details
                detailsSection

                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Access Pass QR")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Revoke This Pass?", isPresented: $showRevokeConfirm) {
            Button("Revoke", role: .destructive) { onRevoke?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone with this QR code or link will lose access immediately.")
        }
    }

    private var qrSection: some View {
        VStack(spacing: 16) {
            if let qrImage = generateQR(from: universalLink) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .accessibilityLabel("QR code for \(pass.title)")
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                    .frame(width: 220, height: 220)
                    .overlay(
                        Text("QR unavailable")
                            .foregroundStyle(.secondary)
                    )
            }

            StatusBadgeView(status: pass.status)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pass.title)
                .font(.headline)

            if let host = pass.verifiedHostName {
                HStack(spacing: 4) {
                    Text(host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if pass.verifiedHostBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified")
                    }
                }
            }

            Label(pass.mode.accessStatusLabel, systemImage: "lock.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let exp = pass.expiresAt {
                Label("Expires \(exp.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("No expiration", systemImage: "infinity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            usesRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var usesRow: some View {
        HStack {
            Text("Uses")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let max = pass.maxUses {
                Text("\(pass.usesCount) / \(max)")
                    .font(.caption)
                    .fontWeight(.medium)
            } else {
                Text("\(pass.usesCount) (unlimited)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Copy link
            Button {
                UIPasteboard.general.string = universalLink
                copyFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copyFeedback = false
                }
            } label: {
                Label(copyFeedback ? "Copied!" : "Copy Link", systemImage: copyFeedback ? "checkmark" : "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Copy access pass link")

            // Share link
            ShareLink(item: URL(string: universalLink) ?? URL(fileURLWithPath: "/")) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Share access pass")

            // Rotate token
            Button {
                guard !isRotating else { return }
                isRotating = true
                Task {
                    do {
                        _ = try await AmenAccessPassService.shared.rotateAccessPassToken(accessPassId: pass.accessPassId)
                        AmenAccessPassAnalytics.shared.logTokenRotated(passId: pass.accessPassId)
                        isRotating = false
                        onRotateToken?()
                    } catch {
                        rotateError = error.localizedDescription
                        isRotating = false
                    }
                }
            } label: {
                HStack {
                    if isRotating { ProgressView() }
                    Label("Rotate Token", systemImage: "arrow.triangle.2.circlepath")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel("Rotate token — old QR and links stop working")

            if let err = rotateError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            // Revoke
            Button(role: .destructive) {
                showRevokeConfirm = true
            } label: {
                Label("Revoke Pass", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Revoke this access pass")
        }
    }

    // MARK: - QR Generation

    private func generateQR(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    let status: AmenAccessPassStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
            .accessibilityLabel("Status: \(status.displayName)")
    }

    private var badgeColor: Color {
        switch status {
        case .active:  return .green
        case .paused:  return .orange
        case .revoked: return .red
        case .expired: return .secondary
        }
    }
}
