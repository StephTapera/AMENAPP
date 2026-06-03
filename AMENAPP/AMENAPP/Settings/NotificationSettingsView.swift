// NotificationSettingsView.swift
// AMENAPP — Settings
//
// Settings screen that lets users customise the notification display style
// for each of the five AMEN actions.
//
// Presented from the app's main Settings flow.  No coordinator imports
// beyond NotifPrefs (which self-injects into the coordinator).

import SwiftUI

// MARK: - NotificationSettingsView

struct NotificationSettingsView: View {

    // MARK: - State

    @ObservedObject private var prefs = NotifPrefs.shared
    @State private var showingResetAlert = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Per-action style pickers
                Section {
                    ForEach(AmenAction.allCases, id: \.rawValue) { action in
                        ActionStyleRow(action: action, prefs: prefs)
                    }
                } header: {
                    Text("Notification Style")
                } footer: {
                    Text("Smart = full card first time, quick toast after")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: Reset section
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset What I've Seen")
                                .foregroundStyle(Color(hex: "#C9A84C"))
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("Reset what I've seen")
                    .accessibilityHint("Clears the record of which cards you have already seen. Educational cards will reappear.")
                } footer: {
                    Text("Educational cards will reappear after resetting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notification Style")
            .navigationBarTitleDisplayMode(.large)
            .alert("Reset Seen History?", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) {
                    NotificationCoordinator.shared.resetSeen()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Educational notification cards will reappear for all actions.")
            }
        }
    }
}

// MARK: - ActionStyleRow

/// A single row in the notification preferences list.
/// Displays the action icon, display name, and a picker for the style override.
private struct ActionStyleRow: View {

    let action: AmenAction
    @ObservedObject var prefs: NotifPrefs

    var body: some View {
        HStack(spacing: 14) {
            // Action icon
            ZStack {
                Circle()
                    .fill(iconGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: action.systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0D0D1A"))
            }
            .accessibilityHidden(true)

            // Display name + picker
            Picker(
                selection: Binding(
                    get: { prefs.style(for: action) },
                    set: { prefs.set($0, for: action) }
                ),
                label: Text(action.settingsDisplayName)
                    .font(.body)
            ) {
                Text("Smart")            .tag(NotifStyleOverride.smart)
                Text("Always Show Card") .tag(NotifStyleOverride.alwaysCard)
                Text("Toast Only")       .tag(NotifStyleOverride.toastOnly)
                Text("Off")              .tag(NotifStyleOverride.off)
            }
            .pickerStyle(.menu)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.settingsDisplayName), style: \(prefs.style(for: action).settingsDisplayName)")
        .accessibilityHint("Double-tap to change notification style for this action.")
    }

    // MARK: - Icon gradient

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#C9A84C"), Color(hex: "#7B68EE")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - AmenAction + settingsDisplayName

extension AmenAction {
    /// Longer display name shown in the Settings list.
    fileprivate var settingsDisplayName: String {
        switch self {
        case .amen:   return "Amen (Pray With)"
        case .repost: return "Repost"
        case .save:   return "Save"
        case .join:   return "Join Sanctuary"
        case .give:   return "Give"
        }
    }
}

// MARK: - NotifStyleOverride + settingsDisplayName

extension NotifStyleOverride {
    /// Human-readable label for the current style, used in accessibility strings.
    fileprivate var settingsDisplayName: String {
        switch self {
        case .smart:      return "Smart"
        case .alwaysCard: return "Always Show Card"
        case .toastOnly:  return "Toast Only"
        case .off:        return "Off"
        }
    }
}

// MARK: - Preview

#Preview("NotificationSettingsView") {
    NotificationSettingsView()
}
