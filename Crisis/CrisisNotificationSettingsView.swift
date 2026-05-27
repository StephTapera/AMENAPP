import SwiftUI

struct CrisisNotificationSettingsView: View {
    @StateObject private var service = CrisisIndicatorService()
    @State private var proactiveSupportEnabled = true
    @State private var emergencyContact = ""
    @State private var showContactField = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $proactiveSupportEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Proactive Support Offers")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Allow AMEN to send supportive check-ins when it detects you may need help.")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                .tint(Color(red: 0.40, green: 0.70, blue: 0.95))
                .onChange(of: proactiveSupportEnabled) { _, newValue in
                    Task { if newValue { await service.optInToProactiveSupport() } else { await service.optOutOfProactiveSupport() } }
                }
                .accessibilityLabel("Proactive support offers toggle")
            } header: {
                Text("Crisis Support").font(.custom("OpenSans-Bold", size: 13))
            } footer: {
                Text("AMEN monitors usage patterns to detect when you might benefit from support. Your data is never shared.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            Section {
                Button { showContactField.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Emergency Contact")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(emergencyContact.isEmpty ? "Not set" : "Contact saved")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                .accessibilityLabel("Set emergency contact")
                if showContactField {
                    TextField("Phone number or email", text: $emergencyContact)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .keyboardType(.phonePad)
                        .accessibilityLabel("Emergency contact")
                }
            } header: {
                Text("Emergency Contact").font(.custom("OpenSans-Bold", size: 13))
            } footer: {
                Text("Your emergency contact is stored securely and only accessed during crisis escalations with your consent.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            Section {
                Link(destination: URL(string: "https://988lifeline.org")!) {
                    HStack {
                        Image(systemName: "phone.fill").foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95))
                        Text("988 Suicide & Crisis Lifeline")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }
                .accessibilityLabel("988 Suicide and Crisis Lifeline")
            } header: {
                Text("Crisis Resources").font(.custom("OpenSans-Bold", size: 13))
            }
        }
        .navigationTitle("Crisis Support Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            service.startListening()
            proactiveSupportEnabled = service.supportStatus?.optedIntoProactiveSupport ?? true
        }
    }
}
