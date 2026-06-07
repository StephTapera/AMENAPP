// BereanProfileSheet.swift
// AMEN App — Berean profile + account sheet.
//
// Design reference: ChatGPT profile drawer (IMG_2398) · translated to AMEN Liquid Glass.
// Sections: avatar (initials + pencil) · Customize Berean · Account · Appearance.
// Presented as .sheet with .large detent.

import SwiftUI
import FirebaseAuth

// MARK: - BereanProfileSheet

struct BereanProfileSheet: View {

    @Binding var isPresented: Bool

    // MARK: Appearance preference

    @AppStorage("berean_appearance") private var appearanceRaw = "system"
    @AppStorage("berean_memory_enabled") private var memoryEnabled = true
    @AppStorage("berean_explicit_protection") private var safeMode = true

    @State private var showAlignmentSettings = false
    @State private var showUpgradeSheet = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - User info

    private var currentUser: FirebaseAuth.User? { Auth.auth().currentUser }

    private var displayName: String {
        currentUser?.displayName ?? "Berean User"
    }

    private var email: String {
        currentUser?.email ?? ""
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").map(String.init)
        if parts.count >= 2,
           let f = parts[0].first, let s = parts[1].first {
            return "\(f)\(s)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    private var subscriptionLabel: String { "Free" }

    private let bgColor = Color(red: 0.971, green: 0.971, blue: 0.969)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            bgColor.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    avatarSection
                        .padding(.top, 56)

                    customizeSection

                    accountSection

                    appearanceSection

                    Spacer().frame(height: 48)
                }
                .padding(.horizontal, 18)
            }

            // Dismiss X
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .background(glassCircle)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel("Close profile")
        }
        .sheet(isPresented: $showAlignmentSettings) {
            BereanAlignmentSettingsView()
        }
        .alert("Upgrade to Amen+", isPresented: $showUpgradeSheet) {
            Button("Learn More", role: .cancel) {}
        } message: {
            Text("Unlock unlimited Berean conversations and premium features.")
        }
    }

    // MARK: - Avatar section

    private var avatarSection: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.30, blue: 0.90).opacity(0.14),
                                Color(red: 0.25, green: 0.55, blue: 0.95).opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.80), lineWidth: 1.5)
                    )
                    .overlay(
                        Text(initials)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.90))
                    )
                    .shadow(color: Color(red: 0.35, green: 0.30, blue: 0.90).opacity(0.12), radius: 14, y: 4)

                // Edit badge
                Circle()
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Circle().fill(Color.white.opacity(0.88)))
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.black.opacity(0.72))
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.90), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            }

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)

                if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.black.opacity(0.48))
                }
            }
        }
    }

    // MARK: - Customize Berean

    private var customizeSection: some View {
        profileSection(title: "Customize Berean") {
            chevronRow(icon: "person.badge.shield.checkmark", label: "Theology Alignment",
                       tint: Color(red: 0.35, green: 0.30, blue: 0.90)) {
                showAlignmentSettings = true
            }
            Divider().padding(.leading, 52)
            toggleRow(icon: "brain", label: "Memory",
                      tint: Color(red: 0.30, green: 0.65, blue: 0.50),
                      value: $memoryEnabled)
            Divider().padding(.leading, 52)
            toggleRow(icon: "shield", label: "Safe Mode",
                      tint: Color(red: 0.85, green: 0.40, blue: 0.20),
                      value: $safeMode)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        profileSection(title: "Account") {
            infoRow(icon: "envelope", label: "Email",
                    value: email.isEmpty ? "—" : email,
                    tint: Color(red: 0.35, green: 0.30, blue: 0.90))
            Divider().padding(.leading, 52)
            infoRow(icon: "creditcard", label: "Subscription",
                    value: subscriptionLabel,
                    tint: Color(red: 0.35, green: 0.30, blue: 0.90))
            Divider().padding(.leading, 52)
            upgradeRow
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        profileSection(title: "Theme") {
            HStack(spacing: 14) {
                iconBadge("sun.max", tint: Color(red: 0.85, green: 0.62, blue: 0.10))
                Text("Appearance")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                Spacer()
                Menu {
                    Button("System") { appearanceRaw = "system" }
                    Button("Light")  { appearanceRaw = "light" }
                    Button("Dark")   { appearanceRaw = "dark" }
                } label: {
                    HStack(spacing: 4) {
                        Text(appearanceLabel)
                            .font(.system(size: 14))
                            .foregroundColor(.black.opacity(0.42))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.black.opacity(0.28))
                    }
                }
                .foregroundColor(.black)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var appearanceLabel: String {
        switch appearanceRaw {
        case "light": return "Light"
        case "dark":  return "Dark"
        default:      return "System"
        }
    }

    // MARK: - Row builders

    private func chevronRow(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconBadge(icon, tint: tint)
                Text(label)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.28))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, label: String, tint: Color, value: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, tint: tint)
            Text(label)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.black)
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(Color(red: 0.35, green: 0.30, blue: 0.90))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func infoRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            iconBadge(icon, tint: tint)
            Text(label)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.black)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black.opacity(0.42))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var upgradeRow: some View {
        Button { showUpgradeSheet = true } label: {
            HStack(spacing: 14) {
                iconBadge("crown", tint: Color(red: 0.85, green: 0.58, blue: 0.08))
                Text("Upgrade to Amen+")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.78, green: 0.50, blue: 0.06))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section wrapper

    @ViewBuilder
    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.42))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Reusable icon badge

    private func iconBadge(_ name: String, tint: Color) -> some View {
        Circle()
            .fill(tint.opacity(0.12))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tint)
            )
    }

    // MARK: - Glass circle (dismiss button background)

    private var glassCircle: some View {
        Circle()
            .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(Circle().fill(Color.white.opacity(0.52)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
