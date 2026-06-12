# DEPLOYMENT_TODO.md — Berean Trust Architecture

## Session: 2026-06-12

| # | Item | Type | Action Required | Where | Blocking? | Status |
|---|------|------|----------------|-------|-----------|--------|
| 1 | ANTHROPIC_API_KEY | Secret | firebase functions:secrets:set ANTHROPIC_API_KEY | Terminal | Yes | Pending |
| 2 | GEMINI_API_KEY | Secret | firebase functions:secrets:set GEMINI_API_KEY | Terminal | Yes | Pending |
| 3 | BIBLE_API_KEY | Secret | firebase functions:secrets:set BIBLE_API_KEY | Terminal | Yes | Pending |
| 4 | Compile berean TypeScript | Deploy | cd functions && npx tsc --project berean/tsconfig.json | Terminal | Yes | Pending |
| 5 | Deploy all berean functions | Deploy | firebase deploy --only functions:bereanConstitutionalPipeline,functions:bereanGetMemory,functions:bereanDeleteMemory,functions:bereanToggleMemoryLock,functions:bereanUpdateMemory,functions:bereanDeleteAllMemory,functions:bereanSubmitFeedback,functions:bereanRunEvals | Terminal | Yes | Pending |
| 6 | Deploy Firestore rules | Deploy | firebase deploy --only firestore:rules | Terminal | Yes | Pending |
| 7 | Deploy Firestore indexes | Deploy | firebase deploy --only firestore:indexes | Terminal | Before launch | Pending |
| 8 | Enable feature flags (Remote Config) | Config | In Firebase Console → Remote Config, add: trustArchitecture_modelRouter=false, trustArchitecture_evidenceRetrieval=false, trustArchitecture_constitutionalPipeline=false, trustArchitecture_memoryLayer=false, trustArchitecture_feedbackCapture=false. Publish. All default OFF. | Firebase Console | Before launch | Pending |
| 9 | Create Firestore feature flag doc | Config | Firebase Console → Firestore → featureFlags/trustArchitecture → add fields: modelRouter=false, evidenceRetrieval=false, constitutionalPipeline=false, memoryLayer=false, feedbackCapture=false | Firebase Console | Yes | Pending |
| 10 | Seed bereanTheologyCorpus | Config | Firebase Console → Firestore → bereanTheologyCorpus → seed with 5-10 documents (title, content, source, denomination fields) | Firebase Console | Before launch | Pending |
| 11 | Berean memory privacy disclosure | Manual | Update Privacy Policy: "Berean saves conversation context (preferences, study topics, prayer requests) to personalize AI responses. You can view, edit, delete, and lock this data at any time from Settings → Berean → Memory." | Website + App Store Connect | Before submission | Pending |
| 12 | PrivacyInfo.xcprivacy update | Manual | Add NSPrivacyAccessedAPITypeReasons for AI pipeline traces and feedback data storage. Declare data type: NSPrivacyCollectedDataTypeOtherAppUsageData (Berean response ratings). | Xcode → AMENAPP target | Before submission | Pending |
| 13 | Xcode target membership | Test on device | Add new Swift files to AMENAPP target in Xcode: BereanTrustBadge.swift, BereanEvidenceSheet.swift, BereanConstitutionalPipeline.swift, BereanMemoryView.swift, BereanFeedbackRating.swift | Xcode | Yes | Pending |
| 14 | Remote Config flag (iOS) | Config | Add Remote Config parameter: berean_constitutional_pipeline_enabled = false (String, default false). Publish. | Firebase Console → Remote Config | Yes | Pending |
| 15 | Blaze plan verification | Billing | Confirm Firebase project is on Blaze plan — required for Cloud Functions v2 and external API calls (Anthropic, Google AI) | Firebase Console → Usage & Billing | Yes | Pending |
| 16 | Run eval baseline | Test on device | After deploy: call bereanRunEvals callable from admin account. Verify pass rates meet thresholds: Bible 90%, Safety 95%, Product 80%, Technical 75%, Moderation 90% | Firebase console / test device | Before launch | Pending |
| 17 | App Check enforcement | Config | Confirm App Check is enforced (not just debug) on all new berean* callables in Firebase Console → App Check | Firebase Console | Yes | Pending |
