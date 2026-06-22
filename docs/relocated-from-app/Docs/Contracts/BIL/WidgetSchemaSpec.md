# BIL Widget Schema v1 Contract

Frozen: 2026-06-11  
Version: `bil-widget-schema-v1`  
Feature: BI-13 Generative Widgets + Artifact Workspace

Berean may emit declarative widget JSON only. It may not emit raw HTML, JavaScript, Swift source, executable snippets, remote script URLs, inline event handlers, or arbitrary style declarations for client execution.

## Envelope

```json
{
  "schemaVersion": 1,
  "widgetId": "w_opaque_id",
  "kind": "comparison_table|fillable_form|checklist|scripture_card|chart",
  "title": "string",
  "data": {},
  "actions": [
    { "id": "string", "label": "string", "intent": "copy|save_artifact|create_commitment|attach_source|none" }
  ],
  "tier": "tier_s|tier_c|tier_p",
  "sourceRefs": [{ "kind": "turn|source_card|ledger_entry", "id": "string" }],
  "validationHash": "sha256_of_canonical_json"
}
```

Limits: title <= 120 characters, widget JSON <= 64 KB, max actions 4, max source refs 20. Unknown keys cause validation failure unless explicitly listed as `x_` experimental fields and ignored by the renderer.

## Kinds

### `comparison_table`

```json
{
  "columns": [{ "id": "string", "title": "string", "type": "text|number|badge|citation" }],
  "rows": [{ "id": "string", "cells": { "columnId": "string|number|object" } }],
  "sort": { "columnId": "string", "direction": "asc|desc" }
}
```

Validation: max 8 columns, max 50 rows, no Markdown tables inside cells. Citation cells reference Source Card citation IDs.

SwiftUI mapping: `BILComparisonTableWidget` using native `Table` where available and a responsive grid fallback on compact width.

### `fillable_form`

```json
{
  "fields": [
    { "id": "string", "label": "string", "type": "text|textarea|date|single_select|multi_select|toggle", "required": true, "options": ["string"] }
  ],
  "submitIntent": "save_artifact|create_commitment|none"
}
```

Validation: max 20 fields; labels <= 80 characters; option count <= 12. Form submissions produce client-owned data and require explicit user action.

SwiftUI mapping: `BILFormWidget` with native controls, dynamic type support, and no auto-submit.

### `checklist`

```json
{
  "items": [{ "id": "string", "title": "string", "detail": "string?", "checked": false, "commitmentSuggestionId": "string?" }]
}
```

Validation: max 100 items. Items linked to commitments must reference BI-08 `CommitmentSuggestion` or existing `AmenCommitmentObject` IDs.

SwiftUI mapping: `BILChecklistWidget` with `Toggle` rows and optional create-commitment action.

### `scripture_card`

```json
{
  "reference": "string",
  "translation": "string",
  "text": "string",
  "layers": [{ "layer": "text|context|interpretation|tradition|application", "summary": "string", "citationIds": ["string"] }]
}
```

Validation: scripture reference must pass `ScriptureReferenceValidator` before rendering as verified. Unverified references render with an explicit unverified state.

SwiftUI mapping: `BILScriptureCardWidget`; layer 5 application must be visually distinct from layer 1 text.

### `chart`

```json
{
  "chartType": "bar|line|donut|timeline",
  "series": [{ "id": "string", "label": "string", "points": [{ "x": "string|number", "y": 0 }] }],
  "unit": "string?"
}
```

Validation: max 5 series, max 100 points per series, no remote data references. Charts are informational only and cannot imply medical/legal/financial certainty.

SwiftUI mapping: native Charts if available; otherwise a static accessible summary list.

## Artifact Workspace

Persistent artifacts use this envelope:

```json
{
  "artifactId": "string",
  "ownerUid": "string",
  "threadId": "string",
  "title": "string",
  "kind": "document|code|note|study_guide|widget_collection",
  "tier": "tier_s|tier_c|tier_p",
  "currentVersionId": "string",
  "versions": [{ "id": "string", "createdAt": "Timestamp", "createdBy": "user|berean", "summary": "string", "contentRef": "string" }]
}
```

Tier P artifacts are local-only. Tier S/C artifacts may use Firestore version history after feature flags and permissions are enforced.

## Validation Rules

1. Parse with a strict JSON decoder into typed Swift models. Do not render unknown widget kinds.
2. Reject any field containing `<script`, `javascript:`, `data:text/html`, inline event attributes, or remote executable URLs.
3. Reject actions outside the allowed `intent` enum.
4. Enforce tier before persistence or source lookup.
5. Validate all Source Card citation IDs against authorized source cards before rendering citations.
6. Render a neutral unsupported-widget fallback for validation failures; do not crash the chat.
7. Analytics may log widget kind and validation result only, not widget content.

## Component Mapping Table

| Schema kind | SwiftUI component | Feature flag | Notes |
| --- | --- | --- | --- |
| `comparison_table` | `BILComparisonTableWidget` | `bil_widgets` | Sortable only when row count > 1. |
| `fillable_form` | `BILFormWidget` | `bil_widgets` | Submit requires user tap. |
| `checklist` | `BILChecklistWidget` | `bil_widgets` | Commitment creation requires BI-08 flag. |
| `scripture_card` | `BILScriptureCardWidget` | `bil_scripture_crosscheck` and `bil_widgets` | Must honor epistemic layer visuals. |
| `chart` | `BILChartWidget` | `bil_widgets` | Accessible text summary required. |
| Artifact pane | `BILArtifactWorkspaceView` | `bil_artifact_workspace` | No server version history for Tier P. |
