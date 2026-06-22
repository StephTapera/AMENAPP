// CapabilityComposerCoordinator.swift
// AMEN Capabilities v1 — @ trigger coordinator (Wave 1: Lane C)
//
// Detects "@" at a word boundary in a wired composer, shows the capability
// picker, and routes selection to the appropriate entry flow.
//
// Contract: Docs/Capabilities/CONTRACTS.md §8

import SwiftUI
import Combine

// MARK: - CapabilityComposerCoordinator

@MainActor
final class CapabilityComposerCoordinator: ObservableObject {

    // MARK: Published state

    @Published var isPickerVisible = false
    @Published var selectedCapability: Capability?

    // MARK: Surface

    let surface: CapabilitySurface

    // MARK: Private state

    /// Tracks the cursor position at the time the "@" was detected,
    /// so we know where to insert content later.
    private var atSignCursorPosition: Int = 0

    // MARK: Init

    init(surface: CapabilitySurface) {
        self.surface = surface
    }

    // MARK: - Public API

    /// Call this every time the composer text changes.
    ///
    /// Shows the picker when:
    /// - `capabilityPickerEnabled` flag is ON, AND
    /// - the character at `cursorPosition - 1` is "@", AND
    /// - the character before that "@" is whitespace or there is none (word boundary).
    func handleTextChange(_ text: String, cursorPosition: Int) {
        guard AMENFeatureFlags.shared.capabilityPickerEnabled else {
            if isPickerVisible { isPickerVisible = false }
            return
        }

        // cursorPosition is the offset (in UTF-16 code units) after the last typed character.
        guard cursorPosition > 0 else {
            isPickerVisible = false
            return
        }

        let utf16 = text.utf16
        let atIndex = utf16.index(utf16.startIndex, offsetBy: cursorPosition - 1,
                                  limitedBy: utf16.endIndex) ?? utf16.endIndex
        guard atIndex < utf16.endIndex,
              utf16[atIndex] == UInt16(UnicodeScalar("@").value) else {
            // The character just before the cursor is not "@" — hide picker.
            if isPickerVisible { isPickerVisible = false }
            return
        }

        // Check word boundary: character before "@" must be whitespace or absent.
        if atIndex > utf16.startIndex {
            let prevIndex = utf16.index(before: atIndex)
            let prevChar = utf16[prevIndex]
            // Allow: space (0x20), newline (0x0A, 0x0D), tab (0x09)
            let isWordBoundary = prevChar == 0x20 || prevChar == 0x0A || prevChar == 0x0D || prevChar == 0x09
            guard isWordBoundary else {
                if isPickerVisible { isPickerVisible = false }
                return
            }
        }
        // Cursor is immediately after "@" at a word boundary — show picker.
        atSignCursorPosition = cursorPosition
        isPickerVisible = true
    }

    /// Called when the user taps a capability row in the picker.
    func selectCapability(_ capability: Capability) {
        selectedCapability = capability
        isPickerVisible = false
        // Dispatch to the right entry flow based on the capability's entryFunction.
        // Inline capabilities (verse_lookup): insert a content token into the composer.
        // Sheet capabilities (prayer_os): present a sheet; composer stays open in bg.
        // The owning view observes `selectedCapability` and drives the appropriate flow.
    }

    /// Dismisses the picker without making a selection.
    func dismissPicker() {
        isPickerVisible = false
    }

    /// Inserts a content token or formatted string at the current @ cursor position.
    /// Callers (e.g. VerseLookupView result handler) should call this with the
    /// formatted text to splice into the composer.
    ///
    /// This method publishes the inserted content via `insertionRequest` so the
    /// owning view can apply it to the bound text field.
    func insertContent(_ content: String) {
        pendingInsertion = InsertionRequest(position: atSignCursorPosition, text: content)
    }

    // MARK: - Insertion pipeline

    /// Publishes pending insertion requests to the owning view.
    @Published private(set) var pendingInsertion: InsertionRequest?

    /// Acknowledges the last insertion request so it is not applied twice.
    func acknowledgeInsertion() {
        pendingInsertion = nil
    }
}

// MARK: - InsertionRequest

/// A value type describing a single text-insertion event.
struct InsertionRequest: Equatable {
    /// UTF-16 cursor position immediately after the "@" character.
    let position: Int
    /// Text to splice into the composer, replacing the "@" and any query prefix typed so far.
    let text: String
}
