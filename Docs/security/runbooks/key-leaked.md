# Runbook: API Key Leaked

Applies to: Firebase API keys, Anthropic API keys, OpenAI API keys, Pinecone API keys,
Stripe secret keys, Twilio auth tokens.

---

## 1. Detect

- **Gitleaks CI failure** on the `secret-scan` job in `.github/workflows/security.yml` or
  `ios-ci.yml` — check the Actions tab for the failing workflow run and the offending commit.
- **Unexpected API costs** — provider dashboard (Anthropic Console, OpenAI Usage, Firebase
  billing) shows a sudden spend spike not explained by normal traffic.
- **Secret Manager access logs** — in GCP Cloud Audit Logs, filter for
  `secretmanager.googleapis.com` `AccessSecretVersion` calls from unfamiliar service accounts
  or source IPs.
- **Provider abuse alert** — the provider emails or flags the key for suspicious usage
  (geo-anomaly, volume spike, ToS violation).

---

## 2. Contain

1. **Revoke the key at the provider immediately** — do not wait for confirmation of misuse.
   - Firebase API key: Firebase Console > Project Settings > Web API Key > Restrict/regenerate.
   - Anthropic: console.anthropic.com > API Keys > revoke.
   - OpenAI: platform.openai.com > API Keys > revoke.
   - Stripe: Dashboard > Developers > API Keys > Roll key.
   - Twilio: Console > Account Info > Auth Token > rotate.
2. **Rotate the secret in Firebase Secret Manager**:
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY   # paste new value
   firebase functions:secrets:set OPENAI_API_KEY
   # etc.
   ```
3. **Deploy Cloud Functions** to pick up the new secret version immediately:
   ```bash
   firebase deploy --only functions
   ```
4. **Restrict or delete the leaked secret** at the provider — ensure the old value returns
   `401 Unauthorized` before moving on.
5. If the key was committed to Git history, **remove it from history** using `git filter-repo`
   or BFG Repo Cleaner, then force-push (coordinate with the team first).

---

## 3. Remediate

1. **Audit provider usage logs** for the window between the first known exposure and revocation:
   - Look for calls from unfamiliar IPs, unusual models, or batch jobs not initiated by AMEN.
   - Note any user data that may have been passed through a hijacked AI endpoint.
2. **Review Firestore audit logs** (GCP Cloud Logging > `cloudaudit.googleapis.com`) for
   unauthorized reads/writes that may have used Firebase credentials.
3. **Notify affected users** if personal data (messages, prayer content, health signals) was
   accessed by a third party — GDPR/CCPA notification obligations apply within 72 hours of
   confirmed breach.
4. **File a provider incident report** if the key was used to generate content or access user
   data — providers may have their own notification requirements.

---

## 4. Review

- Add the specific key pattern (if novel) to `.gitleaks.toml` `[[rules]]` so it is caught
  automatically in future scans.
- Add a **pre-commit hook** via Lefthook or Husky that runs `gitleaks protect --staged`
  before every commit:
  ```bash
  # .lefthook.yml (or .husky/pre-commit)
  pre-commit:
    commands:
      gitleaks:
        run: gitleaks protect --staged --config .gitleaks.toml
  ```
- Review `Config.xcconfig` handling — ensure the template (`Config.xcconfig.template`) uses
  placeholder values and the real file is in `.gitignore`.
- Schedule a quarterly rotation of all production secrets as a calendar reminder.
- Update this runbook with any new provider-specific steps discovered during the incident.
