//
//  BereanFallbackSheet.swift
//  AMENAPP
//
//  Bottom sheet fallback for the Berean AI Live Activity on devices
//  without Dynamic Island (iPhone 14 and earlier).
//  Same layout as the expanded Dynamic Island view.
//

import SwiftUI

struct BereanFallbackSheet: View {
    @ObservedObject var service = BereanLiveActivityService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "cross.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Berean AI")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()

                if service.fallbackState?.phase == .loading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.purple)
                } else if service.fallbackState?.phase == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Post preview
            Text(service.fallbackPostPreview)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .lineLimit(1)

            Divider().background(Color.white.opacity(0.1))

            // Response
            if service.fallbackState?.phase == .loading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(.purple)
                    Text(service.fallbackState?.phase.statusText ?? "Loading...")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            } else {
                Text(service.fallbackState?.responseText ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
            }

            // Scripture pills
            if let scriptures = service.fallbackState?.scriptures, !scriptures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(scriptures, id: \.self) { ref in
                            Text(ref)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.purple.opacity(0.5)))
                        }
                    }
                }
            }

            Spacer()

            // Go Deeper button
            if service.fallbackState?.phase == .complete {
                Button {
                    dismiss()
                    // Navigate to full Berean UI
                    NotificationCenter.default.post(
                        name: .openBereanFromLiveActivity,
                        object: nil,
                        userInfo: [:]
                    )
                } label: {
                    Text("Go Deeper")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [.purple, Color(red: 0.4, green: 0.2, blue: 0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.06, green: 0.06, blue: 0.10))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
