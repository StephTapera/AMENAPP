# Selah Button Inventory

Every interactive Selah control must be registered here in the same change that adds it.

| Control | Handler | Effect | Test |
|---|---|---|---|
| `SelahLensBar.understandButton` / `selahLens.understandButton` | `SelahLensBar.dispatch(.understand)` → reader `onStudySheet` | Presents `BereanStudySheetView`; calls `bereanStudySheet2`; renders four study layers and cross-reference chips. | `SelahScriptureReaderUITests.testSelahLensUnderstandOpensStudySheet` |
| `SelahLensBar.crossReferencesButton` / `selahLens.crossReferencesButton` | `SelahLensBar.dispatch(.crossReferences)` → reader `onCrossRefs` | Presents deeper study/cross-reference surface for the selected verse. | `SelahScriptureReaderUITests.testSelahLensCrossRefsOpensStudySurface` |
| `SelahLensBar.reflectButton` / `selahLens.reflectButton` | `SelahLensBar.dispatch(.reflect)` → reader `onReflect` | Opens `SelahReflectionComposerView` with selected verse id/translation; save runs `classifySafety2` and writes `reflections`. | `SelahScriptureReaderUITests.testSelahLensReflectSavesPrivateReflection` |
| `SelahLensBar.prayButton` / `selahLens.prayButton` | `SelahLensBar.dispatch(.pray)` → reader `onPray` | Switches reader to prayer mode for the selected verse. | `SelahScriptureReaderUITests.testSelahLensPraySwitchesToPrayerMode` |
| `SelahLensBar.addToSessionButton` / `selahLens.addToSessionButton` | `SelahLensBar.dispatch(.addToSession)` → reader `onAddToSession` | Presents `GuidedSelahSessionView`; creates/resumes `guidedSessions`. | `SelahScriptureReaderUITests.testGuidedSelahSessionAdvances` |
| `selahLens.dismissButton` | `SelahLensBar.dismissButton` | Clears selected verse and hides Selah Lens. | `SelahScriptureReaderUITests.testSelahLensDismissHidesBar` |
| `studySheet.crossRef.*` | `BereanStudySheetView.onCrossRefTapped` | Dismisses sheet and asks reader to navigate to the referenced verse id. | `SelahScriptureReaderUITests.testStudySheetCrossReferenceNavigates` |
| `reflection.saveButton` | `SelahReflectionViewModel.save()` | Runs safety classification, persists private reflection, blocks sensitive sharing. | `SelahScriptureReaderUITests.testSelahLensReflectSavesPrivateReflection` |
| `reflection.shareScope.*` | `SelahReflectionViewModel.updateShareScope(_:)` | Explicitly changes share scope only when safety allows sharing. | `SelahScriptureReaderUITests.testReflectionShareScopeIsExplicit` |
| `guidedSession.backButton` | `GuidedSelahSessionViewModel.goBack()` | Persists previous guided-session step. | `SelahScriptureReaderUITests.testGuidedSelahSessionAdvances` |
| `guidedSession.nextButton` | `GuidedSelahSessionViewModel.goNext()` | Persists next guided-session step. | `SelahScriptureReaderUITests.testGuidedSelahSessionAdvances` |
| `guidedSession.skipButton` | `GuidedSelahSessionViewModel.skipCurrentStep()` | Persists skipped guided-session step transition. | `SelahScriptureReaderUITests.testGuidedSelahSessionSkipMovesForward` |
| `guidedSession.finishButton` | `GuidedSelahSessionViewModel.finish()` | Marks session complete in `guidedSessions`. | `SelahScriptureReaderUITests.testGuidedSelahSessionFinishCompletes` |
