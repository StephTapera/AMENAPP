// HealthWellnessView.swift — AMEN IntegrationOS
// SwiftUI wellness summary integrating HealthKit data.

import SwiftUI
import HealthKit

@MainActor
final class HealthWellnessViewModel: ObservableObject {
    @Published var summary: WellnessIntegrationService.WellnessSummary?
    @Published var isLoading = false
    @Published var hasAccess = false
    @Published var errorMessage: String?

    private let service = WellnessIntegrationService.shared

    func requestAndLoad() async {
        isLoading = true
        errorMessage = nil
        do {
            try await service.requestAccess(scopes: [.healthWalkingSteps, .healthSleepData, .healthWorkouts])
            hasAccess = true
            summary = await service.dailySummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct HealthWellnessView: View {
    @StateObject private var viewModel = HealthWellnessViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasAccess {
                    permissionPrompt
                } else if viewModel.isLoading {
                    ProgressView("Loading wellness data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let summary = viewModel.summary {
                    wellnessDashboard(summary: summary)
                }
            }
            .navigationTitle("Wellness")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.requestAndLoad() }
            .refreshable { await viewModel.requestAndLoad() }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.circle.fill")
                .font(.systemScaled(56))
                .foregroundStyle(.red)
            VStack(spacing: 8) {
                Text("Whole-Person Wellness")
                    .font(.title2.weight(.bold))
                Text("Connect your health data to integrate your physical and spiritual journey.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                Task { await viewModel.requestAndLoad() }
            } label: {
                Text("Connect Health")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func wellnessDashboard(summary: WellnessIntegrationService.WellnessSummary) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                WellnessTile(
                    icon: "figure.walk",
                    title: "Steps",
                    value: summary.steps.formatted(.number.precision(.fractionLength(0))),
                    unit: "steps",
                    color: .blue
                )
                WellnessTile(
                    icon: "flame.fill",
                    title: "Active Cal.",
                    value: summary.activeCalories.formatted(.number.precision(.fractionLength(0))),
                    unit: "kcal",
                    color: .orange
                )
                WellnessTile(
                    icon: "moon.fill",
                    title: "Sleep",
                    value: String(format: "%.1f", summary.sleepHours),
                    unit: "hours",
                    color: .purple
                )
                WellnessTile(
                    icon: "dumbbell.fill",
                    title: "Workouts",
                    value: summary.workoutMinutes.formatted(.number.precision(.fractionLength(0))),
                    unit: "min",
                    color: .green
                )
            }
            .padding()

            VStack(alignment: .leading, spacing: 8) {
                Text("Spiritual Connection")
                    .font(.headline)
                Text("Walking \(Int(summary.steps).formatted()) steps today — every step is a prayer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
            )
            .padding(.horizontal)
        }
    }
}

private struct WellnessTile: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
            Text("\(title) · \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
        )
    }
}
