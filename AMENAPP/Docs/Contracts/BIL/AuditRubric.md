# BIL Audit Stake Rubric and GUARDIAN Capability

Frozen: 2026-06-11  
Version: `bil-wave0-v1`  
Feature: BI-11 Multi-Agent Answer Audit

## Capability Registration

Reserved capability ID:

```text
C59_BEREAN_MULTI_AGENT_ANSWER_AUDIT
```

Finding: no canonical all-caps `GUARDIAN` registry type was found in the current Xcode project. Aegis/content-safety extension points exist and are the binding implementation path for Wave 2 unless a canonical registry is introduced.

Approved registration path:

- `AmenConnectSpacesPhase0BindingService.runAegisInputGate`
- `AmenConnectSpacesPhase0BindingService.runAegisOutputGate`
- `AmenContentSafetyService.quickCheck/checkContent/checkBeforePost`
- `BereanContextCoordinator.addMedicalGuardrail`
- `BereanOSBridgeObserver` notifications for crisis/support state

BIL may add a thin adapter named for C59, but it may not modify Aegis internals without a contract amendment.

## Stake Classification

| Stake class | Triggers | Required audit critics |
| --- | --- | --- |
| `trivial` | Greetings, small talk, simple app navigation, low-impact wording help. | None. Scratchpad may say audit skipped. |
| `normal` | Ordinary advice, summarization, low-risk planning. | Optional factual/privacy spot checks when retrieval is used. |
| `faith_theology` | Bible interpretation, doctrine, church guidance, prayer/theology explanation. | Scripture grounding, factual accuracy, safety, privacy/tier. |
| `crisis_adjacent` | Self-harm, abuse, despair, urgent pastoral care, coercion, minors. | Safety, privacy/tier, factual accuracy. Must run Aegis/content-safety hooks. |
| `medical_legal_adjacent` | Health, medication, diagnosis, legal/financial claims, mandated reporting. | Safety, factual accuracy, privacy/tier. Must include non-professional boundary. |
| `architecture` | App architecture, security, data migration, Firebase rules, encryption, billing/cost. | Product logic, implementation risk, privacy/tier, factual accuracy. |
| `privacy_sensitive` | Tier C/P content, minors, private Spaces, source-card permissions, encrypted data. | Privacy/tier, safety, product logic. |

The highest matched class wins. Multiple classes may attach as reason codes.

## Critic Contracts

| Critic | Purpose | Pass condition | Fail condition |
| --- | --- | --- | --- |
| `factual_accuracy` | Check factual claims and sourced context. | Claims are supported or framed with uncertainty. | Unsupported high-impact claims presented as fact. |
| `scripture_grounding` | Check BI-06 text/context/interpretation/tradition/application layering. | Scripture references validate and layers are visually/textually distinct. | Application or interpretation presented as direct scripture. |
| `safety` | Check Aegis/content-safety concerns. | Response handles risk calmly and routes to existing resources. | Response escalates harm, ignores crisis, or provides unsafe instruction. |
| `privacy_tier` | Check Tier S/C/P boundaries. | No unauthorized source or Tier P plaintext leaves local boundary. | Any server payload/log/vector/audit evidence contains Tier P plaintext. |
| `product_logic` | Check AMEN product contracts. | Uses existing primitives and flags, no vanity/dark pattern. | Creates parallel task system, bypasses flags, or violates product philosophy. |
| `implementation_risk` | Check engineering feasibility. | Notes constraints and avoids brittle implementation claims. | Claims implemented behavior that does not exist or breaks frozen surfaces. |

Critic output shape is defined in `DataSchemas.md` `AuditReport`.

## Audit Execution Rules

1. `trivial` requests skip audit entirely.
2. `normal` requests may skip audit unless retrieval, source cards, commitments, or private data are involved.
3. `faith_theology`, `crisis_adjacent`, `medical_legal_adjacent`, `architecture`, and `privacy_sensitive` must run the required critics when `bil_answer_audit` is enabled.
4. Tier P cannot run server critics. Use local deterministic critics only or mark server critics `skipped` with reason `tier_p_local_only`.
5. Any `fail` verdict blocks auto-send and requires either response regeneration or a visible safe fallback.
6. Any `warn` verdict may send only if the final response includes appropriate uncertainty, citation, safety boundary, or product caveat.
7. The visible `Checked` affordance shows only sanitized verdict summaries.

## Latency and Cost Budgets

Initial Wave 2 budget assumptions:

| Stake class | Target added latency | Max critics |
| --- | --- | --- |
| `normal` | <= 400 ms | 2 lightweight/local |
| `faith_theology` | <= 1500 ms | 4 |
| `crisis_adjacent` | <= 1000 ms | 3, safety first |
| `medical_legal_adjacent` | <= 1200 ms | 3 |
| `architecture` | <= 1800 ms | 4 |
| `privacy_sensitive` | <= 1000 ms | 3 |

Stop condition: if projected per-user audit/routing cost exceeds the Wave 0 budget assumptions above by more than 25% in QA load tests, halt enablement and report.

## User-Visible Copy Constraints

Allowed: `Checked`, `Scripture grounding checked`, `Privacy boundary checked`, `Server audit skipped in private mode`.

Forbidden: detailed hidden reasoning, raw critic prompts, scare language, or claims that Aegis/Guardian guarantees correctness.
