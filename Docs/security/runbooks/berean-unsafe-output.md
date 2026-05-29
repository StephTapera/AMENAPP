# Runbook: Berean AI Unsafe Output

Applies to: All Berean AI callables (`bereanBibleQA`, `bereanMoralCounsel`,
`bereanPostAssist`, `bereanCommentAssist`, `bereanDMSafety`, `anonymousBereanQuery`,
`livingWordEngine`, `vibeMatch`, `digestBrain`, `spiritGraph`) and any callable that
proxies Anthropic or OpenAI responses to the client.

---

## 1. Detect

- **`bereanGuardrails` output validation fires** — a `meta/guardrailViolations/{id}` document
  is written with `stage: "output"`. Check the `pattern`, `severity`, and `callableId` fields.
- **User report** — a user reports receiving harmful, sexually explicit, theologically extreme,
  or personally dangerous content from a Berean AI feature.
- **Content moderation flag** — the `moderateContent` or `serverSidePostModeration` pipeline
  flags a post or message that originated from a Berean AI suggestion.
- **Prompt injection indicator** — a guardrail violation document has `stage: "input"` and
  `pattern` matching an injection attempt (e.g., `ignore_previous_instructions`,
  `jailbreak`, `DAN`). This means a bypass was attempted; check whether output was also
  affected.

---

## 2. Contain

1. **Deploy updated guardrail patterns immediately** — add the new bypass or harmful output
   pattern to the appropriate list in `functions/bereanGuardrails.js` (or the equivalent
   file in your codebase) and deploy:
   ```bash
   firebase deploy --only functions:bereanBibleQA,functions:anonymousBereanQuery
   # or deploy all functions if the pattern applies broadly
   firebase deploy --only functions
   ```
2. **Lower the block threshold** temporarily to increase sensitivity while the full pattern
   is investigated:
   - In `bereanGuardrails.js`, find the `OUTPUT_VIOLATION_THRESHOLD` constant and set it
     to `0.25` (flag more aggressively) for the affected callable.
   - Deploy immediately; this will produce more false positives but prevents harm while the
     root cause is understood.
3. **If the callable is actively producing harmful output at scale**, disable it entirely
   via a feature flag in Firestore:
   ```
   Firestore > config/featureFlags > bereanBibleQA = false
   ```
   The callable should check this flag and return a graceful error to the client.
4. **Preserve the offending prompt and response** — copy the `meta/guardrailViolations/{id}`
   document and any associated `users/{uid}/bereanHistory` entry to a secure incident
   collection before any cleanup jobs delete them.

---

## 3. Remediate

1. **Add the bypass pattern** to `INJECTION_PATTERNS` in `bereanGuardrails.js` if it was a
   prompt injection:
   ```javascript
   const INJECTION_PATTERNS = [
     // ... existing patterns ...
     /your_new_bypass_pattern_here/i,
   ];
   ```
2. **Add the harmful output pattern** to `OUTPUT_VIOLATION_PATTERNS` if the LLM produced
   content that should be blocked at the output layer regardless of input:
   ```javascript
   const OUTPUT_VIOLATION_PATTERNS = [
     // ... existing patterns ...
     /your_new_output_pattern_here/i,
   ];
   ```
3. **Review the system prompt** for the affected callable — determine whether the harmful
   output resulted from an ambiguous or under-specified system prompt. Tighten the spiritual
   and safety framing (e.g., add explicit refusal instructions for the category of content
   that was generated).
4. **Notify the affected user** if the content could cause personal harm (e.g., crisis content
   was generated without appropriate resources, or theologically harmful advice was given).
   Use a warm, faith-aligned communication that acknowledges the failure without specifying
   what the AI produced.
5. **Check for data in Berean history** — if the harmful response was stored in
   `users/{uid}/bereanHistory`, delete the specific entry using the `deleteBereanHistory`
   callable or Admin SDK to prevent it surfacing in future context windows.

---

## 4. Review

- **Add the specific prompt to the regression test set** in
  `functions/__tests__/bereanGuardrails.test.js` (or the equivalent test file). The test
  should assert that the prompt triggers a block:
  ```javascript
  it('blocks the [incident-name] bypass pattern', async () => {
    const result = await checkInputGuardrails('your_bypass_prompt_here');
    expect(result.blocked).toBe(true);
    expect(result.reason).toMatch(/injection/i);
  });
  ```
- Run the full guardrails test suite locally before merging:
  ```bash
  cd functions && npx jest bereanGuardrails
  ```
- **Audit Anthropic system prompt** against current Anthropic usage policy — some bypass
  patterns exploit provider-side model behavior; report them to Anthropic via
  `safety@anthropic.com` with the sanitized prompt and response.
- **Review the `anonymousBereanQuery` callable** separately — it has no `userId` context
  and therefore no rate-limit-per-user protection. If the attack came through the anonymous
  path, consider requiring at minimum a valid App Check token and adding a stricter output
  filter for anonymous sessions.
- Update `docs/security/THREAT_MODEL.md` with the new attack vector under the Berean AI
  section, noting the detection method, containment action, and mitigating control added.
- Schedule a **monthly red-team exercise** where a developer attempts to jailbreak each
  Berean callable using current known techniques (jailbreak databases, DAN variants) and
  verifies the guardrails block all attempts.
