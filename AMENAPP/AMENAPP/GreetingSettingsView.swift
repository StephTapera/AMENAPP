//
//  GreetingSettingsView.swift
//  AMENAPP
//
//  Settings panel for personalized greeting preferences
//

import SwiftUI

struct GreetingSettingsView: View {
    @ObservedObject private var greetingService = GreetingService.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var showBirthdayPicker = false
    @State private var selectedBirthday = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                // Preview section
                previewSection
                
                // Basic personalization
                basicSettingsSection
                
                // Advanced options
                advancedSettingsSection
                
                // Birthday
                birthdaySection
                
                // Info
                infoSection
            }
            .navigationTitle("Personalized Greeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
        .onAppear {
            loadBirthday()
        }
    }
    
    // MARK: - Sections
    
    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                // Live preview
                HStack(spacing: 12) {
                    Image(systemName: greetingIconForType(greetingService.currentGreeting.type))
                        .font(.system(size: 28))
                        .foregroundStyle(.black.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingService.currentGreeting.text)
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.black)
                        
                        Text("This is how your greeting will appear")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var basicSettingsSection: some View {
        Section {
            Toggle(isOn: $greetingService.useFirstName) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use my first name")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Personalize greeting with your name")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: greetingService.useFirstName) { _, _ in
                greetingService.updateGreeting()
                HapticManager.impact(style: .light)
            }
            
            Toggle(isOn: $greetingService.useLocalTime) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use local time")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Show Morning, Afternoon, or Evening")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: greetingService.useLocalTime) { _, _ in
                greetingService.updateGreeting()
                HapticManager.impact(style: .light)
            }
        } header: {
            Text("Personalization")
        }
    }
    
    private var advancedSettingsSection: some View {
        Section {
            Toggle(isOn: $greetingService.showFaithBased) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Faith-based greetings")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Show occasional Sunday and holiday greetings")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: greetingService.showFaithBased) { _, _ in
                greetingService.updateGreeting()
                HapticManager.impact(style: .light)
            }
        } header: {
            Text("Special Occasions")
        }
    }
    
    private var birthdaySection: some View {
        Section {
            Toggle(isOn: $greetingService.useBirthday) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Birthday greeting")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Show special greeting on your birthday")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: greetingService.useBirthday) { _, newValue in
                if newValue && greetingService.userBirthdayString.isEmpty {
                    showBirthdayPicker = true
                }
                greetingService.updateGreeting()
                HapticManager.impact(style: .light)
            }
            
            if greetingService.useBirthday {
                Button {
                    showBirthdayPicker = true
                } label: {
                    HStack {
                        Text("Birthday")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text(birthdayDisplayText)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        } header: {
            Text("Birthday")
        } footer: {
            Text("Your birthday is only used for the greeting and is stored locally on your device.")
                .font(.custom("OpenSans-Regular", size: 12))
        }
        .sheet(isPresented: $showBirthdayPicker) {
            birthdayPickerSheet
        }
    }
    
    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("About Personalized Greetings")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                
                Text("AMEN can personalize your home greeting using your first name, local time, and optional birthday. All personalization data is stored locally on your device and never shared.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var birthdayPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Birthday",
                    selection: $selectedBirthday,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showBirthdayPicker = false
                    }
                    .font(.custom("OpenSans-Regular", size: 15))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveBirthday()
                        showBirthdayPicker = false
                    }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Helpers
    
    private var birthdayDisplayText: String {
        if greetingService.userBirthdayString.isEmpty {
            return "Not Set"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let birthday = formatter.date(from: greetingService.userBirthdayString) else {
            return "Not Set"
        }
        
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: birthday)
    }
    
    private func loadBirthday() {
        if !greetingService.userBirthdayString.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let birthday = formatter.date(from: greetingService.userBirthdayString) {
                selectedBirthday = birthday
            }
        }
    }
    
    private func saveBirthday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        greetingService.userBirthdayString = formatter.string(from: selectedBirthday)
        greetingService.updateGreeting()
        HapticManager.notification(type: .success)
    }
    
    private func greetingIconForType(_ type: GreetingType) -> String {
        switch type {
        case .morning:
            return "sunrise.fill"
        case .afternoon:
            return "sun.max.fill"
        case .evening:
            return "moon.stars.fill"
        case .birthday:
            return "gift.fill"
        case .sunday:
            return "cross.fill"
        case .holiday:
            return "sparkles"
        case .welcome, .generic:
            return "hand.wave.fill"
        }
    }
}

#Preview {
    GreetingSettingsView()
}
