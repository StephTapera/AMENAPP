// ContextSettingsView.swift — Context grant settings UI (Wave 1: Lane C)
//
// SKELETON — Wave 0 placeholder. Lane C owns this directory.
// Do not edit from outside Lane C.
//
// Contract: see Docs/Capabilities/CONTRACTS.md §2.1, §3.1

import SwiftUI

// Wave 1: Lane C implements:
//   ContextSettingsView     — lists all ContextSource items with current policy
//   Policy picker per row   — never / ask every time / while using / always
//   Device-level sources    — calendar, location shown as "Coming soon" (not yet supported)
//   Wired to contextEngine_getGrants + contextEngine_setGrant callables
