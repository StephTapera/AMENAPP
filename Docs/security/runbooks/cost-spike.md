# Runbook: AI / Cloud Cost Spike

Applies to: Anthropic (Berean AI), OpenAI (whisper, smart suggestions), Firebase (Firestore
reads, Cloud Functions invocations), GCP Vision, Cloud Translation.

---

## 1. Detect

- **`hourlyAnomalyCheck` alert** — a `meta/anomalyAlerts/alerts/{id}` document appears with
  `type: "ai_spend_warning"` or `type: "per_user_berean_spike"`. Check the `pct`, `current`,
  and `cap` fields to understand severity.
- **Firebase billing alert** — a budget alert email arrives from `billing-noreply@google.com`
  for the Firebase/GCP project.
- **Per-user anomaly in Firestore** — query
  `meta/anomalyAlerts/alerts` where `status == "new"` and `type == "per_user_berean_spike"`
  to identify the responsible `userId`.
- **Provider dashboard** — Anthropic Console or OpenAI Usage page shows a spike not correlated
  with normal daily traffic patterns.

---

## 2. Contain

1. **Kill all AI calls immediately** by setting the circuit-breaker cap to 0 in Firestore:
   ```
   Firestore > config/aiLimits > anthropicDailyGlobalCap = 0
   Firestore > config/aiLimits > openaiDailyGlobalCap    = 0
   ```
   The `recordAIUsageAndCheckLimit` and `requirePremiumFeature` callables check these caps
   before forwarding to the provider — setting to 0 blocks all calls without a deploy.
2. **Identify the responsible userId** from the `per_user_berean_spike` alert or by querying:
   ```
   Firestore > users/{userId}/aiUsage
   ```
   Filter by `createdAt >= now - 1h` and sort by count descending.
3. **Temporarily disable the account** if abuse is confirmed — use Firebase Auth Admin SDK or
   the Firebase Console to disable the user, preventing further calls.
4. **Check for anonymous path abuse** — query `meta/globalAICosts/daily/{dayKey}` for a field
   `anonymousCalls`. If elevated, the `anonymousBereanQuery` callable may be under attack.
   Temporarily restrict it by setting a feature flag in `config/featureFlags`:
   ```
   anonymousBerean: false
   ```

---

## 3. Remediate

1. **Restore caps to normal levels** once the abuser is contained:
   ```
   config/aiLimits > anthropicDailyGlobalCap = 2000
   config/aiLimits > openaiDailyGlobalCap    = 5000
   ```
2. **Tighten per-user rate limits** in `config/aiLimits` if the existing per-user cap was
   too permissive (e.g., reduce `perUserHourlyBereanCap` from 50 to 20).
3. **Add CAPTCHA** to the anonymous Berean path if it was abused — add a
   `recaptchaToken` field to the callable request and verify it server-side using the
   reCAPTCHA Enterprise API before forwarding to Anthropic.
4. **Review the specific user's account** — check whether the account was compromised
   (credential stuffing) or whether the user is intentionally abusing the service.
   Apply a permanent cap override in `users/{userId}/limits` if needed.
5. **Dispute unexpected charges** with the provider if abuse was from a compromised key
   (see `key-leaked.md`).

---

## 4. Review

- Tune `THRESHOLDS` in `functions/anomalyMonitor.js` based on observed normal traffic
  patterns. Typical daily Berean calls per active user should be measured over 7 days and
  the warning threshold set to 3x that average.
- Add a **Slack/email webhook** to `anomalyMonitor.js` (the `TODO` comment at the bottom
  of the file) so alerts reach on-call engineers in real time rather than requiring a
  Firestore query.
- Consider adding a **Firebase billing budget alert** at 50% and 90% of monthly budget via
  GCP Console > Billing > Budgets & Alerts to catch infrastructure cost spikes independently
  of the application-level monitors.
- Update this runbook with the actual thresholds confirmed to be normal after 30 days of
  production traffic.
