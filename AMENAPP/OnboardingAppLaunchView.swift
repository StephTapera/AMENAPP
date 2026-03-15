//
//  AppLaunchView.swift
//  AMENAPP
//
//  Redesigned — Screen 1 of the AMEN onboarding experience.
//  Bold editorial welcome · AMEN logo · spiritual calm · premium spacing.
//

import SwiftUI

struct AppLaunchView: View {
    @State private var showAuth = false
    @State private var authMode: AuthMode = .login

    // Staggered entrance phases
    @State private var logoAppeared  = false
    @State private var heroAppeared  = false
    @State private var pillsAppeared = false
    @State private var ctaAppeared   = false

    enum AuthMode {
        case login
        case signup
    }

    var body: some View {
        ZStack {
            ONB.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 72)

                // ── Logo ──────────────────────────────────────────────
                ONBAMENLogo(size: 56)
                    .opacity(logoAppeared ? 1 : 0)
                    .scaleEffect(logoAppeared ? 1 : 0.80)

                Spacer().frame(height: 32)

                // ── Wordmark ──────────────────────────────────────────
                Text("AMEN")
                    .font(.system(size: 44, weight: .black))
                    .tracking(10)
                    .foregroundStyle(ONB.inkPrimary)
                    .opacity(logoAppeared ? 1 : 0)
                    .offset(y: logoAppeared ? 0 : 8)

                Spacer().frame(height: 48)

                // ── Editorial hero block ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("A place to\ngrow in faith.")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(ONB.inkPrimary)
                        .lineSpacing(1)

                    Text("Thoughtful social, grounded in\nscripture. Free of noise.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(ONB.inkSecondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ONB.pagePadding)
                .opacity(heroAppeared ? 1 : 0)
                .offset(y: heroAppeared ? 0 : 18)

                Spacer().frame(height: 32)

                // ── Feature pills ─────────────────────────────────────
                HStack(spacing: 8) {
                    ForEach([
                        ("cross",                    "Prayer"),
                        ("book.closed",              "Scripture"),
                        ("person.2",                 "Community"),
                        ("sparkles",                 "Berean AI"),
                    ], id: \.1) { icon, label in
                        HStack(spacing: 5) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(ONB.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .strokeBorder(ONB.inkRule, lineWidth: 1)
                                .background(Capsule().fill(Color.white.opacity(0.6)))
                        )
                    }
                }
                .padding(.horizontal, ONB.pagePadding)
                .opacity(pillsAppeared ? 1 : 0)
                .offset(y: pillsAppeared ? 0 : 8)

                Spacer()

                // ── Rule ──────────────────────────────────────────────
                Rectangle()
                    .fill(ONB.inkRule)
                    .frame(height: 1)
                    .padding(.horizontal, ONB.pagePadding)
                    .opacity(ctaAppeared ? 1 : 0)

                Spacer().frame(height: 24)

                // ── CTA ───────────────────────────────────────────────
                VStack(spacing: 12) {
                    ONBPrimaryButton(title: "Create Account") {
                        authMode = .signup
                        showAuth = true
                    }

                    ONBSecondaryButton(title: "Log In") {
                        authMode = .login
                        showAuth = true
                    }
                }
                .padding(.horizontal, ONB.pagePadding)
                .opacity(ctaAppeared ? 1 : 0)
                .offset(y: ctaAppeared ? 0 : 12)

                Spacer().frame(height: 16)

                // Fine print
                Text("By continuing you agree to our **Terms** and **Privacy Policy**.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ONB.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(ctaAppeared ? 1 : 0)

                Spacer().frame(height: 40)
            }
        }
        .onAppear { runEntranceAnimation() }
        .fullScreenCover(isPresented: $showAuth) {
            MinimalAuthenticationView(initialMode: authMode)
        }
    }

    private func runEntranceAnimation() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.08)) {
            logoAppeared = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.28)) {
            heroAppeared = true
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.52)) {
            pillsAppeared = true
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.60)) {
            ctaAppeared = true
        }
    }
}

#Preview {
    AppLaunchView()
}
