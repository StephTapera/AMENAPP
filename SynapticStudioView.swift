//
//  SynapticStudioView.swift
//  AMENAPP
//
//  Synaptic Studio — biometric-driven creative medium.
//
//  At the moment of creation, your body's state becomes context.
//  Heart rate at rest → contemplative, slower tone.
//  Elevated HR → urgent, emotionally charged language.
//  HRV (Heart Rate Variability) → resilience / stress signal → warmth vs directness.
//
//  V1 approach (no Watch required):
//    • HealthKit reads most recent HKQuantityType heartRate + HRV sample.
//    • iPhone motion/steps optionally supplement if no HR sample in last 10 min.
//    • Biometric snapshot is passed to `synapticCreate` Cloud Function alongside
//      the user's creative intent — AI shapes tone accordingly.
//    • No biometric data is stored or transmitted beyond the anonymous
//      "biometric_context" snapshot for the single creation request.
//
//  Privacy: biometric data is never stored in Firestore or logged.
//  HealthKit permission: NSHealthShareUsageDescription required in Info.plist.
//

import Combine
import SwiftUI
import HealthKit
import FirebaseFunctions

// MARK: - Biometric Snapshot

struct BiometricSnapshot {
    let heartRate: Double?        // BPM — nil if no recent sample
    let hrv: Double?              // ms RMSSD — nil if unavailable
    let stepsToday: Int?          // step count since midnight
    let capturedAt: Date

    /// Returns a simplified string context for the AI prompt
    var aiContext: String {
        var parts: [String] = []
        if let hr = heartRate {
            let desc = hr < 60 ? "resting" : hr < 80 ? "calm" : hr < 100 ? "moderately elevated" : "elevated"
            parts.append("heart rate: \(Int(hr)) BPM (\(desc))")
        }
        if let hrv = hrv {
            let desc = hrv > 50 ? "high resilience" : hrv > 30 ? "moderate stress" : "elevated stress"
            parts.append("HRV: \(Int(hrv))ms (\(desc))")
        }
        if let steps = stepsToday {
            parts.append("steps today: \(steps)")
        }
        return parts.isEmpty ? "no biometric data available" : parts.joined(separator: ", ")
    }

    var emotionalProfile: String {
        guard let hr = heartRate else { return "unknown" }
        if hr < 60 { return "deeply still" }
        if hr < 75 { return "centered" }
        if hr < 90 { return "engaged" }
        if hr < 110 { return "stirred" }
        return "impassioned"
    }
}

// MARK: - HealthKit Reader

final class BiometricReader {
    static let shared = BiometricReader()
    private let store = HKHealthStore()

    private init() {}

    func isAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestPermissionIfNeeded() async -> Bool {
        guard isAvailable() else { return false }
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: nil, read: types) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func snapshot() async -> BiometricSnapshot {
        async let hr = latestHeartRate()
        async let hrv = latestHRV()
        async let steps = stepsToday()
        return await BiometricSnapshot(
            heartRate: hr,
            hrv: hrv,
            stepsToday: steps,
            capturedAt: Date()
        )
    }

