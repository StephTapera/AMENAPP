//
//  PhoneVerificationView.swift
//  AMENAPP
//
//  Phone verification UI for identity verification
//

import SwiftUI

// MARK: - Country Calling Code Data

struct CountryCallingCode: Identifiable, Hashable {
    let id: String   // ISO 3166-1 alpha-2 code e.g. "US"
    let dialCode: String  // e.g. "+1"
    let name: String  // Localised display name

    var display: String { "\(dialCode) (\(name))" }
}

/// Comprehensive list of country calling codes covering all inhabited regions.
/// Sorted alphabetically by country name for the picker.
let allCountryCallingCodes: [CountryCallingCode] = [
    CountryCallingCode(id: "AF", dialCode: "+93",  name: "Afghanistan"),
    CountryCallingCode(id: "AL", dialCode: "+355", name: "Albania"),
    CountryCallingCode(id: "DZ", dialCode: "+213", name: "Algeria"),
    CountryCallingCode(id: "AD", dialCode: "+376", name: "Andorra"),
    CountryCallingCode(id: "AO", dialCode: "+244", name: "Angola"),
    CountryCallingCode(id: "AR", dialCode: "+54",  name: "Argentina"),
    CountryCallingCode(id: "AM", dialCode: "+374", name: "Armenia"),
    CountryCallingCode(id: "AU", dialCode: "+61",  name: "Australia"),
    CountryCallingCode(id: "AT", dialCode: "+43",  name: "Austria"),
    CountryCallingCode(id: "AZ", dialCode: "+994", name: "Azerbaijan"),
    CountryCallingCode(id: "BH", dialCode: "+973", name: "Bahrain"),
    CountryCallingCode(id: "BD", dialCode: "+880", name: "Bangladesh"),
    CountryCallingCode(id: "BY", dialCode: "+375", name: "Belarus"),
    CountryCallingCode(id: "BE", dialCode: "+32",  name: "Belgium"),
    CountryCallingCode(id: "BZ", dialCode: "+501", name: "Belize"),
    CountryCallingCode(id: "BJ", dialCode: "+229", name: "Benin"),
    CountryCallingCode(id: "BO", dialCode: "+591", name: "Bolivia"),
    CountryCallingCode(id: "BA", dialCode: "+387", name: "Bosnia and Herzegovina"),
    CountryCallingCode(id: "BW", dialCode: "+267", name: "Botswana"),
    CountryCallingCode(id: "BR", dialCode: "+55",  name: "Brazil"),
    CountryCallingCode(id: "BN", dialCode: "+673", name: "Brunei"),
    CountryCallingCode(id: "BG", dialCode: "+359", name: "Bulgaria"),
    CountryCallingCode(id: "BF", dialCode: "+226", name: "Burkina Faso"),
    CountryCallingCode(id: "BI", dialCode: "+257", name: "Burundi"),
    CountryCallingCode(id: "KH", dialCode: "+855", name: "Cambodia"),
    CountryCallingCode(id: "CM", dialCode: "+237", name: "Cameroon"),
    CountryCallingCode(id: "CA", dialCode: "+1",   name: "Canada"),
    CountryCallingCode(id: "CV", dialCode: "+238", name: "Cape Verde"),
    CountryCallingCode(id: "CF", dialCode: "+236", name: "Central African Republic"),
    CountryCallingCode(id: "TD", dialCode: "+235", name: "Chad"),
    CountryCallingCode(id: "CL", dialCode: "+56",  name: "Chile"),
    CountryCallingCode(id: "CN", dialCode: "+86",  name: "China"),
    CountryCallingCode(id: "CO", dialCode: "+57",  name: "Colombia"),
    CountryCallingCode(id: "KM", dialCode: "+269", name: "Comoros"),
    CountryCallingCode(id: "CG", dialCode: "+242", name: "Congo"),
    CountryCallingCode(id: "CD", dialCode: "+243", name: "Congo (DRC)"),
    CountryCallingCode(id: "CR", dialCode: "+506", name: "Costa Rica"),
    CountryCallingCode(id: "CI", dialCode: "+225", name: "Côte d'Ivoire"),
    CountryCallingCode(id: "HR", dialCode: "+385", name: "Croatia"),
    CountryCallingCode(id: "CU", dialCode: "+53",  name: "Cuba"),
    CountryCallingCode(id: "CY", dialCode: "+357", name: "Cyprus"),
    CountryCallingCode(id: "CZ", dialCode: "+420", name: "Czech Republic"),
    CountryCallingCode(id: "DK", dialCode: "+45",  name: "Denmark"),
    CountryCallingCode(id: "DJ", dialCode: "+253", name: "Djibouti"),
    CountryCallingCode(id: "DO", dialCode: "+1",   name: "Dominican Republic"),
    CountryCallingCode(id: "EC", dialCode: "+593", name: "Ecuador"),
    CountryCallingCode(id: "EG", dialCode: "+20",  name: "Egypt"),
    CountryCallingCode(id: "SV", dialCode: "+503", name: "El Salvador"),
    CountryCallingCode(id: "GQ", dialCode: "+240", name: "Equatorial Guinea"),
    CountryCallingCode(id: "ER", dialCode: "+291", name: "Eritrea"),
    CountryCallingCode(id: "EE", dialCode: "+372", name: "Estonia"),
    CountryCallingCode(id: "ET", dialCode: "+251", name: "Ethiopia"),
    CountryCallingCode(id: "FJ", dialCode: "+679", name: "Fiji"),
    CountryCallingCode(id: "FI", dialCode: "+358", name: "Finland"),
    CountryCallingCode(id: "FR", dialCode: "+33",  name: "France"),
    CountryCallingCode(id: "GA", dialCode: "+241", name: "Gabon"),
    CountryCallingCode(id: "GM", dialCode: "+220", name: "Gambia"),
    CountryCallingCode(id: "GE", dialCode: "+995", name: "Georgia"),
    CountryCallingCode(id: "DE", dialCode: "+49",  name: "Germany"),
    CountryCallingCode(id: "GH", dialCode: "+233", name: "Ghana"),
    CountryCallingCode(id: "GR", dialCode: "+30",  name: "Greece"),
    CountryCallingCode(id: "GT", dialCode: "+502", name: "Guatemala"),
    CountryCallingCode(id: "GN", dialCode: "+224", name: "Guinea"),
    CountryCallingCode(id: "GW", dialCode: "+245", name: "Guinea-Bissau"),
    CountryCallingCode(id: "GY", dialCode: "+592", name: "Guyana"),
    CountryCallingCode(id: "HT", dialCode: "+509", name: "Haiti"),
    CountryCallingCode(id: "HN", dialCode: "+504", name: "Honduras"),
    CountryCallingCode(id: "HK", dialCode: "+852", name: "Hong Kong"),
    CountryCallingCode(id: "HU", dialCode: "+36",  name: "Hungary"),
    CountryCallingCode(id: "IS", dialCode: "+354", name: "Iceland"),
    CountryCallingCode(id: "IN", dialCode: "+91",  name: "India"),
    CountryCallingCode(id: "ID", dialCode: "+62",  name: "Indonesia"),
    CountryCallingCode(id: "IR", dialCode: "+98",  name: "Iran"),
    CountryCallingCode(id: "IQ", dialCode: "+964", name: "Iraq"),
    CountryCallingCode(id: "IE", dialCode: "+353", name: "Ireland"),
    CountryCallingCode(id: "IL", dialCode: "+972", name: "Israel"),
    CountryCallingCode(id: "IT", dialCode: "+39",  name: "Italy"),
    CountryCallingCode(id: "JM", dialCode: "+1",   name: "Jamaica"),
    CountryCallingCode(id: "JP", dialCode: "+81",  name: "Japan"),
    CountryCallingCode(id: "JO", dialCode: "+962", name: "Jordan"),
    CountryCallingCode(id: "KZ", dialCode: "+7",   name: "Kazakhstan"),
    CountryCallingCode(id: "KE", dialCode: "+254", name: "Kenya"),
    CountryCallingCode(id: "KW", dialCode: "+965", name: "Kuwait"),
    CountryCallingCode(id: "KG", dialCode: "+996", name: "Kyrgyzstan"),
    CountryCallingCode(id: "LA", dialCode: "+856", name: "Laos"),
    CountryCallingCode(id: "LV", dialCode: "+371", name: "Latvia"),
    CountryCallingCode(id: "LB", dialCode: "+961", name: "Lebanon"),
    CountryCallingCode(id: "LS", dialCode: "+266", name: "Lesotho"),
    CountryCallingCode(id: "LR", dialCode: "+231", name: "Liberia"),
    CountryCallingCode(id: "LY", dialCode: "+218", name: "Libya"),
    CountryCallingCode(id: "LI", dialCode: "+423", name: "Liechtenstein"),
    CountryCallingCode(id: "LT", dialCode: "+370", name: "Lithuania"),
    CountryCallingCode(id: "LU", dialCode: "+352", name: "Luxembourg"),
    CountryCallingCode(id: "MO", dialCode: "+853", name: "Macao"),
    CountryCallingCode(id: "MK", dialCode: "+389", name: "North Macedonia"),
    CountryCallingCode(id: "MG", dialCode: "+261", name: "Madagascar"),
    CountryCallingCode(id: "MW", dialCode: "+265", name: "Malawi"),
    CountryCallingCode(id: "MY", dialCode: "+60",  name: "Malaysia"),
    CountryCallingCode(id: "MV", dialCode: "+960", name: "Maldives"),
    CountryCallingCode(id: "ML", dialCode: "+223", name: "Mali"),
    CountryCallingCode(id: "MT", dialCode: "+356", name: "Malta"),
    CountryCallingCode(id: "MR", dialCode: "+222", name: "Mauritania"),
    CountryCallingCode(id: "MU", dialCode: "+230", name: "Mauritius"),
    CountryCallingCode(id: "MX", dialCode: "+52",  name: "Mexico"),
    CountryCallingCode(id: "MD", dialCode: "+373", name: "Moldova"),
    CountryCallingCode(id: "MC", dialCode: "+377", name: "Monaco"),
    CountryCallingCode(id: "MN", dialCode: "+976", name: "Mongolia"),
    CountryCallingCode(id: "ME", dialCode: "+382", name: "Montenegro"),
    CountryCallingCode(id: "MA", dialCode: "+212", name: "Morocco"),
    CountryCallingCode(id: "MZ", dialCode: "+258", name: "Mozambique"),
    CountryCallingCode(id: "MM", dialCode: "+95",  name: "Myanmar"),
    CountryCallingCode(id: "NA", dialCode: "+264", name: "Namibia"),
    CountryCallingCode(id: "NP", dialCode: "+977", name: "Nepal"),
    CountryCallingCode(id: "NL", dialCode: "+31",  name: "Netherlands"),
    CountryCallingCode(id: "NZ", dialCode: "+64",  name: "New Zealand"),
    CountryCallingCode(id: "NI", dialCode: "+505", name: "Nicaragua"),
    CountryCallingCode(id: "NE", dialCode: "+227", name: "Niger"),
    CountryCallingCode(id: "NG", dialCode: "+234", name: "Nigeria"),
    CountryCallingCode(id: "NO", dialCode: "+47",  name: "Norway"),
    CountryCallingCode(id: "OM", dialCode: "+968", name: "Oman"),
    CountryCallingCode(id: "PK", dialCode: "+92",  name: "Pakistan"),
    CountryCallingCode(id: "PA", dialCode: "+507", name: "Panama"),
    CountryCallingCode(id: "PG", dialCode: "+675", name: "Papua New Guinea"),
    CountryCallingCode(id: "PY", dialCode: "+595", name: "Paraguay"),
    CountryCallingCode(id: "PE", dialCode: "+51",  name: "Peru"),
    CountryCallingCode(id: "PH", dialCode: "+63",  name: "Philippines"),
    CountryCallingCode(id: "PL", dialCode: "+48",  name: "Poland"),
    CountryCallingCode(id: "PT", dialCode: "+351", name: "Portugal"),
    CountryCallingCode(id: "QA", dialCode: "+974", name: "Qatar"),
    CountryCallingCode(id: "RO", dialCode: "+40",  name: "Romania"),
    CountryCallingCode(id: "RU", dialCode: "+7",   name: "Russia"),
    CountryCallingCode(id: "RW", dialCode: "+250", name: "Rwanda"),
    CountryCallingCode(id: "SA", dialCode: "+966", name: "Saudi Arabia"),
    CountryCallingCode(id: "SN", dialCode: "+221", name: "Senegal"),
    CountryCallingCode(id: "RS", dialCode: "+381", name: "Serbia"),
    CountryCallingCode(id: "SL", dialCode: "+232", name: "Sierra Leone"),
    CountryCallingCode(id: "SG", dialCode: "+65",  name: "Singapore"),
    CountryCallingCode(id: "SK", dialCode: "+421", name: "Slovakia"),
    CountryCallingCode(id: "SI", dialCode: "+386", name: "Slovenia"),
    CountryCallingCode(id: "SO", dialCode: "+252", name: "Somalia"),
    CountryCallingCode(id: "ZA", dialCode: "+27",  name: "South Africa"),
    CountryCallingCode(id: "SS", dialCode: "+211", name: "South Sudan"),
    CountryCallingCode(id: "ES", dialCode: "+34",  name: "Spain"),
    CountryCallingCode(id: "LK", dialCode: "+94",  name: "Sri Lanka"),
    CountryCallingCode(id: "SD", dialCode: "+249", name: "Sudan"),
    CountryCallingCode(id: "SR", dialCode: "+597", name: "Suriname"),
    CountryCallingCode(id: "SE", dialCode: "+46",  name: "Sweden"),
    CountryCallingCode(id: "CH", dialCode: "+41",  name: "Switzerland"),
    CountryCallingCode(id: "SY", dialCode: "+963", name: "Syria"),
    CountryCallingCode(id: "TW", dialCode: "+886", name: "Taiwan"),
    CountryCallingCode(id: "TJ", dialCode: "+992", name: "Tajikistan"),
    CountryCallingCode(id: "TZ", dialCode: "+255", name: "Tanzania"),
    CountryCallingCode(id: "TH", dialCode: "+66",  name: "Thailand"),
    CountryCallingCode(id: "TG", dialCode: "+228", name: "Togo"),
    CountryCallingCode(id: "TT", dialCode: "+1",   name: "Trinidad and Tobago"),
    CountryCallingCode(id: "TN", dialCode: "+216", name: "Tunisia"),
    CountryCallingCode(id: "TR", dialCode: "+90",  name: "Turkey"),
    CountryCallingCode(id: "TM", dialCode: "+993", name: "Turkmenistan"),
    CountryCallingCode(id: "UG", dialCode: "+256", name: "Uganda"),
    CountryCallingCode(id: "UA", dialCode: "+380", name: "Ukraine"),
    CountryCallingCode(id: "AE", dialCode: "+971", name: "United Arab Emirates"),
    CountryCallingCode(id: "GB", dialCode: "+44",  name: "United Kingdom"),
    CountryCallingCode(id: "US", dialCode: "+1",   name: "United States"),
    CountryCallingCode(id: "UY", dialCode: "+598", name: "Uruguay"),
    CountryCallingCode(id: "UZ", dialCode: "+998", name: "Uzbekistan"),
    CountryCallingCode(id: "VE", dialCode: "+58",  name: "Venezuela"),
    CountryCallingCode(id: "VN", dialCode: "+84",  name: "Vietnam"),
    CountryCallingCode(id: "YE", dialCode: "+967", name: "Yemen"),
    CountryCallingCode(id: "ZM", dialCode: "+260", name: "Zambia"),
    CountryCallingCode(id: "ZW", dialCode: "+263", name: "Zimbabwe"),
].sorted { $0.name < $1.name }

