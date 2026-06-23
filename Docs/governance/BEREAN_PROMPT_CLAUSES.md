# Berean System-Prompt Clauses (Wave 3)

Three governance clauses are encoded directly in `BASE_SYSTEM_PROMPT` so they govern
**every** Berean mode and overlay (scholarly, pastoral, comfort, crisis, exploratory,
prayer_support, balanced). They complement — they do not replace — the existing
authority hierarchy and crisis override.

Source: `Backend/functions/src/berean/prompts/systemPrompt.ts`

| Clause | Invariant | Substance |
|--------|-----------|-----------|
| `GROUNDING_CLAUSE` | 2 | Character + claims grounded in Scripture and the historic Christian tradition, **not** training-data consensus or in-the-moment preference. |
| `COMPANION_BOUNDARY_CLAUSE` | 3 | Tool-that-points-outward, not object-of-attachment. Encodes (i) no-mediator, (ii) no-authority, (iii) no-devotion, (iv) no-dependence; prohibits "keep talking to me"; default reflex hands the user outward. |
| `EPISTEMIC_HONESTY_CLAUSE` | 7 | The Berean test (Acts 17:11): no fabricated Scripture/doctrine; separate text / interpretation / synthesis; cite or don't assert; disclose denominational disagreement; "I don't know" over guessing. |

## Defense in depth

The prompt clauses are the **first** line (shape the model's output). GUARDIAN's
`guardBereanEmission` (Wave 2) is the **second** line (inspects the candidate and forces
an outward handoff / strips unverifiable citations even if the model slips). The
Constitution articles (Wave 1) are the **durable record**. All three reference the same
prohibited-phrase list and the same Companion-Boundary clauses (i)–(iv).

## genkit deployment — now governed (was the known ungoverned path)

`genkit/berean-flows.ts` and `genkit/src/index.ts` previously carried a minimal
hard-coded prompt and did **not** route through `buildSystemPrompt` (gap G-3). The genkit
server is a separate Node deployment and cannot import the canonical builder directly, so
the canonical clauses are now **mirrored** in `genkit/governed-prompt.ts` and every
theological flow routes through `governed()`. The mirror's header names this file
(`Backend/functions/src/berean/prompts/systemPrompt.ts`) as its source of truth — if the
clauses change here, update the mirror in the same change. (Resolved; see GAPS.md G-3.)
