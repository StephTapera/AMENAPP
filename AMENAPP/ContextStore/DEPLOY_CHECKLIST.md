# BLOCKED_exportviews.md
## Wave 5 — AmenExportService + AmenExportView

**Date:** 2026-06-10
**Status:** Three-strikes protocol triggered (error 5 × 3 on both files)

---

### What happened

`XcodeRefreshCodeIssuesInFile` returned `SourceEditor.SourceEditorCallableDiagnosticError error 5`
on all three attempts for both new files:

- `AMENAPP/ContextStore/AmenExportService.swift`
- `AMENAPP/ContextStore/AmenExportView.swift`

Per the task specification, this is the **known indexer artifact for brand-new files** that have not
yet been added to the Xcode project's `.pbxproj`. It is NOT a code error.

---

### Manual type-reference audit result: PASS

All types, enums, properties, and methods referenced in both files were verified against the
frozen canonical model and the existing codebase. Every reference is accounted for:

| Symbol | Source file | Status |
|---|---|---|
| `ContextFacet`, `FacetCategory`, `Visibility`, `EncryptionTier` | `ContextStoreModels.swift` | VERIFIED |
| `ContextTierTable.tier(for:key:)` | `ContextStoreModels.swift` | VERIFIED |
| `Provenance`, `FacetSource`, `StructuredFacetValue` | `ContextStoreModels.swift` | VERIFIED |
| `AMENFeatureFlags.shared.contextSystemEnabled` | `AMENFeatureFlags.swift` (line 222) | VERIFIED |
| `AMENFeatureFlags.shared.contextExportEnabled` | `AMENFeatureFlags.swift` (line 232) | VERIFIED |
| `ContextStoreService.shared.loadFacets()` | `ContextStoreService.swift` (line 187) | VERIFIED |
| `ContextStoreService.shared.facets` | `ContextStoreService.swift` (line 73) | VERIFIED |
| `FacetApprovalView(candidates:)` | `FacetApprovalView.swift` | VERIFIED |
| `ContextUnavailableNotice` | `ManualFacetEntryView.swift` (line 513) | VERIFIED |
| `AmenLiquidGlassPillButton` | `AmenLiquidGlassComponents.swift` | VERIFIED |
| `AmenGlassMetrics.cornerRadius*`, `.borderWidth`, `.shadowRadius` | `AmenGlassDesignTokens.swift` | VERIFIED |
| `Motion.adaptive(_:)`, `Motion.springRelease`, etc. | `Motion.swift` | VERIFIED |
| `Functions.functions()`, `.httpsCallable(_:).call(_:)` | `FirebaseFunctions` (SDK) | VERIFIED |
| `Auth.auth().currentUser?.uid` | `FirebaseAuth` (SDK) | VERIFIED |

---

### What the human operator must do

1. **Add both files to the Xcode project target** (AMENAPP target) via Xcode's "Add Files" or
   drag-and-drop into the ContextStore group — this resolves the error 5 / indexer artifact.

2. **Re-run `XcodeRefreshCodeIssuesInFile`** on both files after they are in the `.pbxproj`.
   Expected result: 0 errors, 0 warnings.

3. **Deploy the Cloud Functions** if not already done:
   - `functions/context/exportAmenFile.ts` → `exportAmenFile` callable
   - `functions/context/signAmenExport.ts` → `signAmenExport` callable
   - Set the `AMEN_EXPORT_ED25519_PRIVATE_KEY` secret via `firebase functions:secrets:set`

4. **Enable flags** in Firebase Remote Config when ready:
   - `context_system_enabled` → true
   - `context_export_enabled` → true

---

### Files created (do not delete)

- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ContextStore/AmenExportService.swift`
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ContextStore/AmenExportView.swift`
