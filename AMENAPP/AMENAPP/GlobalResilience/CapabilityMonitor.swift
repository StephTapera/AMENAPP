// CapabilityMonitor.swift
// AMEN — Global Resilience System
// Observes device + network capability and syncs a DeviceCapabilityProfile to Firestore.

import Foundation
import Network
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - CapabilityMonitor

@MainActor
final class CapabilityMonitor: ObservableObject {

    // MARK: Singleton

    static let shared = CapabilityMonitor()

    // MARK: Published State

    @Published var profile: DeviceCapabilityProfile

    // MARK: User Override

    /// When set to anything other than .automatic, overrides effectiveDataMode.
    var userOverride: DataMode = .automatic {
        didSet { rebuildProfile() }
    }

    // MARK: Private State

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.amen.capabilitymonitor.network", qos: .utility)

    private var currentPath: NWPath?
    private var thermalObservation: NSKeyValueObservation?
    private var powerStateObserver: NSObjectProtocol?

    private var syncTask: Task<Void, Never>?

    private let deviceId: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

    // MARK: Init

    private init() {
        // Build a placeholder profile synchronously so @Published is never nil.
        self.profile = CapabilityMonitor.buildInitialProfile()
        startMonitoring()
    }

    deinit {
        pathMonitor.cancel()
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        thermalObservation?.invalidate()
        syncTask?.cancel()
    }

    // MARK: Start Monitoring

