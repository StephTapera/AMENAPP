// ScriptureIntelligenceView.swift — Notes reference detection UI (Wave 1: Lane E)
//
// SKELETON — Wave 0 placeholder. Lane E owns this directory.
// Do not edit from outside Lane E.
//
// Contract: see Docs/Capabilities/CONTRACTS.md §2.5, §3.4

import SwiftUI

// Wave 1: Lane E implements:
//   ScriptureIntelligenceView   — verse card popover in Smart Church Notes block editor
//   Detection runner            — debounced 800ms on block-commit, cancel-on-edit
//   Translation switcher        — BSB / WEB / KJV
//   Insert-as-block action      — appends verse text block to note
// All wired to scripture_detectReferences + scripture_getVerses callables
