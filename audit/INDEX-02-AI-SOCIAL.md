# AI-in-Social Features Audit — Complete Documentation

**Audit Date**: 2026-05-27  
**Auditor**: Claude Code (AI-in-Social-Features Specialist)  
**Scope**: All AI touchpoints in social features (posts, comments, DMs, reports, crisis)  
**Status**: ✅ COMPLETE

---

## Document Index

### Quick Start
- **[02-ai-social-SUMMARY.txt](02-ai-social-SUMMARY.txt)** — Executive summary, 2-page cheat sheet
  - 12 findings (2 critical, 3 high, 5 medium, 2 low)
  - Moderation matrix by surface
  - Priority roadmap for fixes
  - Legal/compliance notes

### Full Audit Report
- **[02-ai-social.md](02-ai-social.md)** — Complete 801-line technical report
  - Detailed findings with evidence and recommendations
  - Architecture strengths and weaknesses
  - Privacy disclosure checklist
  - Handoff flows (client → server → AI providers)
  - Open questions and blocked items
  - Remediation roadmap (priority-ordered)

---

## Key Takeaways

### Architecture
✅ **Strengths:**
- Server-side enforcement (client-only checks are advisory)
- Fail-open safeguards (never silently approve dangerous content)
- Sacred/monitored channel separation (E2E encryption for adults only)
- Multi-layer defense (banned terms, Perspective, Vision, policy)
- Crisis content never blocked (always delivers + resources)

❌ **Weaknesses:**
- 4+ moderation entry points for posts (complex, hard to audit)
- Privacy disclosure gaps (monitored DMs, comment rejection)
- No unified appeal or moderation history UI
- Async comment moderation (silent deletion, fire-and-forget)
- Shadow-ban capability (potentially deceptive)

### AI Integrations
| AI Provider      | Usage                              | Quality | Risk |
|------------------|------------------------------------|---------|------|
| Claude (Anthropic)| Guardian DMs, comments, content    | ✅ Good | LOW |
| Perspective API  | Text toxicity (audit-only, no block)| ✅ Good | LOW |
| Cloud Vision     | Image SafeSearch (all images)      | ⚠ Medium | MEDIUM |
| Vertex Gemini    | Crisis detection (post-pub, no block)| ⚠ Medium | LOW |

### Privacy/Compliance
| Issue              | Severity | Status | COPPA | GDPR | FTC |
|--------------------|----------|--------|-------|------|-----|
| DM disclosure      | CRITICAL | Open   | ⚠    | ✓    | ⚠   |
| Shadow-ban         | CRITICAL | Open   | —    | ✓    | ⚠   |
| Comment appeal     | MEDIUM   | Open   | —    | ⚠    | —   |
| Post appeal        | MEDIUM   | Open   | —    | ⚠    | —   |

---

## Critical Findings (Must Fix)

### 1. DM Privacy Disclosure Missing [F-social-012]
**Issue:** Monitored channels (minors) are silently AI-scanned but show no disclosure.  
**Impact:** COPPA violation, informed consent gap, user trust erosion.  
**Fix:** Add in-composer banner "Monitored for safety — messages are checked before delivery."  
**Effort:** 1-2 days.  
**Files:** `AMENAPP/AMENAPP/AMENAPP/Messaging/` (UI) + backend flag.

### 2. Shadow-Ban Capability Lacks Transparency [F-social-011]
**Issue:** `.shadowQueue` action silently hides content from others while showing to author.  
**Impact:** Deceptive UX, potential legal liability, user trust.  
**Fix:** Remove `.shadowQueue` enum or implement full transparency (always notify author).  
**Effort:** 1-2 days.  
**Files:** `AMENAPP/ModerationPipeline.swift` (remove enum), post/comment deletion logic.

---

## High Findings (Should Fix Soon)

### 3. Monitored DM Consent Not Obtained [F-social-001]
**Issue:** Users don't consent to AI processing of DMs with minors.  
**Fix:** Require explicit acknowledgment before first send in monitored channel.  
**Effort:** 2-3 days (UI + consent store).

### 4. Post Moderation Lacks Unified Entry Point [F-social-003]
**Issue:** 4+ stages (client NLP → Claude ingest → preflight → per-media → async).  
**Fix:** Consolidate into single server-side gate; client is advisory only.  
**Effort:** 5-7 days (refactoring).

### 5. AI Transparency Labels Missing [F-social-008]
**Issue:** Moderation decisions are not registered with `AmenAITransparencyService`.  
**Fix:** Call `registerAIContent()` after every moderation decision.  
**Effort:** 2-3 days (add calls, test).

---

## Medium Findings (Next Sprint)

| ID | Issue | Effort | Impact |
|----|-------|--------|--------|
| F-social-002 | Comment moderation async (no pre-publish gate) | 2-3 days | UX/appeal |
| F-social-004 | DM patterns hardcoded (move to Firestore) | 1-2 days | Config agility |
| F-social-006 | Crisis detection lacks audit trail | 1 day | Feedback loop |
| F-social-007 | Report flow has no appeal | 3-5 days | User fairness |
| F-social-010 | Image quarantine lacks SLA | 1-2 days | UX clarity |

