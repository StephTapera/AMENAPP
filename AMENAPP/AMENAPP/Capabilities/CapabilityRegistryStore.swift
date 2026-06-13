// CapabilityRegistryStore.swift — Client registry store (Wave 1: Lane C)
//
// SKELETON — Wave 0 placeholder. Lane C owns this file.

import Foundation

// Wave 1: Lane C implements CapabilityRegistryStore as @MainActor ObservableObject
// Listens to `capabilities` Firestore collection + user's `capabilityState`
// Exposes: capabilities(for surface: CapabilitySurface) -> [Capability]
// Cache: Firestore offline persistence (no custom cache layer)