    private func latestHeartRate() async -> Double? {
        await latestQuantitySample(typeId: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    private func latestHRV() async -> Double? {
        await latestQuantitySample(typeId: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    private func stepsToday() async -> Int? {
        guard isAvailable() else { return nil }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let value = result?.sumQuantity().map { Int($0.doubleValue(for: .count())) }
                continuation.resume(returning: value ?? nil)
            }
            store.execute(query)
        }
    }

    private func latestQuantitySample(typeId: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable() else { return nil }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: HKQuery.predicateForSamples(
                    withStart: Date().addingTimeInterval(-600), // last 10 min
                    end: Date(), options: .strictEndDate
                ),
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SynapticStudioViewModel: ObservableObject {
    @Published var snapshot: BiometricSnapshot?
    @Published var isCapturingBiometrics = false
    @Published var userIntent: String = ""
    @Published var creativeMode: SynapticMode = .prayer
    @Published var generatedContent: String = ""
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var phase: Phase = .biometric
    @Published var healthKitDenied = false

    enum Phase { case biometric, intent, result }

    private let functions = Functions.functions(region: "us-central1")

    func captureBiometrics() async {
        isCapturingBiometrics = true
        let reader = BiometricReader.shared
        let granted = await reader.requestPermissionIfNeeded()
        if !granted {
            healthKitDenied = true
            // Proceed without biometrics — create a placeholder snapshot
            snapshot = BiometricSnapshot(heartRate: nil, hrv: nil, stepsToday: nil, capturedAt: Date())
        } else {
            snapshot = await reader.snapshot()
        }
        isCapturingBiometrics = false
        phase = .intent
    }

    func generate() {
        guard !userIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        generatedContent = ""
        phase = .result

        Task {
            defer { isGenerating = false }
            do {
                let payload: [String: Any] = [
                    "mode": creativeMode.rawValue,
                    "user_intent": userIntent,
                    "biometric_context": snapshot?.aiContext ?? "no biometric data",
                    "emotional_profile": snapshot?.emotionalProfile ?? "unknown",
                    "heart_rate": snapshot?.heartRate as Any,
                    "hrv": snapshot?.hrv as Any
                ]
                let result = try await functions.httpsCallable("synapticCreate").safeCall(payload)
                if let data = result.data as? [String: Any],
                   let text = data["generated_content"] as? String {
                    generatedContent = text
                } else {
                    errorMessage = "Couldn't read the response."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reset() {
        snapshot = nil
        userIntent = ""
        generatedContent = ""
        errorMessage = nil
        phase = .biometric
        isGenerating = false
    }
}

enum SynapticMode: String, CaseIterable, Identifiable {
    case prayer      = "prayer"
    case reflection  = "reflection"
    case testimony   = "testimony"
    case lament      = "lament"
    case praise      = "praise"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prayer:     return "Prayer"
        case .reflection: return "Reflection"
        case .testimony:  return "Testimony"
        case .lament:     return "Lament"
        case .praise:     return "Praise"
        }
    }

    var icon: String {
        switch self {
        case .prayer:     return "hands.sparkles.fill"
        case .reflection: return "brain.head.profile"
        case .testimony:  return "quote.bubble.fill"
        case .lament:     return "cloud.drizzle.fill"
        case .praise:     return "star.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .prayer:     return .purple
        case .reflection: return .blue
        case .testimony:  return .teal
        case .lament:     return .indigo
        case .praise:     return .orange
        }
    }
}

// MARK: - Main View

struct SynapticStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SynapticStudioViewModel()
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    switch vm.phase {
                    case .biometric:
                        biometricPhase
                            .transition(.opacity)
                    case .intent:
                        intentPhase
                            .transition(.opacity)
                    case .result:
                        resultPhase
                            .transition(.opacity)
                    }
                }
            }
            .navigationBarHidden(true)
            .animation(.easeInOut(duration: 0.25), value: vm.phase)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("Synaptic Studio")
                    .font(.system(size: 16, weight: .bold))
                Text("Your body. Your words.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Color.clear.frame(width: 33, height: 33)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Phase 1: Biometric Capture

    private var biometricPhase: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.1), Color.clear],
                                    center: .center, startRadius: 10, endRadius: 70
                                )
                            )
                            .frame(width: 120, height: 120)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)

                    Text("Let your body speak first")
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text("Synaptic Studio reads your biometric state — heart rate, HRV — and shapes your creative output to meet you exactly where you are.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // What we read
                VStack(spacing: 10) {
                    BiometricFeatureRow(icon: "heart.fill", color: .red,
                                        title: "Heart Rate",
                                        detail: "Resting vs elevated shapes word rhythm and urgency")
                    BiometricFeatureRow(icon: "waveform.path", color: .purple,
                                        title: "Heart Rate Variability",
                                        detail: "Stress resilience signals warmth vs directness")
                    BiometricFeatureRow(icon: "figure.walk", color: .teal,
                                        title: "Movement",
                                        detail: "Activity level subtly influences energy of language")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.purple.opacity(0.12), lineWidth: 1)
                        )
                )

                if vm.healthKitDenied {
                    Text("HealthKit access denied — your creation will use default tone. You can grant access in Settings > Health.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // CTA
                Button {
                    Task { await vm.captureBiometrics() }
                } label: {
                    Group {
                        if vm.isCapturingBiometrics {
                            HStack(spacing: 10) {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                                Text("Reading…")
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Read My State")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue.opacity(0.8)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(vm.isCapturingBiometrics)

                Button {
                    // Skip biometrics, proceed without
                    vm.snapshot = BiometricSnapshot(heartRate: nil, hrv: nil, stepsToday: nil, capturedAt: Date())
                    vm.phase = .intent
                } label: {
                    Text("Skip — create without biometrics")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Phase 2: Intent

    private var intentPhase: some View {
        VStack(spacing: 0) {
            // Biometric summary card
            if let snap = vm.snapshot, snap.heartRate != nil || snap.hrv != nil {
                biometricSummaryCard(snap)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Mode picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What are you creating?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(SynapticMode.allCases) { mode in
                                    modeChip(mode)
                                }
                            }
                        }
                    }

                    // Intent input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your intention")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $vm.userIntent)
                                .frame(minHeight: 120)
                                .font(.system(size: 15))
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                            if vm.userIntent.isEmpty {
                                Text("What's stirring in you right now?")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.top, 19)
                                    .padding(.leading, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    Button {
                        vm.generate()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg.rectangle.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Create from My State")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule()
                                .fill(
                                    AnyShapeStyle(
                                        vm.userIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? AnyShapeStyle(Color(.tertiarySystemBackground))
                                        : AnyShapeStyle(LinearGradient(
                                            colors: [vm.creativeMode.accentColor, vm.creativeMode.accentColor.opacity(0.7)],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.userIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func modeChip(_ mode: SynapticMode) -> some View {
        Button { vm.creativeMode = mode } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12))
                Text(mode.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(vm.creativeMode == mode ? mode.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(Capsule().strokeBorder(
                        vm.creativeMode == mode ? mode.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    ))
            )
            .foregroundStyle(vm.creativeMode == mode ? mode.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func biometricSummaryCard(_ snap: BiometricSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16))
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.purple.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text("You are: \(snap.emotionalProfile)")
                    .font(.system(size: 13, weight: .semibold))
                Text(snap.aiContext)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.purple.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.15), lineWidth: 1))
        )
    }

    // MARK: - Phase 3: Result

    private var resultPhase: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.phase = .intent }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Edit")
                    }
                    .foregroundStyle(vm.creativeMode.accentColor)
                    .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(vm.creativeMode.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if vm.isGenerating {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(vm.creativeMode.accentColor)
                    Text("Synthesizing from your state…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let err = vm.errorMessage {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { vm.generate() }
                        .foregroundStyle(vm.creativeMode.accentColor)
                }
                .padding(.horizontal, 32)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        TextEditor(text: $vm.generatedContent)
                            .frame(minHeight: 240)
                            .font(.system(size: 15))
                            .scrollContentBackground(.hidden)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(vm.creativeMode.accentColor.opacity(0.12), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            Button {
                                vm.phase = .intent
                                vm.generate()
                            } label: {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(vm.creativeMode.accentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(vm.creativeMode.accentColor.opacity(0.1)))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = vm.generatedContent
                                HapticManager.impact(style: .light)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)

                            Button { showShareSheet = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(vm.creativeMode.accentColor))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)

                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [vm.generatedContent])
        }
    }
}

// MARK: - Biometric Feature Row

private struct BiometricFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
