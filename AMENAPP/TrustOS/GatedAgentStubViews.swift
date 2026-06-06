// GatedAgentStubViews.swift
// TrustOS — Human-Gated Trust Agent Stubs
// These three agents require vendor integration review and are not yet active.
// They are gated pending App Store & legal approval.

import SwiftUI

// MARK: - Child Safety Agent Stub

struct ChildSafetyAgentStubView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Child Safety Agent")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)

                    Text("This feature requires a vendor integration review and is not yet active.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Enabled pending App Store & legal approval.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding()
        }
        .navigationTitle("Child Safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Threat Detection Agent Stub

struct ThreatDetectionAgentStubView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Threat Detection Agent")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)

                    Text("This feature requires a vendor integration review and is not yet active.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Enabled pending App Store & legal approval.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding()
        }
        .navigationTitle("Threat Detection")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Safe Meetups Agent Stub

struct SafeMeetupsAgentStubView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: "location.magnifyingglass")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Safe Meetups Agent")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)

                    Text("This feature requires a vendor integration review and is not yet active.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Enabled pending App Store & legal approval.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
            .padding()
        }
        .navigationTitle("Safe Meetups")
        .navigationBarTitleDisplayMode(.inline)
    }
}