    private func startMonitoring() {
        // Network path monitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.currentPath = path
                self.rebuildProfile()
            }
        }
        pathMonitor.start(queue: pathQueue)

        // Low power mode — NSProcessInfoPowerStateDidChangeNotification
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.rebuildProfile()
            }
        }

        // Thermal state KVO
        thermalObservation = ProcessInfo.processInfo.observe(
            \.thermalState,
            options: [.new]
        ) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.rebuildProfile()
            }
        }

        // Seed an initial profile after monitoring is wired up.
        rebuildProfile()
    }

    // MARK: Profile Construction

    private func rebuildProfile() {
        let path = currentPath
        let networkClass = CapabilityMonitor.networkClass(for: path)
        let isConstrained = path?.isConstrained ?? false
        let isExpensive = path?.isExpensive ?? false
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = CapabilityMonitor.thermalString(ProcessInfo.processInfo.thermalState)
        let storage = CapabilityMonitor.measureStoragePressure()
        let model = UIDevice.current.modelIdentifier
        let tier = CapabilityMonitor.deviceTier(for: model)

        let effective = effectiveDataMode(
            isConstrained: isConstrained,
            lowPower: lowPower
        )

        let newProfile = DeviceCapabilityProfile(
            platform: "ios",
            deviceModel: model,
            deviceTier: tier,
            networkClass: networkClass,
            isConstrainedPath: isConstrained,
            isExpensivePath: isExpensive,
            lowPowerModeEnabled: lowPower,
            thermalState: thermal,
            storagePressure: storage,
            dataMode: effective,
            preferredLanguages: Locale.preferredLanguages,
            sharedDeviceMode: false,
            updatedAt: Date()
        )

        let oldMode = profile.dataMode
        profile = newProfile

        NotificationCenter.default.post(name: .capabilityProfileChanged, object: newProfile)
        if newProfile.dataMode != oldMode {
            NotificationCenter.default.post(name: .dataModeChanged, object: newProfile)
        }

        scheduleDebouncedSync()
    }

    // MARK: Effective Data Mode

    private func effectiveDataMode(isConstrained: Bool, lowPower: Bool) -> DataMode {
        guard userOverride == .automatic else { return userOverride }
        if isConstrained || lowPower { return .lowData }
        return .standard
    }

    // MARK: Debounced Firestore Sync

    private func scheduleDebouncedSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            } catch {
                return // Task was cancelled — that's expected on rapid updates.
            }
            await self?.syncToFirestore()
        }
    }

    private func syncToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = await MainActor.run { profile }
        let db = Firestore.firestore()
        let ref = db
            .collection("users")
            .document(uid)
            .collection("devices")
            .document(deviceId)

        do {
            let data: [String: Any] = [
                "platform": snapshot.platform,
                "deviceModel": snapshot.deviceModel,
                "deviceTier": snapshot.deviceTier.rawValue,
                "networkClass": snapshot.networkClass.rawValue,
                "isConstrainedPath": snapshot.isConstrainedPath,
                "isExpensivePath": snapshot.isExpensivePath,
                "lowPowerModeEnabled": snapshot.lowPowerModeEnabled,
                "thermalState": snapshot.thermalState,
                "storagePressure": snapshot.storagePressure.rawValue,
                "dataMode": snapshot.dataMode.rawValue,
                "preferredLanguages": snapshot.preferredLanguages,
                "sharedDeviceMode": snapshot.sharedDeviceMode,
                "updatedAt": Timestamp(date: snapshot.updatedAt)
            ]
            try await ref.setData(data, merge: true)
        } catch {
            // Non-fatal — capability sync is best-effort.
        }
    }

    // MARK: Static Helpers

    private static func buildInitialProfile() -> DeviceCapabilityProfile {
        let model = UIDevice.current.modelIdentifier
        return DeviceCapabilityProfile(
            platform: "ios",
            deviceModel: model,
            deviceTier: deviceTier(for: model),
            networkClass: .standard,
            isConstrainedPath: false,
            isExpensivePath: false,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: thermalString(ProcessInfo.processInfo.thermalState),
            storagePressure: measureStoragePressure(),
            dataMode: .standard,
            preferredLanguages: Locale.preferredLanguages,
            sharedDeviceMode: false,
            updatedAt: Date()
        )
    }

    private static func networkClass(for path: NWPath?) -> NetworkClass {
        guard let path, path.status == .satisfied else { return .offline }
        if path.isConstrained { return .constrained }
        if path.isExpensive { return .expensive }
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return .fast
        }
        return .standard
    }

    private static func thermalString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
    }

    private static func measureStoragePressure() -> StorageTier {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let url = urls.first,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else {
            return .medium
        }
        let gb = Double(available) / 1_073_741_824.0
        switch gb {
        case ..<0.5:  return .critical
        case 0.5..<2: return .low
        case 2..<10:  return .medium
        default:      return .ample
        }
    }

    // MARK: Device Tier Lookup

    private static func deviceTier(for identifier: String) -> DeviceTier {
        // Low-tier models (iPhone SE 1st gen, 6s, 7, 8, X)
        let lowPrefixes: [String] = [
            "iPhone8,4",              // SE 1st gen
            "iPhone8,1", "iPhone8,2", // 6s, 6s Plus
            "iPhone9,1", "iPhone9,2", "iPhone9,3", "iPhone9,4", // 7, 7 Plus
            "iPhone10,1", "iPhone10,2", "iPhone10,3",
            "iPhone10,4", "iPhone10,5", "iPhone10,6", // 8, 8 Plus, X
        ]

        // Mid-tier models (XR, XS, 11, 12, SE 2nd/3rd gen, 13)
        let midPrefixes: [String] = [
            "iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8", // XS, XS Max, XR
            "iPhone12,1", "iPhone12,3", "iPhone12,5",               // 11, 11 Pro, 11 Pro Max
            "iPhone12,8",                                            // SE 2nd gen
            "iPhone13,1", "iPhone13,2", "iPhone13,3", "iPhone13,4", // 12 mini/12/12 Pro/12 Pro Max
            "iPhone14,4", "iPhone14,5",                              // 13 mini, 13
            "iPhone14,6",                                            // SE 3rd gen
            "iPhone14,7", "iPhone14,8",                              // 13 Pro, 13 Pro Max (legacy names)
        ]

        // High-tier: iPhone 14 and later (also catches Simulator and unknown future devices)
        // We match by prefix so that e.g. "iPhone15,2" falls through to high.

        if lowPrefixes.contains(identifier) { return .low }
        if midPrefixes.contains(identifier) { return .mid }

        // Simulator or unknown — treat as high to avoid degraded UX.
        return .high
    }
}

// MARK: - UIDevice Model Identifier

private extension UIDevice {
    /// Returns the raw hardware model string via sysctlbyname, e.g. "iPhone15,2".
    var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
