# C-Wave-5 — GUARDIAN PrePublish wiring (HUMAN-APPLY, load-bearing)

**Feature C · invariant PP-I1.** Until these five insertions land, the GUARDIAN hook chain
is built but unreached, so PP-I1 ("every write path routes through the chain before commit")
is *not* enforced. This guide is the ready-to-apply form of `DEPLOY_RUNBOOK.md §3 → C Wave 5`.

## What's already on the branch (no call-site edits)
- `AMENAPP/AIIntelligence/GuardianPrePublishContracts.swift` — `HookChain`, surfaces, verdicts, escalation.
- `AMENAPP/AIIntelligence/PrePublishHooks.swift` — the 4 hooks + `HookChain.standard()`.
- `AMENAPP/AIIntelligence/GuardianPrePublishGate.swift` — **the seam**: `GuardianPrePublishGate.shared.gate(...)`
  runs the chain and persists `/moderationQueue` escalations (PP-I7). **All five call sites below
  only call this seam** — none of them re-implement chain logic.

## How to apply (per AMEN shared-tree discipline)
These five files are peer-hot. Apply with **temp-index + path-scoped patch**, never `git add -A`;
verify the diff-stat tripwire reads `N insertions, 0 deletions` per file (see memory
`feedback_shared_tree_commit_discipline`). Anchors below are against `feature/liquid-glass-hero`
@ `bc3518e2` (the integration substrate that has COMPASS + TestimonyKit); re-anchor by the quoted
context lines, not by line number, since the tree moves.

Every call site is already `async`. The seam is `@MainActor`; all five callers are MainActor-reachable.

---

## Site 1 — Comment  ·  `AMENAPP/AIIntelligence/CommentModerationService.swift`
**Function:** `func moderate(commentId: String, body: String) async -> CommentModerationResult`
**Insert:** at the **top of the function**, before the existing `commentModerationPipelineEnabled`
guard — so the guardian chain runs even when the *comment* pipeline flag is OFF (hook 0 always enforces).

Anchor (first lines of the function body):
```swift
    func moderate(commentId: String, body: String) async -> CommentModerationResult {
        let now = Date().timeIntervalSince1970

        // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). Runs regardless of the comment
        //    pipeline flag; hook 0 (child-safety) always enforces, hooks 1–3 obey the
        //    guardian flag. A non-committable verdict blocks the comment write.
        let guardianVerdict = await GuardianPrePublishGate.shared.gate(
            surface: .comment,
            contentRef: commentId,
            text: body
        )
        if !guardianVerdict.mayCommit {
            return CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: .blocked,
                category: .childSafety,
                confidence: 1.0,
                source: .onDevice,
                reviewedAt: now,
                reviewedBy: nil
            )
        }

        // Feature flag guard — when OFF, preserve existing behavior
        guard AMENFeatureFlags.shared.commentModerationPipelineEnabled else {
```
> The `category: .childSafety` is a coarse audit tag; the precise reason is already in the
> persisted `/moderationQueue` record. If `CommentModerationCategory` has a generic `.blocked`
> case, prefer it.

---

## Site 2 — DM  ·  `AMENAPP/MessageSafetyGateway.swift`  *(guard surface — fail-secure)*
**Function:** `func evaluate(text:senderId:recipientId:conversationId:conversationContext:messageId:minorPolicy:) async -> GatewayDecision`
**Insert:** as **step 0**, before the existing minor-safety hard-block (`// 0. Minor safety hard blocks`).
`.dm` is the canonical guard surface, so provider uncertainty fails closed inside the chain.

Anchor:
```swift
        minorPolicy: MinorSafetyPolicy? = nil
    ) async -> GatewayDecision {

        // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). DM is a guard surface, so the
        //    chain fails closed on provider uncertainty. A non-committable verdict blocks
        //    the message before it is written.
        let guardianVerdict = await GuardianPrePublishGate.shared.gate(
            surface: .dm,
            contentRef: messageId,
            text: text
        )
        if !guardianVerdict.mayCommit {
            return .blockAndStrike(
                signals: [],
                riskScore: 1.0,
                strikeReason: "Message held by safety review"
            )
        }

        // 0. Minor safety hard blocks — enforced before classifier runs
        if let policy = minorPolicy, !policy.canSendDM {
```
> **Decision-type adaptation (the one site that needs it):** `GatewayDecision` has no
> `holdForReview`. Mapping `!mayCommit → .blockAndStrike` treats a *hold* as a *block* on DMs —
> the conservative, guard-surface-correct choice. If you add a softer `.hold` case to
> `GatewayDecision`, branch on `guardianVerdict.finalDecision == .holdForReview` to use it.

---

## Site 3 — Media (DM attachments)  ·  `AMENAPP/MediaSafetyGateway.swift`
**Function:** `func evaluate(image:senderId:recipientId:conversationId:recipientIsMinor:senderTrustTier:) async -> MediaSafetyDecision`
**Insert:** after the cheap tier/throttle rejects (steps 1–3), before the on-device pre-screen
(`// 4. On-device pre-screen`). This feeds the **raw bytes** to hook 0 (the child-safety hash).

