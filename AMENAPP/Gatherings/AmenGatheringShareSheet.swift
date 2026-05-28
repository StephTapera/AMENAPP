// AmenGatheringShareSheet.swift
// AMENAPP — Gathering Share Sheet + QR Code
//
// Shows QR code, share link, copy link.
// QR code generated client-side from the access pass qrPayload (set during create).
// Token never exposed raw — only the opaque payload string is shown.

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AmenGatheringShareSheet: View {
    let gathering: AmenGathering

    @Environment(\.dismiss) private var dismiss
    @State private var shareLink: String?
    @State private var qrPayload: String?
    @State private var isLoading = true
    @State private var copiedLink = false
    @State private var showSystemShare = false

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerInfo

                    if flags.gatheringQRShareEnabled, let payload = qrPayload {
                        qrSection(payload: payload)
                    } else if isLoading {
                        ProgressView("Generating pass...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }

                    if let link = shareLink {
                        shareLinkSection(link)
                    }

                    nativShareButton

                    privacyNote
                }
                .padding(20)
            }
            .navigationTitle("Invite People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSystemShare) {
                if let link = shareLink {
                    SystemShareSheet(items: [gathering.title, URL(string: link) as Any].compactMap { $0 })
                }
            }
            .task { await loadPassInfo() }
        }
    }

    // MARK: - Header

    private var headerInfo: some View {
        VStack(spacing: 8) {
            Image(systemName: gathering.type.systemImage)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(gathering.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text(gathering.startAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - QR Section

    private func qrSection(payload: String) -> some View {
        VStack(spacing: 12) {
            Text("Scan to Join")
                .font(.subheadline.weight(.semibold))

            if let qrImage = generateQR(from: payload) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                    .accessibilityLabel("QR code for \(gathering.title)")
            }

            Text("Point a camera at this code to join the gathering.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Share Link Section

    private func shareLinkSection(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share Link")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Text(link)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = link
                    copiedLink = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedLink = false
                    }
                } label: {
                    Image(systemName: copiedLink ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copiedLink ? .green : .secondary)
                }
                .accessibilityLabel(copiedLink ? "Copied!" : "Copy link")
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Native Share

    private var nativShareButton: some View {
        Button {
            showSystemShare = true
        } label: {
            Label("Share via Messages, Email & More", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share this gathering")
    }

    // MARK: - Privacy Note

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Invite links are validated by the Amen server.", systemImage: "lock.shield")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Scanning or opening a link will show a safe preview before joining — no one is added automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - QR Generation

    private func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Load Pass Info

    private func loadPassInfo() async {
        defer { isLoading = false }
        guard let passId = gathering.access.defaultAccessPassId else {
            // No pass yet — show link only
            shareLink = "https://amen.app/gathering/\(gathering.gatheringId)"
            return
        }
        do {
            let passes = try await AmenAccessPassService.shared.listAccessPassesForTarget(
                targetType: .event,
                targetId: gathering.gatheringId
            )
            if let pass = passes.first(where: { $0.accessPassId == passId }) {
                shareLink = pass.lastUsedAt != nil ? "https://amen.app/access/\(passId)" : nil
            }
        } catch {
            shareLink = "https://amen.app/gathering/\(gathering.gatheringId)"
        }
    }
}

// MARK: - System Share Sheet Wrapper

private struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
