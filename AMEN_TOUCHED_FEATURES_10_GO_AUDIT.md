# AMEN Touched Features 10 GO Audit

## Executive Status

**GO WITH CAVEATS**

The touched-feature implementation is materially stronger than the prior state: production "coming soon" UI is removed, payment is StoreKit-backed, covenant settings/guidelines persist to Firestore, Berean media actions open real picker/camera flows, calendar export has permission/duplicate handling, Legacy Studio exports a real PDF, and focused regression tests pass.

This is not marked full **GO** because:

- Full `RunAllTests` did not complete before the Xcode MCP 120s timeout.
- Direct `xcodebuild` validation is blocked by sandbox permissions against DerivedData/SwiftPM caches and CoreSimulator is unavailable from the shell.
- Existing UI test files are present on disk, but the shared `AMENAPP` scheme only includes `AMENAPPTests`, not a UI test bundle.
- Firebase rules dry-run compiled successfully, but the Firebase CLI exited with auth/config update errors after the dry-run due local credentials/cache permissions.

## Files Inspected

- `firebase.json`
- `AMENAPP.xcodeproj/xcshareddata/xcschemes/AMENAPP.xcscheme`
- `AMENAPP/firestore.deploy.rules`
- `AMENAPP/Info.plist`
- `AMENAPP/BereanAttachmentPickerSheet.swift`
- `AMENAPP/BereanHomeView.swift`
- `AMENAPP/BereanChatView.swift`
- `AMENAPP/AMENAPP/BereanConversationView.swift`
- `AMENAPP/AMENAPP/BereanStudyHomeView.swift`
- `AMENAPP/MentorshipPlanSheet.swift`
- `AMENAPP/AMENAPP/MentorModel.swift`
- `AMENAPP/AMENAPP/MentorshipService.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantManageView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantModerationView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantEventsView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantViewModel.swift`
- `AMENAPP/LegacyStudioView.swift`
- `AMENAPP/AMENAPP/AmenMessageSaveActionsSheet.swift`
- `AMENAPP/Creator/Views/CreatorMediaPickerView.swift`
- `AMENAPPTests/AmenTouchedFeatures10GoTests.swift`
- `AMENAPPUITests 2/AmenTouchedFeatures10GoUITests.swift`
- `Backend/functions/package.json`

## Files Changed

- `AmenStoreKit.storekit`
- `AMENAPP.xcodeproj/xcshareddata/xcschemes/AMENAPP.xcscheme`
- `AMENAPP/firestore.deploy.rules`
- `AMENAPP/Info.plist`
- `AMENAPP/BereanAttachmentPickerSheet.swift`
- `AMENAPP/BereanHomeView.swift`
- `AMENAPP/BereanChatView.swift`
- `AMENAPP/AMENAPP/BereanConversationView.swift`
- `AMENAPP/AMENAPP/BereanStudyHomeView.swift`
- `AMENAPP/MentorshipPlanSheet.swift`
- `AMENAPP/AMENAPP/MentorModel.swift`
- `AMENAPP/AMENAPP/MentorshipService.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantManageView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantModerationView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantEventsView.swift`
- `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantViewModel.swift`
- `AMENAPP/LegacyStudioView.swift`
- `AMENAPP/AMENAPP/AmenMessageSaveActionsSheet.swift`
- `AMENAPP/Creator/Views/CreatorMediaPickerView.swift`
- `AMENAPPTests/AmenTouchedFeatures10GoTests.swift`
- `AMENAPPUITests 2/AmenTouchedFeatures10GoUITests.swift`
- `AMEN_TOUCHED_FEATURES_10_GO_AUDIT.md`

## StoreKit Configuration Status

Added `AmenStoreKit.storekit` with local subscriptions:

- `amen.mentorship.growth.monthly`
- `amen.mentorship.deep.monthly`

Updated the shared `AMENAPP.xcscheme` to reference `container:AmenStoreKit.storekit` for launch/test actions.

`MentorshipPlanSheet` uses StoreKit 2 product loading, purchase, verification, cancellation, pending, failure, and restore handling. Successful paid purchases call `MentorshipService.finalizeStoreKitRelationship(...)`.

Manual App Store Connect setup is still required for production product availability.

## Firestore Rules Status

