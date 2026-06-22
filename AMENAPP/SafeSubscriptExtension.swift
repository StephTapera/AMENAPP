// SafeSubscriptExtension.swift
// AMEN — Single canonical safe-subscript for Array.
// All per-file private copies removed; this is the module-wide definition.

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
