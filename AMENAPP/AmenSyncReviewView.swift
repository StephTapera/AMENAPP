// AmenSyncReviewView.swift
// AMEN Sync — Review & Publish Screen
// Per-platform variant review with safety status

import SwiftUI

struct AmenSyncReviewView: View {
    @ObservedObject var vm: AmenSyncViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVariantForEdit: AmenSyncVariant?
    @State private var publishSucceeded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if publishSucceeded {
                    publishSuccessView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Review & Publish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary card
                    summaryCard
                        .padding(.top, 16)

                    // Safety status
                    safetyCard

                    // Variant cards
                    variantsSection

                    // Platforms with no variant yet
                    if vm.variants.isEmpty {
                        emptyVariantsState
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 20)
            }

            // Publish bar
            publishBar
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(.teal)
                Text("Ready to Distribute")
                    .font(.custom("OpenSans-Bold", size: 17))
                Spacer()
            }

            HStack(spacing: 16) {
                statBadge(value: "\(vm.variants.count)", label: "Versions")
                statBadge(value: "\(vm.selectedPlatformCount)", label: "Platforms")
                statBadge(value: vm.assets.isEmpty ? "Text" : "\(vm.assets.count) media", label: "Assets")
            }

            if !vm.caption.isEmpty {
                Text(vm.caption)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.teal.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.teal.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("OpenSans-Bold", size: 16))
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.07))
        )
    }

    // MARK: - Safety Card

    private var safetyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: moderationIcon)
                .font(.system(size: 22))
                .foregroundStyle(moderationColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(moderationTitle)
                    .font(.custom("OpenSans-Bold", size: 14))
                Text(moderationSubtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if vm.isModerating {
                ProgressView().scaleEffect(0.8)
            } else {
                Button {
                    Task { await vm.runModeration() }
                } label: {
                    Text("Re-check")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(moderationColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(moderationColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var moderationIcon: String {
        switch vm.moderationStatus {
        case .approved: return "checkmark.shield.fill"
        case .flagged:  return "exclamationmark.shield.fill"
        case .rejected: return "xmark.shield.fill"
        default:        return "shield.fill"
        }
    }

    private var moderationColor: Color {
        switch vm.moderationStatus {
        case .approved: return .green
        case .flagged:  return .orange
        case .rejected: return .red
        default:        return .gray
        }
    }

    private var moderationTitle: String {
        switch vm.moderationStatus {
        case .approved: return "Content approved"
        case .flagged:  return "Review recommended"
        case .rejected: return "Content blocked"
        default:        return "Pending review"
        }
    }

    private var moderationSubtitle: String {
        switch vm.moderationStatus {
        case .approved: return "All safety checks passed"
        case .flagged:  return "Some content may need revision"
        case .rejected: return "Content cannot be published as-is"
        default:        return "Run safety check before publishing"
        }
    }

    // MARK: - Variants Section

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distribution Versions")
                .font(.custom("OpenSans-Bold", size: 17))

            ForEach(vm.publishableVariants) { variant in
                ReviewVariantCard(
                    variant: variant,
                    onEdit: { selectedVariantForEdit = variant }
                )
            }
        }
    }

    private var emptyVariantsState: some View {
        VStack(spacing: 16) {
            CreationEmptyState(
                icon: "arrow.triangle.2.circlepath",
                title: "Preparing Versions",
                message: "AMEN Sync is generating platform-specific versions. This only takes a moment.",
                actionLabel: nil, action: nil
            )

            if vm.isPreparing {
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Publish Bar

    private var publishBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                if vm.isPublishing {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.85)
                        Text("Publishing to AMEN...")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            await vm.publish(selectedVariants: vm.publishableVariants)
                            if case .published = vm.projectState {
                                publishSucceeded = true
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16))
                            Text("Publish to AMEN")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(vm.moderationStatus == .rejected ? Color.gray.opacity(0.3) : Color.black)
                        )
                    }
                    .disabled(vm.moderationStatus == .rejected || vm.isPublishing)
                    .padding(.horizontal, 20)

                    if !vm.publishableVariants.isEmpty {
                        Button {
                            shareSheet()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14))
                                Text("Export All Versions")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
    }

    private func shareSheet() {
        // Build share items from variants
        let items: [Any] = vm.publishableVariants.compactMap { v -> URL? in
            guard let urlStr = v.mediaURL, let url = URL(string: urlStr) else { return nil }
            return url
        }
        guard !items.isEmpty else { return }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            window.rootViewController?.present(av, animated: true)
        }
    }

    // MARK: - Success View

    private var publishSuccessView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                }
                .scaleEffect(publishSucceeded ? 1 : 0.5)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: publishSucceeded)

                VStack(spacing: 8) {
                    Text("Published!")
                        .font(.custom("OpenSans-Bold", size: 26))
                    Text("Your content is live on AMEN.\nAll \(vm.variants.count) versions are ready.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            GlassCreationButton(label: "Done", icon: nil, style: .primary) {
                dismiss()
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Review Variant Card

struct ReviewVariantCard: View {
    let variant: AmenSyncVariant
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Platform icon
                ZStack {
                    Circle()
                        .fill(variant.platform.iconColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: variant.platform.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(variant.platform.iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.platform.displayName)
                        .font(.custom("OpenSans-Bold", size: 14))

                    HStack(spacing: 6) {
                        StatusPill(status: variant.status)
                        if variant.aiCaption {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9))
                                Text("AI Caption")
                                    .font(.custom("OpenSans-Regular", size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.gray.opacity(0.08)))
                        }
                    }
                }

                Spacer()

                Button(action: onEdit) {
                    Text("Edit")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
            }

            if !variant.caption.isEmpty {
                Text(variant.caption)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            if !variant.hashtags.isEmpty {
                Text(variant.hashtags.map { "#\($0)" }.joined(separator: " "))
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: SyncVariantStatus

    var label: String {
        switch status {
        case .pending:   return "Pending"
        case .adapting:  return "Adapting"
        case .ready:     return "Ready"
        case .approved:  return "Approved"
        case .published: return "Published"
        case .failed:    return "Failed"
        }
    }

    var color: Color {
        switch status {
        case .pending:   return .gray
        case .adapting:  return .orange
        case .ready:     return .blue
        case .approved:  return .green
        case .published: return .teal
        case .failed:    return .red
        }
    }

    var body: some View {
        Text(label)
            .font(.custom("OpenSans-SemiBold", size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.1)))
    }
}
