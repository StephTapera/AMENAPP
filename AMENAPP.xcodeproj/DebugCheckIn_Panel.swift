//
//  DebugCheckIn_Panel.swift
//  AMENAPP
//
//  Debug panel for testing daily check-in (remove in production)
//

import SwiftUI

struct DebugCheckIn_Panel: View {
    @ObservedObject var manager = DailyCheckIn_Manager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Current State") {
                    LabeledContent("Should Show Check-In", value: manager.shouldShowCheckIn ? "Yes" : "No")
                    LabeledContent("Has Answered Today", value: manager.hasAnsweredToday ? "Yes" : "No")
                    LabeledContent("User Answered Yes", value: manager.userAnsweredYes ? "Yes" : "No")
                }
                
                Section("Last Check-In") {
                    if let timestamp = UserDefaults.standard.object(forKey: "lastCheckInDate") as? Double {
                        let date = Date(timeIntervalSince1970: timestamp)
                        LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Answer", value: UserDefaults.standard.bool(forKey: "lastCheckInAnswer") ? "Yes" : "No")
                    } else {
                        Text("No check-in recorded yet")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Actions") {
                    Button("Reset Check-In") {
                        manager.reset()
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                    
                    Button("Simulate New Day") {
                        // Clear just the date
                        UserDefaults.standard.removeObject(forKey: "lastCheckInDate")
                        UserDefaults.standard.removeObject(forKey: "hasAnsweredToday")
                        manager.checkIfShouldShowCheckIn()
                        
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                    }
                    
                    Button("Force Show Check-In") {
                        manager.shouldShowCheckIn = true
                        dismiss()
                        
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.warning)
                    }
                }
                
                Section("Info") {
                    Text("Shake device to open this panel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Remember to remove this debug panel before production!")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Check-In Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Shake Gesture Extension

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

// MARK: - View Modifier for Shake Detection

struct ShakeDetector: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(action: action))
    }
}

// MARK: - Preview

#Preview {
    DebugCheckIn_Panel()
}
