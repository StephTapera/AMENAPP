//
//  ShareCardGenerator.swift
//  AMENAPP
//
//  Generates a shareable profile card image (avatar, name, username, QR code)
//  using ImageRenderer for a delightful share experience.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
struct ShareCardGenerator {

    /// Generate a shareable profile card as a UIImage.
    static func generateProfileCard(
        name: String,
        username: String,
        profileImageURL: String?,
        qrCodeURL: String = "https://amenapp.com"
    ) -> UIImage? {
        let cardView = ProfileShareCard(
            name: name,
            username: username,
            profileImageURL: profileImageURL,
            qrCodeURL: "\(qrCodeURL)/u/\(username)"
        )

        let renderer = ImageRenderer(content: cardView.frame(width: 380, height: 480))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

// MARK: - Profile Share Card View

private struct ProfileShareCard: View {
    let name: String
    let username: String
    let profileImageURL: String?
    let qrCodeURL: String

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("AMEN")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Image(systemName: "cross.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)

            Spacer()

            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                Text(name.prefix(1).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Name + username
            VStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("@\(username)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // QR Code
            if let qrImage = generateQRCode(from: qrCodeURL) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(12)
            }

            Text("Scan to connect on AMEN")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
        .frame(width: 380, height: 480)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(24)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
