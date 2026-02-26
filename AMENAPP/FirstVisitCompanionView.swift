//
//  FirstVisitCompanionView.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - Main View
//

import SwiftUI
import FirebaseFirestore

struct FirstVisitCompanionView: View {
    @StateObject private var viewModel = FirstVisitCompanionViewModel()
    @Environment(\.dismiss) private var dismiss
    
    let church: VisitCompanionChurch
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // What to Expect
                    whatToExpectSection
                    
                    // Service Selection
                    serviceSelectionSection
                    
                    // Date Picker
                    dateSelectionSection
                    
                    // Preferences
                    preferencesSection
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.amenDarkPrimary,
                        Color.amenDarkPrimary.opacity(0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Plan Your Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.amenGold)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .alert("Visit Plan Created", isPresented: $viewModel.showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your visit to \(church.name) has been added to your plan.")
            }
        }
        .onAppear {
            viewModel.selectedChurch = church
            Task {
                await viewModel.loadExistingVisitPlan(
                    church: church,
                    serviceDate: viewModel.selectedDate
                )
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.amenGold)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(church.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.amenTextPrimary)
                    
                    if let denomination = church.denomination {
                        Text(denomination)
                            .font(.subheadline)
                            .foregroundColor(.amenTextSecondary)
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.amenGold)
                Text(church.address.fullAddress)
                    .font(.subheadline)
                    .foregroundColor(.amenTextSecondary)
            }
            
            if let phone = church.phoneNumber {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.amenGold)
                    Text(phone)
                        .font(.subheadline)
                        .foregroundColor(.amenTextSecondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - What to Expect Section
    
    private var whatToExpectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What to Expect")
                .font(.headline)
                .foregroundColor(.amenTextPrimary)
            
            if let dressCode = church.dressCode {
                infoRow(icon: "tshirt.fill", title: "Dress Code", value: dressCode)
            }
            
            if let parking = church.parkingInfo {
                infoRow(icon: "parkingsign.circle.fill", title: "Parking", value: parking)
            }
            
            if let accessibility = church.accessibilityInfo {
                infoRow(icon: "figure.roll", title: "Accessibility", value: accessibility)
            }
            
            if church.childcareAvailable {
                infoRow(icon: "figure.2.and.child.holdinghands", title: "Childcare", value: "Available")
            }
            
            if let contact = church.welcomeTeamContact {
                infoRow(icon: "person.2.fill", title: "Welcome Team", value: contact)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.amenGold)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.amenTextPrimary)
                
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.amenTextSecondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Service Selection
    
    private var serviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Service")
                .font(.headline)
                .foregroundColor(.amenTextPrimary)
            
            ForEach(church.services) { service in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectedService = service
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.serviceType)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.amenTextPrimary)
                            
                            HStack(spacing: 8) {
                                Text("\(service.dayOfWeek) at \(service.startTime)")
                                    .font(.caption)
                                    .foregroundColor(.amenTextSecondary)
                                
                                if let language = service.language, language != "English" {
                                    Text("• \(language)")
                                        .font(.caption)
                                        .foregroundColor(.amenTextSecondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if viewModel.selectedService?.id == service.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.amenGold)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.selectedService?.id == service.id ?
                                  Color.amenGold.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                viewModel.selectedService?.id == service.id ?
                                Color.amenGold : Color.gray.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Date Selection
    
    private var dateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Date")
                .font(.headline)
                .foregroundColor(.amenTextPrimary)
            
            DatePicker(
                "Service Date",
                selection: $viewModel.selectedDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(.amenGold)
            
            if !viewModel.isValidVisitDate() {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Please select a future date")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reminders & Calendar")
                .font(.headline)
                .foregroundColor(.amenTextPrimary)
            
            Toggle(isOn: $viewModel.addToCalendar) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.amenGold)
                    Text("Add to Calendar")
                        .font(.subheadline)
                }
            }
            .tint(.amenGold)
            
            Toggle(isOn: $viewModel.enable24HourReminder) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.amenGold)
                    Text("Remind me 24 hours before")
                        .font(.subheadline)
                }
            }
            .tint(.amenGold)
            
            Toggle(isOn: $viewModel.enableDayOfReminder) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.amenGold)
                    Text("Remind me 1 hour before")
                        .font(.subheadline)
                }
            }
            .tint(.amenGold)
            
            Toggle(isOn: $viewModel.enablePostVisitReminder) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text.badge.plus")
                        .foregroundColor(.amenGold)
                    Text("Prompt me to create a note after")
                        .font(.subheadline)
                }
            }
            .tint(.amenGold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if viewModel.visitPlan == nil {
                // Create visit plan button
                Button {
                    Task {
                        await viewModel.createVisitPlan()
                    }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Create Visit Plan")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                viewModel.selectedService != nil && viewModel.isValidVisitDate() ?
                                Color.amenGold : Color.gray.opacity(0.5)
                            )
                    )
                    .foregroundColor(.white)
                }
                .disabled(viewModel.selectedService == nil || !viewModel.isValidVisitDate() || viewModel.isLoading)
                .buttonStyle(.plain)
                
            } else {
                // Existing visit plan - show cancel option
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Visit plan created")
                            .font(.subheadline)
                            .foregroundColor(.amenTextPrimary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.15))
                    )
                    
                    Button {
                        Task {
                            await viewModel.cancelVisitPlan()
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel Visit Plan")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 1.5)
                        )
                        .foregroundColor(.red)
                    }
                    .disabled(viewModel.isLoading)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
