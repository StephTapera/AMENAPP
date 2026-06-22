# Wave 0 — Flag Registration Plan + Pinecone Namespace Conventions

> **PENDING HUMAN FREEZE — nothing wired yet.** No edits to `AMENFeatureFlags.swift`,
> `RAG_NAMESPACES`, or Remote Config. All flags default **OFF**.

## 1. Feature flags (§4.5)

The canonical registry is `AMENFeatureFlags.swift` (Remote Config-wired:
`@Published` + RC key + `refreshRemoteConfig`). A **second**, divergent registry
exists — `BereanVoiceFeatureFlags.swift` — a static struct that **hardcodes every
flag to `true`** with a DEBUG override, **bypassing Remote Config kill switches.**
Closing that drift is the highest-priority flag task.

| Flag | Rec | Source → target | Default |
|---|---|---|---|
| `berean_voice_enabled` (master) | **REUSE** | already canonical (`AMENFeatureFlags` ~line 35, RC ~1643) | false |
| `berean_voice_transport_realtime` | **BUILD-NEW** | add to `AMENFeatureFlags` + RC | false → pipeline path |
| `berean_voice_formation_engine` | **BUILD-NEW** | add to `AMENFeatureFlags` + RC | false |
| `berean_voice_mode_empathy` | **RENAME-TO-EXISTING** | migrate `BereanVoiceFeatureFlags.bereanVoiceEmpathyMode` → canonical | false |
| `berean_voice_mode_church` | **RENAME-TO-EXISTING** | migrate `bereanVoiceChurchMode` → canonical | false |
| `berean_voice_mode_prayer` | **RENAME-TO-EXISTING** | migrate `bereanVoicePrayerMode` → canonical | false |
| `bereanVoiceKillSwitch` | **OPTIONAL NEW** | `AMENFeatureFlags` + RC | (no voice-lifecycle kill switch exists today) |

**Per-mode flags from the spec** (`berean_voice_mode_study/sermon/walk/group/creator/decision`)
should follow the same canonical pattern, default false — register them as the
modes are built (Waves 3–9), not all up front.

⚠️ **Drift to close:** until `bereanVoiceEmpathy/Church/Prayer` move out of the
static struct, production voice code reading that struct **cannot be killed
remotely**. There is also a second master switch `bereanVoiceAssistantEnabled`
(~line 653) — confirm which gates what so they don't diverge.

## 2. Pinecone namespace conventions (§4.4)

**Convention (confirmed from existing code):** the codebase uses **single shared
namespaces with a metadata filter** (e.g. `user-interest-embeddings` filtered by
`userId`), **not** per-user namespaces. `formation-memory:{uid}` etc. in the spec
should therefore be `formation-memory` + `userId` metadata. Reuse
`pineconeUpsert/Query/Delete` + `openaiEmbed` (`functions/mlClients.js`) and extend
the `RAG_NAMESPACES` map (`functions/amenAIFeatures.js`).

| Spec namespace | Rec | Final namespace | Note |
|---|---|---|---|
| `scripture-graph` | **RENAME-TO-EXISTING** | `scripture-embeddings` | Real existing 31K-verse KJV shared corpus (`semanticEmbeddings.js`). A *topical verse-to-verse graph* is **not** implemented — if that distinct concept is intended, it is separate BUILD-NEW, flag it. |
| `formation-memory:{uid}` | **BUILD-NEW** | `formation-memory` + `userId` filter | reuse single-namespace convention |
| `prayer-memory:{uid}` 🔒 | **BUILD-NEW** | `prayer-memory` + `userId` filter | **BLOCKED on E2EE decision** — vectors are currently unencrypted; encrypted-at-rest needs key derivation + per-vector AES-GCM + CF-side decrypt. `prayer-partner-pool` (existing, transient) is **not** a substitute. |
| `study-project:{projectId}` | **BUILD-NEW** | `study-project` + `projectId` filter | reuse `onTestimonyCreated`-style auto-embed trigger |
| `org-memory:{orgId}` | **BUILD-NEW** | `org-memory` + `orgId` filter | needs query-time isolation filter + org ACL (`church-notes-embeddings` is one shared namespace today, no org isolation) |

### Account-deletion obligation
`accountDeletion` currently **swallows Pinecone delete errors silently.** Every new
namespace (`formation-memory`, `prayer-memory`, `study-project`, `org-memory`) MUST
be added to the purge path, and the silent-swallow should be surfaced/logged.

## 3. Deploy/region note (CLAUDE.md)

All new voice callables (`bereanVoiceIngestTurn`, formation orchestrate) → **us-east1**
(us-central1 at 999/1000). `voicePrayer.js` hardcodes `us-central1` (line ~29) and
its disabled exports — **do not copy that pattern.** Add a `docs/FUNCTION_INVENTORY.md`
Interim Region Table entry **before** any deploy. New callables must be exported in
`Backend/functions/src/index.ts` or they won't deploy even if the files exist.
