import SwiftUI
import UIKit

struct AmenCommandLayerPermissionRecoveryContext: Identifiable, Equatable {
    let actionID: AmenCommandLayerActionID
    let permissionType: AmenCommandLayerPermissionType
    let status: AmenCommandLayerPermissionStatus

    var id: String {
        "\(actionID.rawValue)-\(permissionType.rawValue)"
    }
}

struct AmenCommandLayerPermissionRecoveryView: View {
    let context: AmenCommandLayerPermissionRecoveryContext

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: iconName)
                    .font(.system(size: 38, weight: .semibold))
                    .frame(width: 74, height: 74)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(context.status.recoveryMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    openSettings()
                } label: {
                    Label("Manage Access", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens Settings so you can manage Amen permissions")

                Button("Not Now") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .navigationTitle("Permission Needed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch context.permissionType {
        case .camera:
            return "Camera Access"
        case .photos:
            return "Photo Access"
        case .microphone:
            return "Microphone Access"
        case .files:
            return "File Access"
        }
    }

    private var iconName: String {
        switch context.permissionType {
        case .camera:
            return "camera"
        case .photos:
            return "photo.on.rectangle"
        case .microphone:
            return "mic"
        case .files:
            return "folder"
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
