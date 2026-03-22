// AMENAuthLandingView.swift
// AMENAPP
//
// The first auth screen shown after the splash dissolves.
// Pure white. Logo zone (top) + button zone (bottom).
// Funnels into existing SignInView for email auth.

import SwiftUI
import AuthenticationServices

struct AMENAuthLandingView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel

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
    @State private var emailBg = Color(white: 0.957)   // #F4F4F4

    // Email flows
    @State private var showEmailSignUp = false
    @State private var showEmailSignIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Logo zone ──────────────────────────────────────────
                    Spacer()

                    VStack(spacing: 14) {
                        Image("amen-logo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundStyle(Color.black)
                            .scaledToFit()
                            .frame(width: 52, height: 56)
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)

                        Text("AMEN")
                            .font(.system(size: 22, weight: .black))
                            .tracking(7)
                            .foregroundStyle(Color.black)
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
                    }
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

    // MARK: - Apple button

    private var appleButton: some View {
        Button {
            print("Apple sign in")
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Continue with Apple")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 52)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Google button

    private var googleButton: some View {
        Button {
            print("Google sign in")
        } label: {
            HStack(spacing: 0) {
                GoogleGLogo()
                    .frame(width: 18, height: 18)
                    .padding(.leading, 18)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Continue with Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
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
                .font(.system(size: 11))
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.leading, 18)
                    .frame(width: 52, alignment: .leading)
                Spacer()
                Text("Sign up with email")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
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
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.667))
            Button {
                showEmailSignIn = true
            } label: {
                Text("Sign in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Entry animation

    private func runEntryAnimation() {
        let easeOut35 = Animation.easeOut(duration: 0.35)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            logoScale   = 1.0
            logoOpacity = 1
        }
        withAnimation(easeOut35.delay(0.08)) {
            wordOpacity = 1
        }
        withAnimation(easeOut35.delay(0.18)) {
            btn1Opacity = 1; btn1Offset = 0
        }
        withAnimation(easeOut35.delay(0.26)) {
            btn2Opacity = 1; btn2Offset = 0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.32)) {
            divOpacity = 1
        }
        withAnimation(easeOut35.delay(0.38)) {
            btn3Opacity = 1; btn3Offset = 0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.46)) {
            linkOpacity = 1
        }
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
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: -30, end: 90,  color: .init(Color(red: 0.259, green: 0.522, blue: 0.957)))
            // Red arc (top-left)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 90,  end: 200, color: .init(Color(red: 0.918, green: 0.263, blue: 0.208)))
            // Yellow arc (bottom-left)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 200, end: 330, color: .init(Color(red: 0.988, green: 0.729, blue: 0.012)))
            // Green arc (bottom-right)
            drawArc(ctx: &ctx, cx: cx, cy: cy, r: r, start: 330, end: 360-30, color: .init(Color(red: 0.204, green: 0.659, blue: 0.325)))

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

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct EmailButtonStyle: ButtonStyle {
    @Binding var bg: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    bg = pressed ? Color(white: 0.922) : Color(white: 0.957)
                }
            }
    }
}

// MARK: - Stub email views

struct EmailSignUpView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Hands off to the full existing SignInView in sign-up mode.
        // Replace with real email sign-up flow when ready.
        SignInView()
            .environmentObject(authViewModel)
            .navigationBarHidden(true)
    }
}

struct EmailSignInView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SignInView()
            .environmentObject(authViewModel)
            .navigationBarHidden(true)
    }
}