struct PhoneVerificationView: View {
    @ObservedObject private var verificationService = PhoneVerificationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var selectedCountry: CountryCallingCode = allCountryCallingCodes.first(where: { $0.id == "US" })
        ?? allCountryCallingCodes[0]
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var canResend = false
    @State private var resendCountdown = 60

    @FocusState private var focusedField: Field?

    /// The dial code string used when building the full E.164 number.
    private var countryCode: String { selectedCountry.dialCode }

    enum Field {
        case phone
        case code
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Phone input or code verification
                    if case .codeSent = verificationService.verificationStatus {
                        codeVerificationSection
                    } else if case .verifying = verificationService.verificationStatus {
                        loadingSection
                    } else if case .verified = verificationService.verificationStatus {
                        successSection
                    } else {
                        phoneInputSection
                    }
                }
                .padding()
            }
            .navigationTitle("Verify Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Verify Your Phone")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Text("Phone verification helps keep AMEN safe and unlocks more features")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Phone Input Section
    
    private var phoneInputSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Phone Number")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    // Country code picker — full global list
                    Menu {
                        Picker("Country", selection: $selectedCountry) {
                            ForEach(allCountryCallingCodes) { country in
                                Text(country.display).tag(country)
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedCountry.dialCode)
                                .font(.custom("OpenSans-SemiBold", size: 16))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    // Phone number input
                    TextField("123456789", text: $phoneNumber)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .focused($focusedField, equals: .phone)
                }
            }
            
            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "checkmark.shield.fill", text: "Enhanced security", color: .green)
                benefitRow(icon: "message.fill", text: "Send messages to more users", color: .blue)
                benefitRow(icon: "person.badge.plus", text: "Build trust in the community", color: .purple)
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
            
            // Send code button
            Button(action: sendCode) {
                HStack {
                    if case .verifying = verificationService.verificationStatus {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Send Verification Code")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    phoneNumber.count >= 7 ? Color.black : Color.gray.opacity(0.3)
                )
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(phoneNumber.count < 7)
        }
    }
    
    // MARK: - Code Verification Section
    
    private var codeVerificationSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Code sent to")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                Text("\(countryCode) \(phoneNumber)")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                
                Button("Change number") {
                    verificationService.reset()
                    phoneNumber = ""
                    verificationCode = ""
                }
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Verification Code")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                
                TextField("000000", text: $verificationCode)
                    .font(.custom("OpenSans-Bold", size: 24))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .focused($focusedField, equals: .code)
                    .onChange(of: verificationCode) { oldValue, newValue in
                        // Limit to 6 digits
                        if newValue.count > 6 {
                            verificationCode = String(newValue.prefix(6))
                        }
                        // Auto-verify when 6 digits entered
                        if verificationCode.count == 6 {
                            Task {
                                await verifyCode()
                            }
                        }
                    }
            }
            
            // Resend code
            if canResend {
                Button("Resend Code") {
                    Task {
                        await resendCode()
                    }
                }
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.blue)
            } else {
                Text("Resend code in \(resendCountdown)s")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .onAppear {
                        startResendTimer()
                    }
            }
            
            // Verify button
            Button(action: { Task { await verifyCode() } }) {
                HStack {
                    if case .verifying = verificationService.verificationStatus {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Verify")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    verificationCode.count == 6 ? Color.black : Color.gray.opacity(0.3)
                )
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(verificationCode.count != 6)
        }
        .onAppear {
            focusedField = .code
        }
    }
    
    // MARK: - Loading Section
    
    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Verifying...")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }
    
    // MARK: - Success Section
    
    private var successSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }
            
            Text("Phone Verified!")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Text("Your phone number has been successfully verified")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Done") {
                dismiss()
            }
            .font(.custom("OpenSans-SemiBold", size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black)
            .cornerRadius(12)
        }
        .padding(.top, 40)
    }
    
    // MARK: - Helper Views
    
    private func benefitRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func sendCode() {
        let fullPhoneNumber = countryCode + phoneNumber
        
        Task {
            do {
                try await verificationService.sendVerificationCode(to: fullPhoneNumber)
                focusedField = .code
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func verifyCode() async {
        do {
            try await verificationService.verifyCode(verificationCode)
            // Success handled by verificationStatus change
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            verificationCode = ""
        }
    }
    
    private func resendCode() async {
        canResend = false
        resendCountdown = 60
        
        do {
            try await verificationService.resendVerificationCode()
            startResendTimer()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func startResendTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                canResend = true
                timer.invalidate()
            }
        }
    }
}

#Preview {
    PhoneVerificationView()
}
