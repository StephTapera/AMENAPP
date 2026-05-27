import SwiftUI

enum AmenAppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "amen.appearance.preference"

    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func resolved(from rawValue: String) -> AmenAppearancePreference {
        AmenAppearancePreference(rawValue: rawValue) ?? .system
    }
}

struct AmenAppearanceSettingsView: View {
    @AppStorage(AmenAppearancePreference.storageKey) private var appearanceRaw = AmenAppearancePreference.system.rawValue

    private var selection: Binding<AmenAppearancePreference> {
        Binding(
            get: { AmenAppearancePreference.resolved(from: appearanceRaw) },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: selection) {
                    ForEach(AmenAppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("System follows your iPhone appearance. Light and Dark apply across Amen without changing media playback or privacy behavior.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AmenColor.background.ignoresSafeArea())
    }
}

#Preview("Appearance Settings - Light") {
    NavigationStack {
        AmenAppearanceSettingsView()
    }
    .preferredColorScheme(.light)
}

#Preview("Appearance Settings - Dark") {
    NavigationStack {
        AmenAppearanceSettingsView()
    }
    .preferredColorScheme(.dark)
}
