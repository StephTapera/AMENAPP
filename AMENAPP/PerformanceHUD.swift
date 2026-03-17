//
//  PerformanceHUD.swift
//  AMENAPP
//
//  Dev-only performance overlay and logging utilities.
//  Compiled out in Release builds via #if DEBUG guards.
//
//  Usage — attach to the root view in AMENAPPApp.swift:
//    .overlay(alignment: .topTrailing) { PerformanceHUD() }
//
//  os_signpost intervals are named so Instruments can show them in
//  the "Points of Interest" track without any extra configuration.
//

import SwiftUI
import Combine
import os

// MARK: - Signpost log (shared singleton)

/// Lightweight instrumentation points. Use these anywhere in the codebase
/// to mark the start/end of operations you want to profile in Instruments.
///
/// Example:
///   PerformanceLog.begin("load-feed", "HomeFeed")
///   // … work …
///   PerformanceLog.end("load-feed", "HomeFeed")
enum PerformanceLog {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.amen.app",
                                   category: "Performance")

    /// Begin a signpost interval.
    static func begin(_ name: StaticString, _ message: String = "") {
#if DEBUG
        os_signpost(.begin, log: log, name: name, "%{public}s", message)
#endif
    }

    /// End a signpost interval.
    static func end(_ name: StaticString, _ message: String = "") {
#if DEBUG
        os_signpost(.end, log: log, name: name, "%{public}s", message)
#endif
    }

    /// Emit a single event marker (for taps, state transitions, etc.)
    static func event(_ name: StaticString, _ message: String = "") {
#if DEBUG
        os_signpost(.event, log: log, name: name, "%{public}s", message)
#endif
    }
}

// MARK: - PerformanceHUD View

#if DEBUG
/// Floating overlay that shows live memory, FPS, and active-listener counts.
/// Attach to the root ZStack or use the `.performanceHUD()` view modifier.
struct PerformanceHUD: View {
    @StateObject private var monitor = PerformanceMonitor()

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            label("MEM", value: monitor.memoryMB, unit: "MB",
                  bad: monitor.memoryMB > 300)
            label("FPS", value: Double(monitor.fps), unit: "",
                  bad: monitor.fps < 50)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(6)
        .background(.black.opacity(0.65))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .allowsHitTesting(false)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func label(_ title: String, value: Double, unit: String, bad: Bool) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.gray)
            Text(String(format: "%.0f%@", value, unit))
                .foregroundStyle(bad ? .red : .green)
        }
    }
}

// MARK: - PerformanceMonitor

@MainActor
private final class PerformanceMonitor: ObservableObject {
    @Published var memoryMB: Double = 0
    @Published var fps: Int = 0

    private var displayLink: CADisplayLink?
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0

    func start() {
        // CADisplayLink for FPS
        displayLink = CADisplayLink(target: DisplayLinkTarget { [weak self] link in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.lastTimestamp == 0 {
                    self.lastTimestamp = link.timestamp
                }
                self.frameCount += 1
                let elapsed = link.timestamp - self.lastTimestamp
                if elapsed >= 1.0 {
                    self.fps = Int(Double(self.frameCount) / elapsed)
                    self.frameCount = 0
                    self.lastTimestamp = link.timestamp
                }
            }
        }, selector: #selector(DisplayLinkTarget.tick(_:)))
        displayLink?.add(to: .main, forMode: .common)

        // Timer to sample memory every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.memoryMB = Self.currentMemoryMB()
            }
        }
        timer?.fire()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }

    private static func currentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

// CADisplayLink needs an ObjC target; this helper avoids strong captures.
private final class DisplayLinkTarget: NSObject {
    private let block: (CADisplayLink) -> Void
    init(_ block: @escaping (CADisplayLink) -> Void) { self.block = block }
    @objc func tick(_ link: CADisplayLink) { block(link) }
}

// MARK: - View Modifier

extension View {
    /// Attaches the PerformanceHUD as a top-trailing overlay. No-op in Release.
    func performanceHUD() -> some View {
        overlay(alignment: .topTrailing) { PerformanceHUD() }
    }
}

// MARK: - Preview

#Preview("PerformanceHUD") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        Text("App content here")
    }
    .performanceHUD()
}
#endif
