// AMENAuthLandingView.swift
// AMENAPP
//
// The first auth screen shown after the splash dissolves.
// Pure white. Logo zone (top) + button zone (bottom).
// Funnels into existing SignInView for email auth.

import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseAuth

struct AMENAuthLandingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Stagger animation state
    @State private var logoScale:    CGFloat = 0.9
    @State private var logoOpacity:  Double  = 0
    @State private var wordOpacity:  Double  = 0
    @State private var btn1Opacity:  Double  = 0
    @State private var btn1Offset:   CGFloat = 10
    @State private var btn2Opacity:  Double  = 0
    @State private var btn2Offset:   CGFloat = 10
    @State private var divOpacity:   Double  = 0
    @State private var btn3Opacity:  Double  = 0
    @State private var btn3Offset:   CGFloat = 10
    @State private var linkOpacity:  Double  = 0

    // Button press states
    @State private var applePressed = false
    @State private var googlePressed = false
    @State private var emailBg = Color(.secondarySystemBackground)

    // Email flows
    @State private var showEmailSignUp = false
    @State private var showEmailSignIn = false
    
    // Apple Sign In nonce
    @State private var currentNonce: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Logo zone ──────────────────────────────────────────
                    Spacer()

                    VStack(spacing: 14) {
                        Image("amen-logo")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 52, height: 56)
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)

                        Text("AMEN")
                            .font(.systemScaled(22, weight: .black))
                            .tracking(7)
                            .foregroundStyle(.primary)
                            .opacity(wordOpacity)
                    }

                    Spacer()

                    // ── Button zone ────────────────────────────────────────
                    VStack(spacing: 12) {

                        // Button 1 — Apple
                        appleButton
                            .opacity(btn1Opacity)
                            .offset(y: btn1Offset)

                        // Button 2 — Google
                        googleButton
                            .opacity(btn2Opacity)
                            .offset(y: btn2Offset)

                        // Divider
                        orDivider
                            .opacity(divOpacity)

                        // Button 3 — Email sign up
                        emailButton
                            .opacity(btn3Opacity)
                            .offset(y: btn3Offset)

                        // Sign-in link
                        signInLink
                            .opacity(linkOpacity)
                            .padding(.top, 4)

                        #if targetEnvironment(simulator)
                        simulatorBypassButton
                            .padding(.top, 8)
                        #endif
                    }
                    .frame(maxWidth: 375)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 52)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showEmailSignUp) {
                EmailSignUpView()
                    .environmentObject(authViewModel)
            }
            .navigationDestination(isPresented: $showEmailSignIn) {
                EmailSignInView()
                    .environmentObject(authViewModel)
            }
        }
        .onAppear { runEntryAnimation() }
    }

    // MARK: - Simulator bypass (debug only)

    #if targetEnvironment(simulator)
    private var simulatorBypassButton: some View {
        Button {
            authViewModel.simulatorBypass()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                Text("Skip login (Simulator only)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: - Apple button

    private var appleButton: some View {
        SignInWithAppleButton(
            onRequest: { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            },
            onCompletion: { result in
                Task {
                    await handleAppleSignIn(result: result)
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .cornerRadius(14)
    }

    // MARK: - Google button

    private var googleButton: some View {
        Button {
            Task {
                await handleGoogleSignIn()
            }
        } label: {
            HStack(spacing: 0) {
                GoogleGLogo()
                    .frame(width: 18, height: 18)
                    .padding(.leading, 18)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Continue with Google")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 52)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(white: 0.898), lineWidth: 1.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(white: 0.922))
                .frame(height: 1)
            Text("or")
                .font(.systemScaled(11))
                .foregroundStyle(Color(white: 0.733))
                .fixedSize()
            Rectangle()
                .fill(Color(white: 0.922))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Email button

    private var emailButton: some View {
        Button {
            showEmailSignUp = true
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "envelope")
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.leading, 18)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Sign up with email")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 52)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(emailBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(EmailButtonStyle(bg: $emailBg))
    }

    // MARK: - Sign-in link

    private var signInLink: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .font(.systemScaled(12))
                .foregroundStyle(Color(white: 0.667))
            Button {
                showEmailSignIn = true
            } label: {
                Text("Sign in")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color.amenBlue)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Authentication Handlers
    
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8),
                  let nonce = currentNonce else {
                print("❌ Missing Apple credential data")
                return
            }
            
            do {
                _ = try await FirebaseManager.shared.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: appleIDCredential.fullName
                )
                print("✅ Apple sign-in successful")
            } catch {
                print("❌ Apple sign-in failed: \(error.localizedDescription)")
            }
            
        case .failure(let error):
            print("❌ Apple sign-in error: \(error.localizedDescription)")
        }
    }
    
    private func handleGoogleSignIn() async {
        do {
            _ = try await FirebaseManager.shared.signInWithGoogle()
            print("✅ Google sign-in successful")
        } catch {
            print("❌ Google sign-in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Entry animation

    private func runEntryAnimation() {
        let easeOut35 = Animation.easeOut(duration: 0.35)

        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
            logoScale   = 1.0
            logoOpacity = 1
        }
        withAnimation(reduceMotion ? nil : easeOut35.delay(0.08)) {
            wordOpacity = 1
        }
        withAnimation(reduceMotion ? nil : easeOut35.delay(0.18)) {
            btn1Opacity = 1; btn1Offset = 0
        }
        withAnimation(reduceMotion ? nil : easeOut35.delay(0.26)) {
            btn2Opacity = 1; btn2Offset = 0
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.32)) {
            divOpacity = 1
        }
        withAnimation(reduceMotion ? nil : easeOut35.delay(0.38)) {
            btn3Opacity = 1; btn3Offset = 0
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.46)) {
            linkOpacity = 1
        }
    }
    
    // MARK: - Nonce Helpers
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    assertionFailure("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                    random = UInt8.random(in: 0...UInt8.max)
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - Google G logo (4-color)

private struct GoogleGLogo: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let r  = size.width / 2

            // Blue arc (right)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: -30, end: 90,  color: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
            // Red arc (top-left)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 90,  end: 200, color: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))
            // Yellow arc (bottom-left)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 200, end: 330, color: .color(Color(red: 0.988, green: 0.729, blue: 0.012)))
            // Green arc (bottom-right)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 330, end: 360-30, color: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))

            // White cutout center
            var inner = Path()
            inner.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.58, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            ctx.fill(inner, with: .color(.white))

            // Right crossbar (the horizontal white-on-blue bar)
            var bar = Path()
            let barY = cy - r * 0.14
            bar.addRect(CGRect(x: cx, y: barY, width: r, height: r * 0.28))
            ctx.fill(bar, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))

            // White cutout to clean up center overlap
            var cutout = Path()
            cutout.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.58, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            ctx.fill(cutout, with: .color(.white))
        }
    }

    private func drawArc(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat,
                         start: Double, end: Double, color: GraphicsContext.Shading) {
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy))
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.closeSubpath()
        ctx.fill(path, with: color)
    }
}

// MARK: - Button styles
// (ScaleButtonStyle is defined in SharedUIComponents.swift)

private struct EmailButtonStyle: ButtonStyle {
    @Binding var bg: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                    bg = pressed ? Color(white: 0.922) : Color(white: 0.957)
                }
            }
    }
}

// MARK: - Stub email views

struct EmailSignUpView: View {
    var body: some View {
        MinimalAuthenticationView(
            initialMode: .signup,
            showsEmailFormOnAppear: true
        )
            .navigationBarHidden(true)
    }
}

struct EmailSignInView: View {
    var body: some View {
        MinimalAuthenticationView(
            initialMode: .login,
            showsEmailFormOnAppear: true
        )
            .navigationBarHidden(true)
    }
}
