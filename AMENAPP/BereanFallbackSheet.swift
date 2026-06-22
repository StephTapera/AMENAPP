//
//  BereanFallbackSheet.swift
//  AMENAPP
//
//  Bottom sheet fallback for the Berean AI Live Activity on devices
//  that do not support Dynamic Island (iPhone 14 and earlier) or when
//  the user has disabled Live Activities.
//  Styled in AMEN Liquid Glass: white background, black text, no purple.
//

import SwiftUI

struct BereanFallbackSheet: View {
    @ObservedObject var service = BereanLiveActivityService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: Header
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.black)
                        .frame(width: 32, height: 32)
                    Image(systemName: "cross.fill")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Berean AI")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Biblical insight")
                        .font(.systemScaled(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Phase indicator
                Group {
                    if service.fallbackState?.phase == .loading ||
                       service.fallbackState?.phase == .responding {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.black)
                    } else if service.fallbackState?.phase == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .font(.systemScaled(18))
                    } else if service.fallbackState?.phase == .error {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.systemScaled(18))
                    }
                }

                Button {
                    Task { await service.endActivity() }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.systemGray5)))
                }
            }

            // MARK: Post context
            if !service.fallbackPostPreview.isEmpty {
                Text("\"\(service.fallbackPostPreview)\"")
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
            }

            Divider()

            // MARK: Response body
            if service.fallbackState?.phase == .loading ||
               service.fallbackState?.phase == .responding {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7).tint(.black)
                    Text(service.fallbackState?.phase.statusText ?? "Loading…")
                        .font(.systemScaled(14))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
            } else if let text = service.fallbackState?.responseText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.systemScaled(15))
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            } else if service.fallbackState?.phase == .error {
                Text("Berean is unavailable right now. Please try again.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }

            // MARK: Scripture reference pills
            if let scriptures = service.fallbackState?.scriptures, !scriptures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(scriptures, id: \.self) { ref in
                            Text(ref)
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // MARK: Go Deeper CTA
            if service.fallbackState?.phase == .complete {
                Button {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .openBereanFromLiveActivity,
                        object: nil,
                        userInfo: [:]
                    )
                } label: {
                    Text("Go Deeper")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.black))
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
