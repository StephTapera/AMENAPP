# Capabilities v1 — Frozen Surfaces

**Posted by ARCHITECT at Wave 0 gate.**

The following files are write-locked after Wave 0. No agent may modify them without filing a `CONTESTED` blocker in BLOCKERS.md and waiting for human resolution.

## Write-Locked Files

| File | Locked Since | Description |
|---|---|---|
| `Docs/Capabilities/CONTRACTS.md` | Wave 0 | All Firestore schemas, callable signatures, Swift/TS types |
| `AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift` | Wave 0 | Frozen Swift model types |
| `functions/src/capabilities/types.ts` | Wave 0 | Frozen TypeScript types + zod schemas |
| `AMENAPP/firestore.deploy.rules` (Capabilities section) | Wave 0 | Security rules for new collections |

### Pre-existing frozen surfaces (apply to all builds)
- Design system tokens (`DesignSystem/`)
- Navigation root (`ContentView.swift`, `HomeView.swift` nav stack)
- Berean streaming pipeline (any file that wraps SSE/Berean backend directly)
- Notification pipeline internals (FCM dispatch functions)
- API.Bible proxy internals (existing scripture proxy callable)

## Lane Ownership Map

| Lane | Agent | Exclusive Write Directories |
|---|---|---|
| A | BACKEND-CONTEXT | `functions/src/contextEngine/**` |
| B | BACKEND-CAPS | `functions/src/capabilities/**`, `functions/src/capabilities/scripts/**` |
| C | CLIENT-CORE | `AMENAPP/AMENAPP/Capabilities/CapabilityPicker/**`, `AMENAPP/AMENAPP/Capabilities/CapabilityRegistryStore.swift`, `AMENAPP/AMENAPP/Capabilities/ContextSettings/**` |
| D | CLIENT-PRAYER | `AMENAPP/AMENAPP/Capabilities/PrayerOS/**` |
| E | CLIENT-SCRIPTURE | `AMENAPP/AMENAPP/Capabilities/ScriptureIntelligence/**`, `AMENAPP/AMENAPP/Capabilities/VerseLookup/**` |

## Contested File Protocol

If your work requires changing a frozen surface:
1. **Do not change it.**
2. Append to `Docs/Capabilities/BLOCKERS.md` with severity `CONTESTED`.
3. Continue working on non-dependent items.
4. Human resolves the contested change; INTEGRATOR applies it in Wave 2.
