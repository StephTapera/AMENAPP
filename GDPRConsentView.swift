//
//  GDPRConsentView.swift
//  AMENAPP
//
//  Shown once before a user first submits a prayer request or testimony.
//  Prayer requests and testimonies constitute "special category" religious data
//  under GDPR Article 9, requiring explicit, informed consent at collection time.
//
//  Consent is recorded to Firestore (users/{uid}.gdprConsentGrantedAt) and
//  checked client-side via @AppStorage for subsequent submissions in the same session.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

struct GDPRConsentView: View {
    let contentType: ConsentContentType
    let onConsent: () -> Void
    let onDecline: () -> Void

    enum ConsentContentType {
        case prayer, testimony
        var displayName: String {
            switch self {
            case .prayer: return "prayer request"
            case .testimony: return "testimony"
            }
        }
    }

    @State private var isGranting = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    Text(NSLocalizedString("gdpr.title", comment: ""))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString(contentType == .prayer ? "gdpr.body.prayer" : "gdpr.body.testimony", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    consentPoint(icon: "checkmark.shield", text: NSLocalizedString("gdpr.bullet.encrypted", comment: ""))
                    consentPoint(icon: "person.badge.key", text: NSLocalizedString("gdpr.bullet.visibility", comment: ""))
                    consentPoint(icon: "trash", text: NSLocalizedString("gdpr.bullet.deletion", comment: ""))
                    consentPoint(icon: "hand.raised", text: NSLocalizedString("gdpr.bullet.neverSold", comment: ""))
                }
                .padding(.horizontal)

                Text("By tapping \"I Agree\", you give explicit consent to store this sensitive data as described above. You may withdraw consent by deleting your content at any time.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        grantConsent()
                    } label: {
                        Group {
                            if isGranting {
                                ProgressView().tint(.black)
                            } else {
                                Text(NSLocalizedString("gdpr.agree", comment: ""))
                                    .font(.headline)
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isGranting)

                    Button(NSLocalizedString("gdpr.decline", comment: "")) {
                        onDecline()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.1))
            )
            .padding(.horizontal, 20)
        }
    }

    private func consentPoint(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func grantConsent() {
        isGranting = true
        // Record consent server-side (GDPR requires documented consent with timestamp)
        if let uid = Auth.auth().currentUser?.uid {
            Firestore.firestore().collection("users").document(uid).updateData([
                "gdprReligiousDataConsentGrantedAt": FieldValue.serverTimestamp(),
                "gdprConsentVersion": "1.0",
                "gdprConsentContentType": contentType.displayName,
            ]) { _ in
                // Non-fatal if write fails — consent is still stored locally
            }
        }
        // Store locally to avoid showing again this session
        UserDefaults.standard.set(true, forKey: "gdprReligiousDataConsentGranted")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "gdprReligiousDataConsentDate")
        isGranting = false
        onConsent()
    }
}

// MARK: - Consent Gate Modifier

/// ViewModifier that gates a submission action behind GDPR consent.
/// Usage: .gdprConsentGate(contentType: .prayer) { submitPrayer() }
struct GDPRConsentGate: ViewModifier {
    let contentType: GDPRConsentView.ConsentContentType
    let onConsentGranted: () -> Void
    @State private var showConsent = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if UserDefaults.standard.bool(forKey: "gdprReligiousDataConsentGranted") {
                    onConsentGranted()
                } else {
                    showConsent = true
                }
            }
            .fullScreenCover(isPresented: $showConsent) {
                GDPRConsentView(contentType: contentType) {
                    showConsent = false
                    onConsentGranted()
                } onDecline: {
                    showConsent = false
                }
            }
    }
}

extension View {
    /// Gate any submit action behind GDPR consent for religious data.
    func requireGDPRConsent(
        for contentType: GDPRConsentView.ConsentContentType,
        then action: @escaping () -> Void
    ) -> some View {
        modifier(GDPRConsentGate(contentType: contentType, onConsentGranted: action))
    }
}

#Preview {
    GDPRConsentView(contentType: .prayer) {} onDecline: {}
}