`firebase.json` confirms the active Firestore rules path is:

```text
AMENAPP/firestore.deploy.rules
```

The covenant settings/guideline rule was added to that active file. It allows only covenant creator/admin updates and only for these fields:

- `settings`
- `settingsUpdatedAt`
- `settingsUpdatedBy`
- `moderationGuidelines`
- `moderationGuidelinesUpdatedAt`
- `moderationGuidelinesUpdatedBy`

Validation:

- `firebase deploy --only firestore:rules --dry-run` via local `npx firebase-tools` compiled `AMENAPP/firestore.deploy.rules` successfully.
- The Firebase CLI then exited with auth/config-cache errors. Rules are deploy-ready, but deployment requires `firebase login --reauth` or CI credentials.

## UI Test Coverage Matrix

Added `AMENAPPUITests 2/AmenTouchedFeatures10GoUITests.swift` covering:

- Daily Prayer weekly theme selection and copy.
- Berean Home attachment picker.
- Berean Chat camera/media or permission state.
- Berean Conversation attachment picker.
- Berean Study voice/camera prompt or picker state.
- Creator Insights analytics navigation.
- ScriptureDNA Word Map.
- Mentorship paid plan StoreKit/loading/unavailable state.
- Covenant settings, guidelines, calendar export.
- Legacy PDF export.
- Reel save/share/export.
- QuoteForge save/share/export.
- Find Friends surface.
- Back/dismiss behavior.

Caveat: the shared scheme currently has no UI test bundle in `TestAction`; it only includes `AMENAPPTests`. The UI test source exists, but simulator UI validation cannot be claimed until the UI test target is added to the scheme/test plan.

## Button / Action Matrix

| Area | Final status |
|---|---|
| Berean attachment buttons | Open document/photo/camera picker sheet. |
| Berean camera buttons | Open camera flow or safe unavailable state. |
| Mentorship paid plans | StoreKit 2 purchase path; no fake purchase success. |
| Covenant settings | Loads/saves Firestore settings with loading/error/saved UI. |
| Covenant guidelines | Loads/saves Firestore guideline array with editor state. |
| Covenant calendar export | EventKit write request, duplicate prevention, missing-calendar handling. |
| Legacy export | Generates real PDF and opens system share sheet. |
| Creator media picker | Replaced visible placeholder with PhotosPicker. |
| Disabled save destinations | No "coming soon"; disabled state says setup is required. |

## Navigation / Back Matrix

| Flow | Back/dismiss status |
|---|---|
| Attachment picker sheets | Native sheet dismissal. |
| Camera/media picker | Native picker/camera dismissal. |
| Mentorship plan sheet | Existing sheet dismissal; StoreKit cancellation handled. |
| Covenant settings sheet | Native sheet dismissal. |
| Covenant guideline editor | Native sheet dismissal. |
| Legacy export share sheet | Native share sheet dismissal. |
| Covenant post detail route | Real detail destination via `AmenCovenantPostRouteDetailView`. |

## EmptyView / fatalError Classification

| Hit | Classification |
|---|---|
| `AmenLiquidGlassSpiritualReactionSimulation.swift:892` | Safe visual no-effect fallback. |
| `AmenContextualReactionEffectHost.swift:32,34` | Safe hidden/no-effect rendering. |
| `AmenSafetyOSReactionEngine.swift:820` | Safe no-effect rendering. |
| `AmenSmartPillRow.swift:16` | Safe empty collection rendering. |
| `AmenTranslationMessageView.swift:22` | Safe hidden state for disabled/not-needed translation. |
| `BereanComposerActionPills.swift:19` | Safe empty collection rendering. |
| `BereanExternalContextSheet.swift:175` | Safe empty optional section. |
| `BereanStudyHomeView.swift:713` | Required switch fallback for current tab layout. |
| `ChurchNotesSessionView.swift:260` | Safe branch for no presentation. |
| `AmenMentionTextView.swift:66` | Coder initializer only; not used by SwiftUI programmatic init. |
| `CreatePostMediaMetadataViews.swift:139,166` | Safe unsupported metadata pane fallback. |
| `GetReadyView.swift:1489` | Safe hidden state. |
| `HomeView.swift:1050` | Safe loaded branch after loader swaps to real content. |
| `LocalPostDraft.swift:232` | Last-resort SwiftData invariant; production risk only if persistent and in-memory containers both fail. |
| `LocalSelahSession.swift:168` | Last-resort SwiftData invariant; production risk only if persistent and in-memory containers both fail. |
| `SelahSessionShapingCard.swift:79,215` | Safe dismissed state. |
| `TrueSourceLabelChip.swift:206` | Safe empty collection rendering. |
| `CreatorMediaThumbnail.swift:32` | Required `@unknown default` media fallback. |
| `CreatorEditorView.swift:47,83` | Required `@unknown default` media fallback. |

