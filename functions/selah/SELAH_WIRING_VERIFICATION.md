# SELAH WIRING VERIFICATION
**Authored by:** Final Wiring / Verification Agent  
**Date:** 2026-06-07  
**Build phase:** Phase 2 — End-to-End Wiring

---

## A. FILE MANIFEST

All files verified by reading. No claims are assumed.

### Backend — functions/selah/

| File | Purpose | Lines |
|---|---|---|
| `selah.contracts.ts` | Frozen contract: types (DiscernmentCheck, SelahNote, Citation, etc.), Firestore path constants, routing config additions (DISCERNMENT_ROUTING, SELAH_CORPUS_RETRIEVAL_ROUTING), feature flags, Liquid Glass design tokens (§1–§8), validation helpers (assertOpenTranslation, assertSoftDeleteOnly, validateDiscernmentCheck) | 360 |
| `selahCorpusUtils.js` | Embedding + namespace helpers: `selahNamespace()` (single gated constructor), `buildNoteEmbedText()` (translationRead excluded by design), `buildNoteEmbeddingPayload()` (translationRead excluded), `buildNoteQueryText()`, `filterDeletedNotes()`, `isValidNoteKind()` | 202 |
| `selahCorpusService.js` | Gen2 callable exports: `indexSelahNote` (auth-guarded, rate-limited, upserts/deletes from Pinecone, soft-delete sync) and `querySelahCorpus` (auth-guarded, rate-limited, filters soft-deleted results). Both reject `translationRead` in payload. | 391 |
| `discernmentPrompts.js` | Prompt builders: `buildDiscernmentPrompt()` (double-enforces open-license filter before Claude prompt construction), `buildRefusalResponse()` (refused state invariants enforced), `extractClaimsPrompt()` (optional first-pass extraction) | 259 |
| `discernmentEngine.js` | Gen2 callable exports: `runDiscernmentCheck` (full 13-step pipeline: auth → rate limit → NeMo input guard → verse fetch → prompt → Claude retry → parse → citation strip → NeMo output guard → validate → save) and `shareDiscernmentCheck` (auth → ownership check → soft-delete check → feature flag gate → NeMo re-moderation → promote to shared). | 771 |
| `openLicenseVerseService.js` | Open-license verse fetch service: `getOpenLicenseVersesForContext()` (regex + topic-driven reference extraction, parallel fetch, fail graceful), `getVersesByReference()` (targeted lookup), `assertOpenTranslationJS()` re-exported. All entry points call `assertOpenTranslationJS` before any network activity. | 433 |
| `bibleProviderAdapter.js` | Provider pattern: `BibleApiProvider` (KJV + WEB via bible-api.com, no key required), `BollsLifeProvider` (BSB via bolls.life, no key required), `CompositeOpenLicenseProvider` (routes by translation, per-invocation Map cache, `assertOpenTranslationJS` at every entry point). `fetchWithTimeout` wraps all network calls at 5000ms. | 473 |

**Backend total: 2,889 lines**

### Frontend — functions/selah/ui/

| File | Purpose | Lines |
|---|---|---|
| `selahGlass.css` | All Liquid Glass CSS classes from GLASS_TOKENS: `.selah-page-bg` (§1), `.selah-card` (§2), `.selah-glass-dark-pill` (§3), `.selah-glass-light` / `.selah-glass-circle` / `.selah-glass-pill` (§4), `.selah-segmented-track/option/selected` (§5), `.selah-context-menu` / `.selah-context-menu-item` / `.selah-context-menu-divider` (§6), `.selah-citation-block` (§7), `.selah-highlight-swatch` (§8), bottom sheet classes | 277 |
| `SelahReaderSurface.jsx` | Main reader: full-screen §1 background, sticky frosted glass navbar (§4), SelahReaderControls sub-bar, verse list with VerseRow tap → VerseContextMenu (§6), SelahAnnotationPanel bottom sheet, floating prev/next chapter nav | 710 |
| `SelahVOTD.jsx` | Verse of the Day: §2 card, §3 hero + scrim, verse text + reference bottom-left, §3 dark glass pill "Read Chapter" CTA. Image fallback to neutral gray gradient. | 171 |
| `SelahReaderControls.jsx` | Horizontal toolbar: TranslationPicker (glass pill + dropdown), BookChapterPicker (two-stage book→chapter picker), audio toggle button, search opener — all prop-wired | 469 |
| `SelahAnnotationPanel.jsx` | Bottom sheet: highlight (ColorSwatchRow, immediate commit), note (color + text + SaveButton), question (text + SaveButton), prayer (text + SaveButton), soft-delete DeleteButton (two-tap confirm) | 411 |
| `DiscernmentCard.jsx` | Result card: `loading` (PulsePlaceholder shimmer), `refused` (RefusedState, no verdict chip), `grounded` (GroundedState: VerdictChip, ClaimRow, CitationBlock, PerspectivesSwitcher for contested), opt-in "Share to thread" pill | 543 |
| `DiscernmentAction.jsx` | Trigger pill: `idle` / `loading` (Spinner) / `error` (ExclamationIcon + auto-reset). Calls `callDiscernmentFn` prop with `visibility: 'private'` always. | 217 |
| `DiscernmentShareFlow.jsx` | Opt-in sharing confirmation bottom sheet: read-only DiscernmentCard preview (pointerEvents: none), NeMo notice, "Share" button (calls `callShareFn` then `onConfirmShare`), "Keep Private" (calls `onCancelShare`). | 258 |

