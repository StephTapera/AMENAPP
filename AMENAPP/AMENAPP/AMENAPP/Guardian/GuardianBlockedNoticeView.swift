import SwiftUI

// MARK: - GuardianBlockedNoticeView
// Shown to the sender when their message was blocked. Gentle, not accusatory.

struct GuardianBlockedNoticeView: View {
    let reason: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(AmenTheme.Colors.textTertiary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            VStack(spacing: 8) {
                Text("Message Not Sent")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(reason)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Button("Got it") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AmenTheme.Colors.accentPrimary)
                }
                .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .background(AmenTheme.Colors.backgroundPrimary)
    }
}

// MARK: - CrisisResourceSheet
// Shown when supportResourcesAttached=true. Delivers help, not silence.

struct CrisisResourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let resources: [CrisisResource] = {
        let locale = CrisisResourceResolver.resolve()
        return CrisisResourceResolver.resources(for: .overwhelmedButSafe, locale: locale)
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("You're not alone. These resources are here for you.")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    ForEach(resources) { resource in
                        GuardianCrisisResourceCard(resource: resource)
                    }
                }
                .padding()
            }
            .navigationTitle("Support Resources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary)
        }
    }
}

private struct GuardianCrisisResourceCard: View {
    let resource: CrisisResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resource.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            if !resource.subtitle.isEmpty {
                Text(resource.subtitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.accentPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                }
        }
    }
}
