/// DebugLog.swift
/// AMENAPP
///
/// Lightweight debug-only logging.
/// `dlog()` compiles to a complete no-op in Release builds, eliminating the
/// synchronous stderr write overhead of bare `print()` on hot paths (feed cells,
/// snapshot listeners, message threads).
///
/// Usage:
///   dlog("message")           -- replaces print("message")
///   dlog("value: \(val)")     -- string interpolation is only evaluated in DEBUG
///
/// Migration: replace `print(` with `dlog(` in production files.
/// Debug-only tools (AuthDebugView, DeveloperMenuView, etc.) can keep using print().

@inline(__always)
nonisolated func dlog(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    line: UInt = #line
) {
    #if DEBUG
    print(message())
    #endif
}
