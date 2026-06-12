# NIS Wave 1 — Lane B Notes

**Owner:** Lane B — Detection Pipeline  
**Date completed:** 2026-06-12  
**Branch:** safety-hardening  

---

## Entry point

Trigger document path: `notes/{noteId}`  
Function: `nisProcessNote` in `Backend/functions/src/nis/index.ts`  
Trigger type: `onDocumentWritten` (Firestore)

---

## Commit log

| # | Hash | Description |
|---|------|-------------|
| 1 | `a5e15b57` | `feat(nis/lane-c): add scriptureQuoteDetector` — `detectionPipeline.ts` committed at this point (Lane C placed the file, Lane B owns the pipeline body) |
| 2 | `decfa5fc` | `feat(nis/lane-c): wire index.ts stub to call scriptureQuoteDetector implementation` — `nisProcessNote` body replaced with `await runDetectionPipeline(noteId, data)` |
| 3 | `c56af1ff` | `feat(nis/lane-b): add Wave 1 detection pipeline module` — Lane B checkpoint commit; tsc 0 errors confirmed |

---

## tsc output

```
$ cd Backend/functions && ./node_modules/.bin/tsc --noEmit
(no output — 0 errors)
```

---

## Pipeline summary

### `runDetectionPipeline(noteId, data)` — `detectionPipeline.ts`

Steps (in order):

1. **Read uid from note data** — if absent, skip silently.
2. **Extract text** — from `data.blocks[].text` (block editor format) or `data.body` fallback.
3. **Run three regex detectors** per block:
   - `detectScriptureRefs(text, blockId)` → `type: "scriptureRef"`, payload: `{book, chapter, verseStart, verseEnd, refText}`, confidence 0.92
   - `detectPrayerPatterns(text, blockId)` → `type: "prayer"`, payload: `{rawText, matchedPhrase}`, confidence 0.82
   - `detectActionItems(text, blockId)` → `type: "action"`, payload: `{rawText, matchedPhrase}`, confidence 0.78
4. **Call `nisDetectScriptureQuote(sentences, noteId)`** (imported from `./scriptureQuoteDetector`) — adds `type: "scriptureQuote"` detections.
5. **Deduplicate** — overlapping spans of the same type: keep highest confidence.
6. **Write detections** — `notes/{noteId}/detections/{id}` (one doc per detection, all in a single batch).
7. **Write graph edges** — for `scriptureRef` detections: `users/{uid}/graphEdges/{id}` with `from: {type:"note", nodeId}`, `to: {type:"scripture", nodeId:"<book>.<chapter>.<verse>", label:"<refText>"}`.
8. **Update note metadata** — `nis.lastProcessedAt`, `nis.detectionCount`, `nis.pipelineVersion: "1.0.0"`.

### Files touched

- `Backend/functions/src/nis/detectionPipeline.ts` — CREATED (Lane B owns)
- `Backend/functions/src/nis/index.ts` — MODIFIED (stub replaced with `runDetectionPipeline` call only)

### DONE criteria checklist

- [x] `tsc --noEmit` passes with 0 errors
- [x] `nisProcessNote` body calls `runDetectionPipeline` (no longer a no-op)
- [x] `detectionPipeline.ts` exports `runDetectionPipeline` with all 3 detectors + scripture quote call
- [x] All relevant commits have hashes logged in this file
- [x] No new exported type names duplicate any existing type in the repo
- [x] `pbxproj` not touched