Anchor:
```swift
        if let throttleDecision = checkRateThrottle(
            senderId: senderId,
            recipientIsMinor: recipientIsMinor,
            trustTier: senderTrustTier
        ) {
            return throttleDecision
        }

        // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). Hook 0 hashes the raw bytes;
        //    a hash match fails closed and routes to /moderationQueue type 'csam'.
        if let bytes = image.jpegData(compressionQuality: 0.9) {
            let guardianVerdict = await GuardianPrePublishGate.shared.gate(
                surface: .mediaCaption,
                contentRef: conversationId,
                imageData: bytes,
                hasMedia: true
            )
            if !guardianVerdict.mayCommit {
                let isCSAM = guardianVerdict.verdicts.contains {
                    $0.hook == .childSafetyHash && $0.reason == .hashMatch
                }
                return isCSAM
                    ? .freeze(reason: "Media blocked by safety review")
                    : .reject(reason: "Media blocked by safety review")
            }
        } else {
            // No decodable bytes for a media-bearing send => cannot hash => fail closed.
            return .reject(reason: "Media could not be verified")
        }

        // 4. On-device pre-screen (fast, no network)
        let onDeviceResult = onDevicePreScreen(image: image)
```
> Map `holdForReview → .hold(reason:)` instead of `.reject` if you prefer to queue rather than
> bounce; `MediaSafetyDecision` already has a `.hold` case.

---

## Site 4 — Post composer  ·  `AMENAPP/CreatePostView.swift`
**Function:** the async publish path (`publishPostAsync()` region).
**Insert:** immediately before the Firestore commit — the
`dlog("   📤 Saving to Firestore immediately...")` + `.collection("posts").document(...).setData(postData)`.

Anchor:
```swift
                postData["moderationStatus"] = "pending"
                postData["clientSafetyVersion"] = 1

                // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). Text + scripture-claim +
                //    provenance label. Post image bytes are screened on upload / by the
                //    server onCreate trigger, so this seam gates text (hasMedia: false).
                let guardianVerdict = await GuardianPrePublishGate.shared.gate(
                    surface: .post,
                    contentRef: postId.uuidString,
                    text: content,
                    hasMedia: false
                )
                if !guardianVerdict.mayCommit {
                    await MainActor.run {
                        isPublishing = false
                        inFlightPostId = nil
                        notifyPostingFailed()
                    }
                    return
                }

                // P0-4 FIX: Check if post already exists (idempotency)
                dlog("   🔍 Checking for existing post (idempotency)...")
```
> **Media decision:** if the composer still holds the pre-upload `UIImage`(s) in memory at this
> point, pass `imageData: <firstImage>.jpegData(compressionQuality: 0.9)` and `hasMedia: true` to
> also run hook 0 client-side. If the images are already uploaded as URLs (no raw bytes), keep
> `hasMedia: false` here — `mediaScanning.ts` + the `posts/{id}` onCreate trigger are the backstop.
> Do **not** pass `hasMedia: true` with `imageData: nil`: hook 0 fail-closes and would block the post.

---

## Site 5 — Prayer room caption  ·  `AMENAPP/AIIntelligence/PrayerRoomModerationEngine.swift`
**Function:** `func persistApprovedPrayerCaption(_:sessionId:language:targetLanguage:isFinal:) async throws`
**Insert:** at the **top of the function**, before `ScriptureReferenceValidator.requiresVerification`.
This is a `throws` function, so a block throws.

Anchor:
```swift
        isFinal: Bool = true
    ) async throws {
        // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). Caption text is screened before
        //    it is persisted. A non-committable verdict throws (escalation already queued).
        let guardianVerdict = await GuardianPrePublishGate.shared.gate(
            surface: .note,
            contentRef: sessionId,
            text: text
        )
        guard guardianVerdict.mayCommit else {
            throw NSError(
                domain: "GuardianPrePublish",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Caption held by safety review"]
            )
        }

        let requiresCheck = ScriptureReferenceValidator.requiresVerification(text)
```
> If the engine already defines a typed error, throw that instead of the `NSError` placeholder.

---

## Verification after applying (quiet tree only)
1. Acquire `./.build-lock`; canonical build (DEPLOY_RUNBOOK.md §2). Expect 0 errors; the seam +
   5 insertions are additive.
2. Confirm `guardian_pre_publish_enabled` is still **OFF** in `AMENFeatureFlags` — the first RC
   flip (DEPLOY_RUNBOOK.md §5 step 1) is *shadow-observe*: hooks 1–3 only log; **hook 0 already
   blocks today** because it is never flag-gated (PP-I3).
3. Leave the child-safety hash **inert on detection** until `CSAMComplianceGate` clears (§6).
   The hook routes a match to `/moderationQueue type='csam'`; iOS never auto-files to NCMEC.
4. Add any new `/moderationQueue` record `type` values to `firestore.rules` before flipping
   enforcement (DEPLOY_RUNBOOK.md §4).