No scan hit was identified as a touched-feature production blocker after the Creator media placeholder was fixed.

## Scan Results

Commands:

```bash
git grep -n -i "coming soon" -- 'AMENAPP/**/*.swift' || true
git grep -n -E "Button[[:space:]]*\\{[[:space:]]*\\}|Button[[:space:]]*\\([[:space:]]*action:[[:space:]]*\\{[[:space:]]*\\}" -- 'AMENAPP/**/*.swift' || true
git grep -n -E "placeholder UI|fake production metrics|alert placeholder|Media picker placeholder" -- 'AMENAPP/**/*.swift' || true
git grep -n -E "disabled\\(.*plan|plan.*disabled|isUnavailable\\(.*plan" -- 'AMENAPP/**/*.swift' || true
```

Results:

- `coming soon`: 0 production Swift matches.
- Empty visible `Button { }`: 0 matches.
- `placeholder UI`, `fake production metrics`, `alert placeholder`, `Media picker placeholder`: 0 matches.
- Disabled paid plan pattern: 0 matches.

## Validation Commands And Results

### iOS / Xcode

```text
Xcode MCP BuildProject
```

Result: **Passed**. Project built successfully in 82.469s.

```text
Xcode MCP RunSomeTests:
- AmenTouchedFeatures10GoTests/paidMentorshipPlansDeclareStoreKitProductIds()
- AmenTouchedFeatures10GoTests/legacyPDFExportCreatesShareableArtifact()
- AmenTouchedFeatures10GoTests/bereanAttachmentResultsHaveComposerPrompts()
```

Result: **3 passed, 0 failed**.

```text
Xcode MCP RunAllTests
```

Result: **Timed out after 120s**. No pass/fail claim made.

```bash
xcodebuild -scheme AMENAPP -showdestinations
```

Result: **Blocked by environment**:

- CoreSimulatorService unavailable.
- Operation not permitted writing DerivedData/SwiftPM cache files.

### Backend

```bash
npm install
npm run build
npx tsc --noEmit
npm test
```

Run from `Backend/functions`.

Results:

- `npm install`: passed, 10 low severity audit warnings.
- `npm run build`: passed.
- `npx tsc --noEmit`: passed.
- `npm test`: **28 test suites passed, 619 tests passed**.

### Firestore Rules

```bash
PATH=/opt/homebrew/bin:/usr/local/bin:$PATH npm_config_cache=/private/tmp/amen-npm-cache npx firebase-tools deploy --only firestore:rules --dry-run
```

Result:

- Active rules file compiled successfully: `AMENAPP/firestore.deploy.rules`.
- Dry run completed.
- CLI exited with auth/config update error afterward. Deployment still requires valid Firebase auth.

## Remaining Manual Setup

- Add/confirm App Store Connect products:
  - `amen.mentorship.growth.monthly`
  - `amen.mentorship.deep.monthly`
- Ensure Xcode scheme/test plan includes an actual UI test bundle for `AMENAPPUITests 2`.
- Reauth Firebase before deployment:
  - `firebase login --reauth`
- Deploy rules after auth:
  - `firebase deploy --only firestore:rules`
- Run full unit/UI tests in Xcode once the tool timeout/CoreSimulator issue is resolved.

## Final Recommendation

Ship readiness is **GO WITH CAVEATS**.

The app is no longer blocked by touched-feature placeholder UI, fake payment flow, missing covenant persistence, missing calendar handling, or text-only Legacy export. The remaining blockers to full 10/10 GO are validation and environment/configuration items: full test completion, runnable UI test target inclusion, Firebase auth for rules deployment, and production StoreKit product setup.
