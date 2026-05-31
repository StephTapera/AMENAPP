//
//  PolicyGateView.swift
//  AMENAPP
//
//  T4 — User-facing view for GenerativePolicyGate violations.
//  Presents the Constitutional Constraint block message in a Liquid Glass sheet.
//
//  Usage:
//    .sheet(isPresented: $showPolicyBlock) {
//        PolicyGateView(violations: violations, onDismiss: { showPolicyBlock = false })
//    }
//

import SwiftUI

// MARK: - PolicyGateView

struct PolicyGateView: View {
    let violations: [GenerativePolicyViolation]
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            handle

            Image(systemName: "shield.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(AmenTheme.Colors.statusError)

            VStack(spacing: 8) {
                Text("Content Policy")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("This action can't be completed because it conflicts with AMEN's content policy.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if !violations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(violations, id: \.rule) { violation in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AmenTheme.Colors.statusError)
                                .font(.system(size: 14))
                                .padding(.top, 2)
                            Text(violation.reason)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
            }

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onDismiss()
                } label: {
                    Text("Understood")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AmenTheme.Colors.amenPurple, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://amenapp.com/ai-policy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Learn about AMEN's AI policy")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .presentationDetents([.height(480)])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }

    private var handle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: 36, height: 4)
    }
}

// MARK: - PolicyGateModifier

private struct PolicyGateModifier: ViewModifier {
    @Binding var violations: [GenerativePolicyViolation]
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            PolicyGateView(violations: violations) {
                isPresented = false
                violations = []
            }
        }
    }
}

extension View {
    func policyGateSheet(violations: Binding<[GenerativePolicyViolation]>, isPresented: Binding<Bool>) -> some View {
        modifier(PolicyGateModifier(violations: violations, isPresented: isPresented))
    }
}