---

## Code Locations (Quick Reference)

### Client (Swift)
- **DM & Sacred Chat**: `AMENAPP/AMENAPP/AMENAPP/Messaging/ChannelService.swift` (L30–39)
- **Guardian Service**: `AMENAPP/AMENAPP/AMENAPP/Guardian/GuardianService.swift`
- **Guardian Models**: `AMENAPP/AMENAPP/AMENAPP/Guardian/GuardianModels.swift`
- **Post Publishing**: `AMENAPP/CreatePostView.swift` (L3678–3980)
- **Comment Moderation**: `AMENAPP/CommentClaudeModerator.swift`
- **Moderation Pipeline**: `AMENAPP/ModerationPipeline.swift` (L155–620)
- **AI Transparency**: `AMENAPP/AmenAITransparencyService.swift`
- **DM Risk Warning**: `AMENAPP/AMENAPP/AMENAPP/MessagingOS/AmenMessageSafetyWarningSheet.swift`

### Backend (TypeScript/JavaScript)
- **Guardian Moderation**: `cloud-functions/guardian.ts`
- **Text Moderation**: `Backend/functions/src/trustSafety/moderateText.ts`
- **Image Moderation**: `Backend/functions/src/trustSafety/moderateImage.ts`
- **Crisis Detection**: `cloud-functions/crisis-detection.js`
- **Report Submission**: `Backend/functions/src/trustSafety/reportAbuse.ts`

---

## Remediation Priority Matrix

```
Impact
  High │ [CRITICAL] DM Disclosure    [CRITICAL] Shadow-ban
       │ [HIGH] Monitored consent    [HIGH] Moderation unify
       │ [MEDIUM] Appeal flow         [MEDIUM] Transparency labels
       │ [LOW] Pattern config         [LOW] Audit trail
       └─────────────────────────────────────────────────
         Low                      Effort                   High
```

**Recommendation**: Fix CRITICAL items (diagonal, low effort) first. Then HIGH items. Leave LOW for Q3.

---

## Testing & Validation Checklist

- [ ] DM disclosure banner appears for monitored channels only (not sacred)
- [ ] Minors cannot open sacred channels with adults (enforced server-side)
- [ ] Comments are held for review (not deleted) before moderation decision
- [ ] Moderation decisions are logged with AI model metadata
- [ ] Appeals are discoverable from moderation notification
- [ ] Crisis content is never blocked (always delivers + resources)
- [ ] Shadow-queue action is removed or transparency-enabled
- [ ] Image quarantine includes human review SLA (24h)
- [ ] User can view moderation history (audit log)

---

## Compliance Checklist

### COPPA (Children's Online Privacy Protection Act)
- [ ] Monitored DM disclosure in composer (required for minors)
- [ ] Parental consent mechanism (if collecting minor data)
- [ ] No sale of minor data to third parties (verified with Anthropic, Google)

### GDPR (EU)
- [ ] User can request access to moderation decisions
- [ ] User can submit appeal (right to contest)
- [ ] Moderation data separate from user profile (retention policy)

### FTC (Unfair/Deceptive Practices)
- [ ] No shadow-banning without transparency
- [ ] AI involvement disclosed (if AI made moderation decision)
- [ ] Appeal mechanism exists (if content removal affects user)

### CCPA (California Consumer Privacy Act)
- [ ] User can access/delete moderation records
- [ ] Third-party AI vendor (Claude, Vision) listed as service provider
- [ ] No sale of moderation data

---

## Next Actions

1. **Immediate** (This Week)
   - [ ] Review findings with Trust & Safety lead
   - [ ] Agree on priority: fix CRITICAL items first
   - [ ] Schedule design review: DM disclosure UI mockups

2. **Short-term** (Next Sprint)
   - [ ] Implement DM disclosure banner
   - [ ] Remove or transparency-enable shadow-queue
   - [ ] Begin comment pre-publish gate design

3. **Medium-term** (Next 2-3 Sprints)
   - [ ] Unify post moderation pipeline
   - [ ] Build appeal flow (email + form + decision log)
   - [ ] Implement moderation transparency dashboard

4. **Long-term** (Q3+)
   - [ ] Audit AI model bias (partner with external auditor)
   - [ ] Implement moderation analytics (false positive rate, appeals)
   - [ ] Re-audit social features (measure improvements)

---

## Contact & Questions

For questions on findings or recommendations:
- **Auditor**: Claude Code (AI-in-Social-Features)
- **Report**: `/audit/02-ai-social.md` (801 lines, detailed)
- **Summary**: `/audit/02-ai-social-SUMMARY.txt` (2 pages, quick reference)

---

_End of Index_
