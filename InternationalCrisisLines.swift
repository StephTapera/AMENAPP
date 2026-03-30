//
//  InternationalCrisisLines.swift
//  AMENAPP
//
//  Country → crisis line lookup table.
//  Uses Locale.current.region to detect country without CoreLocation permission.
//

import Foundation

struct InternationalCrisisLine: Identifiable {
    let id = UUID()
    let country: String
    let countryCode: String  // ISO 3166-1 alpha-2
    let name: String
    let phone: String
    let textNumber: String?
    let emergencyNumber: String  // local 911 equivalent
    let is24x7: Bool
}

enum InternationalCrisisLineService {

    /// Detects user's country from device locale (no permission needed).
    static var detectedCountryCode: String {
        Locale.current.region?.identifier ?? "US"
    }

    static var isUS: Bool {
        detectedCountryCode == "US"
    }

    /// Returns the crisis line for the detected country, or nil if US/unknown.
    static var localCrisisLine: InternationalCrisisLine? {
        lines.first { $0.countryCode == detectedCountryCode }
    }

    /// All international crisis lines.
    static let lines: [InternationalCrisisLine] = [
        // North America
        InternationalCrisisLine(country: "Canada", countryCode: "CA",
            name: "988 Suicide Crisis Helpline", phone: "988",
            textNumber: "988", emergencyNumber: "911", is24x7: true),
        InternationalCrisisLine(country: "Mexico", countryCode: "MX",
            name: "Línea de la Vida", phone: "800-911-2000",
            textNumber: nil, emergencyNumber: "911", is24x7: true),

        // Europe
        InternationalCrisisLine(country: "United Kingdom", countryCode: "GB",
            name: "Samaritans", phone: "116 123",
            textNumber: nil, emergencyNumber: "999", is24x7: true),
        InternationalCrisisLine(country: "Ireland", countryCode: "IE",
            name: "Samaritans Ireland", phone: "116 123",
            textNumber: "51444", emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "France", countryCode: "FR",
            name: "SOS Amitié", phone: "09 72 39 40 50",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Germany", countryCode: "DE",
            name: "Telefonseelsorge", phone: "0800 111 0 111",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Spain", countryCode: "ES",
            name: "Teléfono de la Esperanza", phone: "717 003 717",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Italy", countryCode: "IT",
            name: "Telefono Amico", phone: "02 2327 2327",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Netherlands", countryCode: "NL",
            name: "113 Zelfmoordpreventie", phone: "113",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Belgium", countryCode: "BE",
            name: "Centre de Prévention du Suicide", phone: "0800 32 123",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Switzerland", countryCode: "CH",
            name: "Die Dargebotene Hand", phone: "143",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Austria", countryCode: "AT",
            name: "Telefonseelsorge", phone: "142",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Portugal", countryCode: "PT",
            name: "SOS Voz Amiga", phone: "213 544 545",
            textNumber: nil, emergencyNumber: "112", is24x7: false),
        InternationalCrisisLine(country: "Sweden", countryCode: "SE",
            name: "Mind Självmordslinjen", phone: "90101",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Norway", countryCode: "NO",
            name: "Kirkens SOS", phone: "22 40 00 40",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Denmark", countryCode: "DK",
            name: "Livslinien", phone: "70 201 201",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Finland", countryCode: "FI",
            name: "MIELI Crisis Helpline", phone: "09 2525 0111",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Poland", countryCode: "PL",
            name: "Telefon Zaufania", phone: "116 123",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Greece", countryCode: "GR",
            name: "Suicide Help Greece", phone: "1018",
            textNumber: nil, emergencyNumber: "112", is24x7: true),
        InternationalCrisisLine(country: "Romania", countryCode: "RO",
            name: "Telefonul Sufletului", phone: "0800 801 200",
            textNumber: nil, emergencyNumber: "112", is24x7: true),

        // Oceania
        InternationalCrisisLine(country: "Australia", countryCode: "AU",
            name: "Lifeline Australia", phone: "13 11 14",
            textNumber: nil, emergencyNumber: "000", is24x7: true),
        InternationalCrisisLine(country: "New Zealand", countryCode: "NZ",
            name: "Lifeline NZ", phone: "0800 543 354",
            textNumber: "4357", emergencyNumber: "111", is24x7: true),

        // Asia
        InternationalCrisisLine(country: "Japan", countryCode: "JP",
            name: "TELL Lifeline", phone: "03-5774-0992",
            textNumber: nil, emergencyNumber: "119", is24x7: false),
        InternationalCrisisLine(country: "South Korea", countryCode: "KR",
            name: "Korea Suicide Prevention Center", phone: "1393",
            textNumber: nil, emergencyNumber: "119", is24x7: true),
        InternationalCrisisLine(country: "India", countryCode: "IN",
            name: "iCall", phone: "9152987821",
            textNumber: nil, emergencyNumber: "112", is24x7: false),
        InternationalCrisisLine(country: "Philippines", countryCode: "PH",
            name: "Natasha Goulbourn Foundation", phone: "0917-558-4673",
            textNumber: nil, emergencyNumber: "911", is24x7: true),
        InternationalCrisisLine(country: "Singapore", countryCode: "SG",
            name: "Samaritans of Singapore", phone: "1-767",
            textNumber: nil, emergencyNumber: "995", is24x7: true),
        InternationalCrisisLine(country: "Hong Kong", countryCode: "HK",
            name: "Samaritan Befrienders", phone: "2389 2222",
            textNumber: nil, emergencyNumber: "999", is24x7: true),
        InternationalCrisisLine(country: "Taiwan", countryCode: "TW",
            name: "Taiwan Suicide Prevention", phone: "1925",
            textNumber: nil, emergencyNumber: "119", is24x7: true),
        InternationalCrisisLine(country: "Malaysia", countryCode: "MY",
            name: "Befrienders Malaysia", phone: "03-7627 2929",
            textNumber: nil, emergencyNumber: "999", is24x7: true),
        InternationalCrisisLine(country: "Thailand", countryCode: "TH",
            name: "Samaritans Thailand", phone: "02-713-6793",
            textNumber: nil, emergencyNumber: "1669", is24x7: true),
        InternationalCrisisLine(country: "Indonesia", countryCode: "ID",
            name: "Into The Light", phone: "119",
            textNumber: nil, emergencyNumber: "119", is24x7: true),

        // Africa
        InternationalCrisisLine(country: "South Africa", countryCode: "ZA",
            name: "SADAG", phone: "0800 567 567",
            textNumber: "31393", emergencyNumber: "10111", is24x7: true),
        InternationalCrisisLine(country: "Kenya", countryCode: "KE",
            name: "Befrienders Kenya", phone: "0722 178 177",
            textNumber: nil, emergencyNumber: "999", is24x7: false),
        InternationalCrisisLine(country: "Nigeria", countryCode: "NG",
            name: "SURPIN", phone: "0800-123-0000",
            textNumber: nil, emergencyNumber: "112", is24x7: false),
        InternationalCrisisLine(country: "Ghana", countryCode: "GH",
            name: "Ghana Suicide Helpline", phone: "233-244846115",
            textNumber: nil, emergencyNumber: "999", is24x7: false),

        // South America
        InternationalCrisisLine(country: "Brazil", countryCode: "BR",
            name: "CVV", phone: "188",
            textNumber: nil, emergencyNumber: "190", is24x7: true),
        InternationalCrisisLine(country: "Argentina", countryCode: "AR",
            name: "Centro de Asistencia al Suicida", phone: "(011) 5275-1135",
            textNumber: nil, emergencyNumber: "911", is24x7: true),
        InternationalCrisisLine(country: "Colombia", countryCode: "CO",
            name: "Línea 106", phone: "106",
            textNumber: nil, emergencyNumber: "123", is24x7: true),
        InternationalCrisisLine(country: "Chile", countryCode: "CL",
            name: "Salud Responde", phone: "600 360 7777",
            textNumber: nil, emergencyNumber: "131", is24x7: true),
        InternationalCrisisLine(country: "Peru", countryCode: "PE",
            name: "Línea 113", phone: "113",
            textNumber: nil, emergencyNumber: "105", is24x7: true),

        // Middle East
        InternationalCrisisLine(country: "Israel", countryCode: "IL",
            name: "ERAN", phone: "1201",
            textNumber: nil, emergencyNumber: "100", is24x7: true),
        InternationalCrisisLine(country: "United Arab Emirates", countryCode: "AE",
            name: "Dubai Foundation for Women & Children", phone: "800-111",
            textNumber: nil, emergencyNumber: "999", is24x7: true),
        InternationalCrisisLine(country: "Saudi Arabia", countryCode: "SA",
            name: "920033360", phone: "920033360",
            textNumber: nil, emergencyNumber: "911", is24x7: false),
    ]
}