**Frontend total: 3,056 lines  
Grand total: 5,945 lines**

---

## B. DEAD BUTTON AUDIT

All interactive elements verified by reading the actual source. No stubs were found in the critical paths. Notes on stubs where they exist.

### SelahReaderSurface.jsx
| Element | Handler | Verdict |
|---|---|---|
| Verse tap | `handleVersePress` → `setContextMenuOpen(true)` + `setActiveVerse(...)` | WIRED |
| Context menu: Highlight | `handleHighlight` → `setAnnotationMode('highlight')` | WIRED |
| Context menu: Add Note | `handleAddNote` → `setAnnotationMode('note')` | WIRED |
| Context menu: Cross References | `onFetchCrossReferences(verseRef)` prop + `onDismiss()` | WIRED to prop |
| Context menu: Original Language | `onOriginalLanguage(verseRef)` prop + `onDismiss()` | WIRED to prop |
| Context menu: Check against Scripture | `onCheckAgainstScripture(verse)` prop + `onDismiss()` | WIRED to prop (Agent D entry point) |
| Back button (navbar) | Comment: `{/* caller handles navigation */}` — no-op inline | STUB — acceptable (navigation is host app's responsibility; host must wire) |
| More menu: Font Size / Reading Plan / Share Passage | `setMoreMenuOpen(false)` — stub | STUB — acceptable for prototype stage; host must wire |
| Prev/Next chapter | `handlePrevChapter` / `handleNextChapter` → `setCurrentChapter` | WIRED (local state) |
| Audio toggle | `handleAudioToggle` → empty callback | STUB — must be wired by host to AVPlayer service |
| Search open | `handleSearchOpen` → empty callback | STUB — must be wired by host to search overlay |
| Annotation panel: onCreateNote | `handleCreateNote` → `onCreateNote` prop | WIRED |
| Annotation panel: onDeleteNote | `handleDeleteNote` → `onDeleteNote` prop (soft-delete only) | WIRED |

**STUBS REQUIRING HOST WIRING (non-blocking for prototype, required for production):**
1. Back button navigation (`SelahReaderSurface` navbar)
2. More menu items (Font Size, Reading Plan, Share Passage)
3. `onAudioToggle` → must be connected to AVPlayer / playback service
4. `onSearchOpen` → must be connected to in-reader search overlay

These are all correct seam points: the prop callbacks are defined and passed; the host integration layer must implement them. No dead buttons exist in the discernment or corpus paths.

### SelahVOTD.jsx
| Element | Handler | Verdict |
|---|---|---|
| "Read Chapter" pill | `onClick={() => onReadChapter(verseRef)}` | WIRED to prop |
| Image error | `onError={() => setImageError(true)}` → fallback to `PLACEHOLDER_GRADIENT` | WIRED |

### SelahReaderControls.jsx
| Element | Handler | Verdict |
|---|---|---|
| Translation pill | `TranslationPicker` → `onTranslationChange(id)` prop | WIRED |
| Book picker | `BookChapterPicker` stage 1 → `handleBookSelect(book)` → stage 2 | WIRED |
| Chapter picker | `BookChapterPicker` stage 2 → `handleChapterSelect(ch)` → `onNavigate(book, ch)` prop | WIRED |
| Audio toggle | `onClick={onAudioToggle}` prop | WIRED to prop |
| Search opener | `onClick={onSearchOpen}` prop | WIRED to prop |

### SelahAnnotationPanel.jsx
| Element | Handler | Verdict |
|---|---|---|
| Color swatches (highlight mode) | `ColorSwatchRow.onChange` → `handleHighlightSelect` → `onCreateNote({kind:'highlight', color, body:null})` + `onDismiss()` | WIRED, commits immediately |
| Color swatches (note mode) | `ColorSwatchRow.onChange` → `setSelectedColor` only (does NOT immediately commit; Save button commits) | WIRED correctly |
| Text input (note/question/prayer) | `TextInput.onChange` → `setBodyText` | WIRED |
| Save Note button | `handleSave` → `onCreateNote({verseRef, kind, color, body})` + `onDismiss()` | WIRED |
| Delete Note button | `DeleteButton.onPress` → `handleDelete` → `onDeleteNote(existingNote.id)` + `onDismiss()` | WIRED (two-tap confirm pattern) |
| Close (✕) button | `onClick={onDismiss}` | WIRED |
| Backdrop tap | `onClick` on overlay → `onDismiss()` if target === currentTarget | WIRED |

### DiscernmentAction.jsx
| Element | Handler | Verdict |
|---|---|---|
| Pill tap (idle) | `handleTap` → `setState(LOADING)` → `callDiscernmentFn({inputText, sourceType, sourceRef, visibility:'private'})` | WIRED |
| `callDiscernmentFn` success | → `setState(IDLE)` + `onCheckComplete(result)` | WIRED |
| `callDiscernmentFn` error | → `setState(ERROR)` + `onCheckError(msg)` + auto-reset after 3500ms | WIRED |
| Loading state | `disabled={isLoading}`, renders `Spinner` | WIRED |
| Error state | Renders `ExclamationIcon` + error message | WIRED |

### DiscernmentCard.jsx
| Element | Handler | Verdict |
|---|---|---|
| "Share to thread" pill | `onClick={onShare}` prop | WIRED to prop (NOT auto-share; parent must show DiscernmentShareFlow) |
| Dismiss (×) button | `onClick={onDismiss}` prop | WIRED |
| Perspectives tab switcher (3+ traditions) | `setActiveIndex(i)` | WIRED |

### DiscernmentShareFlow.jsx
| Element | Handler | Verdict |
|---|---|---|
| "Share" button | `handleShare` → `callShareFn(check.id)` → `onConfirmShare()` | WIRED |
| "Keep Private" button | `onClick={onCancelShare}` | WIRED |
| Backdrop tap | → `onCancelShare()` | WIRED |
| Share error | Sets `shareError` state, renders error block | WIRED |
| Preview inside sheet | `pointerEvents: 'none'`; share/dismiss inside preview are no-ops | CORRECT — preview is read-only |

---

## C. ALL UI STATES PRESENT

Verified by reading each component's render paths.

### DiscernmentCard
| State | Present | Evidence |
|---|---|---|
| loading (`check === null`) | YES | `if (check === null) return <LoadingState />` — PulsePlaceholder shimmer, `aria-busy="true"` |
| refused (`check.status === 'refused'`) | YES | `if (check.status === 'refused') return <RefusedState ...>` — no verdict chip, refusalReason displayed |
| grounded (aligns / diverges / insufficient) | YES | `GroundedState` renders VerdictChip, ClaimRow, CitationBlock |
| contested (`check.verdict === 'contested'`) | YES | `GroundedState` with `isContested = check.verdict === 'contested'` → renders `PerspectivesSwitcher` |

All four states: CONFIRMED.

### DiscernmentAction
| State | Present | Evidence |
|---|---|---|
| idle | YES | Default state; renders `BookmarkCrossIcon` + "Check against Scripture" |
| loading | YES | `STATE.LOADING` → renders `Spinner` + "Checking…"; button `disabled={isLoading}` |
| error | YES | `STATE.ERROR` → renders `ExclamationIcon` + error message; auto-resets after 3500ms |

All three states: CONFIRMED.

### SelahAnnotationPanel
| Mode | Present | Evidence |
|---|---|---|
| highlight | YES | `mode === 'highlight'` branch: ColorSwatchRow (immediate commit on pick), no text input, no Save button |
| note | YES | `mode === 'note'` branch: ColorSwatchRow + TextInput + SaveButton |
| question | YES | `mode === 'question'` branch: TextInput + SaveButton |
| prayer | YES | `mode === 'prayer'` branch: TextInput + SaveButton |

All four modes: CONFIRMED.

### SelahVOTD
| State | Present | Evidence |
|---|---|---|
| image-loaded | YES | `usePhoto = heroImageUrl && !imageError` → renders `<img>` with `objectFit: cover` |
| placeholder fallback | YES | `!usePhoto` → `background: PLACEHOLDER_GRADIENT` (neutral gray gradient); also triggered on `onError={() => setImageError(true)}` |

Both states: CONFIRMED.

---

## D. SECURITY INVARIANTS

Verified by reading the actual source files. All findings are from code, not assumption.

| Invariant | Status | Evidence |
|---|---|---|
| No client-side secrets in any selah/ file | CONFIRMED | No API keys, tokens, or credentials appear in any selah/ JS or JSX file. Secrets declared via `defineSecret()` in `discernmentEngine.js` lines 45–48 (ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST) — all runtime-injected by Firebase. |
| All CF callables check `request.auth?.uid` | CONFIRMED | `indexSelahNote`: `const uid = request.auth?.uid; if (!uid) throw new HttpsError("unauthenticated", ...)` (line 91–93). `querySelahCorpus`: same pattern (line 284–287). `runDiscernmentCheck`: `if (!request.auth || !request.auth.uid) throw new HttpsError("unauthenticated", ...)` (line 386–390). `shareDiscernmentCheck`: same pattern (line 634–638). |
| `runDiscernmentCheck` auth-guarded | CONFIRMED | First action in the callable body: auth check at step 1 (line 386). |
| `shareDiscernmentCheck` auth-guarded | CONFIRMED | First action in the callable body: auth check at line 634. Additionally checks `check.createdBy !== uid` (line 674) as a second ownership gate. |
| `indexSelahNote` auth-guarded | CONFIRMED | Line 91–93: uid from `request.auth?.uid`; throws `unauthenticated` if absent. |
| `querySelahCorpus` auth-guarded | CONFIRMED | Line 284–287: uid from `request.auth?.uid`; throws `unauthenticated` if absent. |
| Routing: `task: 'discernment'` → Claude-only | CONFIRMED (after STEP 3 edit) | `amenRouting.config.js` now contains `discernment: { primary: "claude", chain: ["claude"], fail: "fail_closed", ... }`. `callClaudeWithRetry` in `discernmentEngine.js` calls `callModel({ task: "discernment", ... })` (line 236). |

---

## E. OPEN-LICENSE INVARIANT (proven from code)

**Claim:** No ESV/NIV/NLT/NASB or other licensed translation can reach the AI citation path.

### Proof chain

1. **`assertOpenTranslationJS` (bibleProviderAdapter.js, line 143)** — throws `HARD CONTRACT VIOLATION` if `translation` is not in `["BSB", "WEB", "KJV"]`. This is the canonical enforcement function.

2. **`CompositeOpenLicenseProvider.getVerses()` (bibleProviderAdapter.js, line 434)** — calls `assertOpenTranslationJS(translation)` before any cache lookup or network call. Licensed translations are rejected before a single byte hits the wire.

3. **`BibleApiProvider.getVerses()` (line 243)** — calls `assertOpenTranslationJS(translation)` then additionally checks `this._supportedTranslations.includes(translation)` (only KJV/WEB).

4. **`BollsLifeProvider.getVerses()` (line 322)** — calls `assertOpenTranslationJS(translation)` then additionally checks `this._supportedTranslations.includes(translation)` (only BSB).

5. **`getOpenLicenseVersesForContext()` (openLicenseVerseService.js, line 305)** — calls `assertOpenTranslationJS(translation)` at function entry before any reference extraction or fetch. Returns `[]` on violation (never throws to caller — graceful degradation).

6. **`getVersesByReference()` (openLicenseVerseService.js, line 382)** — calls `assertOpenTranslationJS(translation)` at function entry. Returns `[]` on violation.

7. **`buildDiscernmentPrompt()` (discernmentPrompts.js, line 54)** — double-enforces at the prompt boundary: filters `openLicenseVerses` array with `OPEN_TRANSLATIONS.includes(v.translation)` check, logs any violation as error, and strips the offending verse before the prompt is built.

8. **`getOpenLicenseVersesForContext` injection in discernmentEngine.js (line 146)** — after receiving verses from Agent E's module, filters the array: `return (verses || []).filter((v) => { if (!OPEN_TRANSLATIONS.includes(v.translation)) { logger.error(...); return false; } return true; })`. Third enforcement layer.

9. **`stripLicensedCitations()` (discernmentEngine.js, line 318)** — after Claude responds, calls `assertOpenTranslation(citation.translation)` on every citation in the response. Removes any citation that fails (logs the violation, does NOT re-throw to client). Also applied to citations inside `perspectives[]` (line 511).

10. **`indexSelahNote` payload rejection (selahCorpusService.js, line 105)** — explicitly rejects any payload that includes `translationRead`: `if ("translationRead" in data) throw new HttpsError("invalid-argument", "translationRead must not be sent to indexSelahNote...")`. This prevents licensed display text from entering Pinecone.

11. **`buildNoteEmbedText()` and `buildNoteEmbeddingPayload()` (selahCorpusUtils.js)** — `translationRead` is structurally excluded from both functions. Comments confirm this is intentional.

**Attempt to cite ESV/NIV in a discernment check is REJECTED at multiple locations:**
- At the verse-fetch boundary (`assertOpenTranslationJS` in bibleProviderAdapter.js) — ESV/NIV never fetched
- At the prompt-building boundary (`buildDiscernmentPrompt` filter) — even if somehow injected
- At the engine injection boundary (filter in `getOpenLicenseVersesForContext` in discernmentEngine.js)
- At the Claude output boundary (`stripLicensedCitations` in discernmentEngine.js) — stripped from Claude's response

The defense is four layers deep. No single-point failure can route licensed text to Claude or into Firestore citations.

---

## F. SOFT-DELETE INVARIANT (proven from code)

**Claim:** Hard deletes do not exist in any Selah file. Only `deletedAt` timestamps are used.

### Proof

**Hard-delete search result:** Grep for `doc.delete()`, `document.delete()`, `.delete()` across all `functions/selah/` JS files returns **no matches**.

**Positive evidence for soft-delete:**

1. **`indexSelahNote` — when `deletedAt` is non-null (selahCorpusService.js, line 135):**
   ```
   if (deletedAt !== null && deletedAt !== undefined) {
     await pineconeDelete(namespace, [noteId]);   // removes vector from Pinecone
     await selahNoteRef(uid, noteId).update({ indexedToCorpus: false }); // updates Firestore flag
     // NOTE: the Firestore document itself is NOT deleted
   }
   ```
   The Firestore document at `users/{uid}/selahNotes/{noteId}` is **never deleted**. Only the Pinecone vector is removed, and `indexedToCorpus` is set to `false`. This matches the contract: `deletedAt is the ONLY delete mechanism; hard-delete is forbidden`.

2. **`runDiscernmentCheck` — new checks always have `deletedAt: null` (discernmentEngine.js, line 570):**
   ```
   deletedAt: null,   // C5: soft-delete only; no hard-delete path
   ```

3. **`shareDiscernmentCheck` — checks `deletedAt` before allowing share (line 664):**
   ```
   if (check.deletedAt != null) {
     throw new HttpsError("not-found", "This discernment check has been deleted and cannot be shared.");
   }
   ```

4. **`SelahAnnotationPanel` delete handler (line 218):**
   ```
   const handleDelete = useCallback(() => {
     if (existingNote?.id) {
       onDeleteNote(existingNote.id);  // calls the prop — never calls Firestore directly
       onDismiss();
     }
   }, ...);
   ```
   The component calls `onDeleteNote` (a prop callback). It does not import or call Firestore directly. The parent (host app) is responsible for setting `deletedAt` on the Firestore document.

5. **`validateSelahNoteOwnership` (discernmentEngine.js, line 196):** Checks `data.deletedAt != null` before allowing a selah_note to be used as a discernment source.

6. **`filterDeletedNotes` (selahCorpusUtils.js, line 166):** Filters Pinecone results where `metadata.deletedAt` is non-null, so soft-deleted notes are excluded from corpus query results.

All six invariants confirmed by code.

---

## G. END-TO-END SCENARIO TRACE

**Scenario:** User highlights James 1:5, queries corpus, then runs a discernment check on a Space message.

### Step 1 — User highlights James 1:5
**User action:** Taps verse → `VerseContextMenu` appears → taps "Highlight" → `SelahAnnotationPanel` (highlight mode) opens → picks cyan swatch.

**Code path:**
- `SelahReaderSurface.handleVersePress` (line 305) sets `activeVerse` + `setContextMenuOpen(true)`
- `VerseContextMenu` renders; user taps "Highlight" → `onHighlight` → `handleHighlight` (line 317) sets `annotationMode('highlight')`
- `SelahAnnotationPanel` renders in highlight mode; user taps cyan swatch
- `ColorSwatchRow.onChange` → `handleHighlightSelect('cyan')` (line 190) → `onCreateNote({ verseRef: 'James 1:5', kind: 'highlight', color: 'rgba(100,200,220,0.25)', body: null })` + `onDismiss()`

**Status:** EXISTS and WIRED. Parent must call `indexSelahNote` after receiving the `onCreateNote` callback.

### Step 2 — indexSelahNote runs
**Code path:**
- `indexSelahNote` (selahCorpusService.js, line 84) receives call from parent
- Auth guard: `uid = request.auth?.uid` (line 91)
- Rate limit: `enforceRateLimit(uid, 'selah_index_note', 60, 60)` (line 96)
- Input validation: `translationRead` rejected if present (line 105); `verseRef` + `kind` validated
- `namespace = selahNamespace(uid)` → `selah-notes-{uid}` (always from auth uid)
- `deletedAt` is null → takes upsert path
- `buildNoteEmbedText({ verseRef: 'James 1:5', kind: 'highlight', body: null })` → `"James 1:5 highlight:"` (translationRead excluded)
- `openaiEmbed(embedText, cacheKey)` → vector
- `buildNoteEmbeddingPayload({ id, userId: uid, verseRef, kind, color, body, createdAt, deletedAt: null })` → payload (translationRead excluded)
- `pineconeUpsert(namespace, [payload])` → vector indexed
- `selahNoteRef(uid, noteId).update({ indexedToCorpus: true })` → Firestore flag updated
- Returns `{ success: true, indexed: true }`

**Status:** EXISTS and WIRED.

### Step 3 — User queries corpus: "What have I noted on wisdom?"
**Code path:**
- `querySelahCorpus` (selahCorpusService.js, line 278) receives call
- Auth guard: uid from `request.auth?.uid` (line 284)
- Rate limit: `enforceRateLimit(uid, 'selah_query_corpus', 30, 60)` (line 290)
- `namespace = selahNamespace(uid)` → `selah-notes-{uid}`
- `buildNoteQueryText(undefined, 'What have I noted on wisdom?')` → `"What have I noted on wisdom?"`
- `openaiEmbed(queryText, null)` → query vector (no cache key — always fresh)
- `pineconeQuery(namespace, queryVector, 5)` → raw results from user's private namespace
- `filterDeletedNotes(rawResults)` → removes soft-deleted notes
- Results shaped: `{ noteId, verseRef, kind, score, body, color, createdAt }` (uid and deletedAt excluded)
- Returns `{ results: [{ noteId, verseRef: 'James 1:5', kind: 'highlight', score: 0.92, ... }], empty: false }`

**Status:** EXISTS and WIRED. James 1:5 highlight is returned (if corpus was indexed and embedding semantic match exists).

### Steps 4–6 — User opens Space message, taps "Check against Scripture"

**Step 4 — UI trigger:**
- `DiscernmentAction` is placed on the space_message surface by the host app
- Props: `sourceType: 'space_message'`, `inputText: 'God told me to do X'`, `callDiscernmentFn: <CF caller>`

**Step 5 — DiscernmentAction.handleTap():**
- `setState(STATE.LOADING)` (line 56)
- `onCheckStarted(provisionalId)` called (line 62)
- `callDiscernmentFn({ inputText, sourceType: 'space_message', sourceRef: null, visibility: 'private' })` (line 64) — `visibility: 'private'` is hardcoded here, NEVER auto-shared

**Status:** EXISTS and WIRED.

**Step 6 — runDiscernmentCheck pipeline (discernmentEngine.js):**

| Sub-step | File:Function | Exists |
|---|---|---|
| a. Auth check | discernmentEngine.js:386 `if (!request.auth || !request.auth.uid)` | YES |
| b. Rate limit | discernmentEngine.js:396 `enforceRateLimit(uid, 'discernment_check', 10, 60)` | YES |
| c. NeMo input guard | discernmentEngine.js:442 `callModel({ task: 'guard_input', input: { text }, userId: uid })` — FAIL CLOSED (C1) | YES |
| d. getOpenLicenseVersesForContext | discernmentEngine.js:468 → openLicenseVerseService.js:301 → bibleProviderAdapter.js CompositeOpenLicenseProvider | YES |
| e. buildDiscernmentPrompt → Claude | discernmentEngine.js:476 `buildDiscernmentPrompt(...)` → line 483 `callClaudeWithRetry({ prompt, uid })` → line 236 `callModel({ task: 'discernment', ... })` — Claude-only (C2) | YES |
| f. Parse + citation validation | discernmentEngine.js:493 `parseClaudeResponse(claudeResult)` → line 505 `stripLicensedCitations(parsed.citations, uid)` (C3) | YES |
| g. NeMo output guard | discernmentEngine.js:524 `callModel({ task: 'guard_output', input: { text: JSON.stringify(...) }, userId: uid })` | YES |
| h. Save to Firestore | discernmentEngine.js:551 `discernmentCheck = { ..., visibility: 'private', deletedAt: null }` → line 588 `saveDiscernmentCheck(...)` | YES |

**Status:** All 8 sub-steps exist and are wired.

### Step 7 — DiscernmentCard renders with `status: 'grounded'`
- `DiscernmentAction` → `onCheckComplete(result)` → parent renders `<DiscernmentCard check={result} />`
- `check` is non-null → skips `LoadingState`
- `check.status !== 'refused'` → renders `GroundedState`
- `VerdictChip` renders with `VERDICT_LABELS[check.verdict]` → "Aligns" or "Contested"

**Status:** EXISTS and WIRED.

### Step 8 — User taps "Share to thread"
- `GroundedState` renders "Share to thread" glass pill (line 487)
- `onClick={onShare}` → parent (host app) shows `<DiscernmentShareFlow check={check} ... />`

**Status:** EXISTS and WIRED. Parent must implement the `onShare` → `DiscernmentShareFlow` flow.

### Step 9 — User confirms → `shareDiscernmentCheck` called
- `DiscernmentShareFlow.handleShare()` (line 38) → `callShareFn(check.id)` (line 44)
- `shareDiscernmentCheck` (discernmentEngine.js, line 627):
  - Auth guard: uid from `request.auth?.uid` (line 634)
  - Fetch check from Firestore (line 651)
  - `check.deletedAt != null` → throws `not-found` (C5)
  - `check.createdBy !== uid` → throws `permission-denied` (ownership gate)
  - Feature flag check: `remoteConfig/selah.discernmentSharing` must have `enabled: true` (HUMAN GATE enforced in code — defaults to blocked)
  - NeMo re-moderation: `callModel({ task: 'guard_output', input: { text: contentForModeration } })` (line 727)
  - Promotes: `ref.update({ visibility: 'shared', updatedAt: now })` (line 759)
- Returns updated check
- `DiscernmentShareFlow`: `setIsSharing(false)` + `onConfirmShare()` (line 46)

**Status:** EXISTS and WIRED.

### Step 10 — Thread participants can see the check
- Check is now `visibility: 'shared'` in `discernmentChecks/{checkId}`
- Firestore security rules must allow `createdBy = uid OR (visibility = 'shared' AND threadParticipant)` — see DEPLOY CHECKLIST §Firestore rules

**Status:** CF side EXISTS. Firestore rule is a pending human deploy step.

---

## H. HUMAN GATES

The following require explicit human approval before production use. They are enforced in code and will block functionality until enabled.

### GATE 1: `selah.discernmentSharing` Remote Config flag
**What it blocks:** `shareDiscernmentCheck` checks `remoteConfig/selah.discernmentSharing` in Firestore and throws `failed-precondition` if `enabled !== true`. This means **no check can ever be shared** until a human explicitly enables this flag.

**Why it requires human approval:** Shared discernment checks are visible to thread participants and could be used to target a person if the feature is misused. The contract (`selah.contracts.ts §SECTION 5`) explicitly marks this: `HUMAN GATE required before enabling in prod`.

**How to enable when ready:** Write `{ enabled: true }` to `remoteConfig/selah.discernmentSharing` in Firestore. A future iteration should migrate this to Firebase Remote Config SDK.

### GATE 2: Discernment checks touching minor account data
Any discernment check triggered in a thread or space where a minor user is a participant must be reviewed before the sharing gate is opened. The platform should enforce an age-verification check before allowing `shareDiscernmentCheck` to proceed for shared spaces with mixed audiences.

**Current status:** Not enforced in the callable. This is a pre-production requirement before `selah.discernmentSharing` is enabled for any community-visible context.

### GATE 3: Public/shared checks as targeting vectors
A shared discernment check displays what claims were assessed and what Scripture says about them. If the check's `inputText` is retained in the share, it may be used to target the original author of the message being assessed. The platform must decide:
- Whether `inputText` is shown in the shared view (currently yes — it is stored and would be visible)
- Whether a human review queue should be added before any `visibility: 'shared'` promotion

**Recommendation:** Before enabling `selah.discernmentSharing`, strip or summarize `inputText` in the shared view, or add a T&S review queue for shared checks above a content-sensitivity threshold.

---

## I. DEPLOY CHECKLIST

All items below require human action before the Selah system is live in production.

### Cloud Functions — firebase deploy

```bash
firebase deploy --only functions:indexSelahNote
firebase deploy --only functions:querySelahCorpus
firebase deploy --only functions:runDiscernmentCheck
firebase deploy --only functions:shareDiscernmentCheck
```

These are exported from `v2functions.js` (wired in STEP 2). They are gen2 callables in `us-central1`. No region-specific flags needed beyond the defaults already set.

### Firestore Security Rules — new paths

Two new paths need rules. Add to your Firestore rules file:

```
// Selah personal notes — owner only
match /users/{uid}/selahNotes/{noteId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// Discernment checks — owner reads private; shared checks readable by thread participants
match /discernmentChecks/{checkId} {
  allow read: if request.auth != null && (
    resource.data.createdBy == request.auth.uid ||
    (resource.data.visibility == 'shared' &&
     // Host app must pass a function here to validate thread membership
     // e.g.: isThreadParticipant(resource.data.sourceRef, request.auth.uid)
     true // PLACEHOLDER — replace with actual thread participant check
    )
  );
  allow create: if request.auth != null;
  allow update: if request.auth != null && resource.data.createdBy == request.auth.uid;
  // Hard rule: no delete — only deletedAt updates are permitted
  allow delete: if false;
}

// Discernment sharing feature flag (read by shareDiscernmentCheck CF)
match /remoteConfig/selah.discernmentSharing {
  allow read: if false; // server-side only; CF uses Admin SDK
  allow write: if false; // admin-only: set via Firebase console or Admin SDK
}
```

**Note:** The `discernmentChecks` shared-read rule currently has a placeholder. Before enabling `selah.discernmentSharing`, replace `true` with a proper thread-participant check.

### Remote Config Flags — start ALL OFF

Create (or verify) these flags exist in Firebase Remote Config with default value `false`:

| Flag | Purpose | Safe to enable when |
|---|---|---|
| `selah.personalCorpus` | Enables note → Pinecone indexing via `indexSelahNote` | After CF deploy + Pinecone index confirmed |
| `selah.discernment` | Enables "Check against Scripture" Berean check feature | After CF deploy + NeMo confirmed working |
| `selah.discernmentSharing` | Enables promoting private checks to 'shared' | HUMAN GATE — requires GATE 1, 2, 3 review above |

### Pinecone Index Configuration

The `indexSelahNote` callable uses namespaces of the form `selah-notes-{uid}` within the existing Pinecone index (resolved from `PINECONE_HOST` secret). No new index is required — namespaces are virtual partitions in Pinecone.

**Required:** Verify the Pinecone index dimension matches the OpenAI embedding model used in `mlClients.openaiEmbed`. If the existing index is already configured for the correct embedding dimension (typically 1536 for `text-embedding-ada-002` or 3072 for `text-embedding-3-large`), no additional configuration is needed.

**If you are creating a new dedicated index for Selah notes:**
```
Index name: selah-notes
Dimension: [match your openaiEmbed model output dimension]
Metric: cosine
Pod type: p1 (or serverless if available in your Pinecone tier)
```

### Bible API Credentials — NONE REQUIRED

The open-license Bible APIs used by `bibleProviderAdapter.js` require no API keys:
- `bible-api.com` (KJV + WEB) — free, no authentication
- `bolls.life` (BSB) — free, no authentication

**Confirmed:** No credentials to configure for the verse fetch pipeline.

### Secrets — verify existing secrets are deployed

The following secrets are declared in `discernmentEngine.js` via `defineSecret()`. They must exist in Secret Manager:
- `ANTHROPIC_API_KEY` — for Claude calls via `callModel`
- `NVIDIA_API_KEY` — for NeMo guard calls
- `PINECONE_API_KEY` — for Pinecone operations
- `PINECONE_HOST` — for Pinecone operations

All four should already exist from prior Berean OS deployments. Verify with:
```bash
gcloud secrets list --filter="name:ANTHROPIC_API_KEY OR name:NVIDIA_API_KEY OR name:PINECONE_API_KEY OR name:PINECONE_HOST"
```

---

## SUMMARY OF FIXES MADE BY THIS AGENT

| Fix | File | Description |
|---|---|---|
| Wire `indexSelahNote` + `querySelahCorpus` | `functions/v2functions.js` | Added require + export block at bottom of file (STEP 2) |
| Wire `runDiscernmentCheck` + `shareDiscernmentCheck` | `functions/v2functions.js` | Added require + export block at bottom of file (STEP 2) |
| Add `discernment` task to routing table | `functions/router/amenRouting.config.js` | Added `discernment` entry: Claude-only, fail_closed, NeMo guards, requireCitations: true (STEP 3) |
| Add `selah_corpus_retrieve` task to routing table | `functions/router/amenRouting.config.js` | Added `selah_corpus_retrieve` entry: Pinecone-only, degrade to empty (STEP 3) |

**No bugs or broken invariants were found that required fixes in the selah/ source files.** All callables are auth-guarded, all UI states are present, all buttons route to real logic (or documented seam-point stubs for host-app wiring), the open-license invariant is four layers deep, and soft-delete is enforced throughout.

---

## BLOCKERS REQUIRING HUMAN ACTION BEFORE PRODUCTION

1. **CF deploy** — 4 functions must be deployed: `indexSelahNote`, `querySelahCorpus`, `runDiscernmentCheck`, `shareDiscernmentCheck`
2. **Firestore rules** — `users/{uid}/selahNotes` and `discernmentChecks` paths need rules; shared-check read rule needs thread-participant check implemented
3. **Remote Config flags** — 3 flags must be created, defaulting to `false`; `selah.discernmentSharing` requires GATES 1/2/3 human review
4. **Pinecone dimension verification** — confirm existing index dimension matches `openaiEmbed` model
5. **GATE 1** — `selah.discernmentSharing` requires explicit T&S/legal review of sharing semantics (minor data, targeting risk) before enabling
6. **Host app wiring** — 4 seam-point stubs in `SelahReaderSurface` need host-level implementation: back navigation, more menu items, audio playback, search overlay
