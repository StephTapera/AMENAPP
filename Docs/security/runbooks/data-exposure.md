# Runbook: Firestore Data Exposure

Applies to: Firestore security rules gaps that allow unauthorized reads or writes to user
data, posts, messages, prayer content, church notes, or admin collections.

---

## 1. Detect

- **Firestore rules test failure** on the `rules-test` CI job in
  `.github/workflows/security.yml` — a previously passing deny test now fails, or a new
  allow test reveals a broader permission than intended.
- **User report** — a user reports seeing another user's private content, prayer requests,
  or messages they should not have access to.
- **Security scan finding** — a penetration test or automated scanner finds a rule that
  allows unauthenticated or cross-user reads on a sensitive collection.
- **Cloud Audit Logs anomaly** — GCP Cloud Logging shows unexpected read volume on
  collections like `users/{uid}/messages`, `conversations`, or `prayerRequests` from
  unfamiliar `callerSuppliedUserAgent` values.

---

## 2. Contain

1. **Tighten the affected rule to deny all** as a temporary measure — patch `firestore.rules`
   with a blanket deny on the affected collection path and deploy immediately:
   ```bash
   firebase deploy --only firestore:rules
   ```
   This may temporarily break legitimate client functionality; that is acceptable while the
   scope of exposure is assessed.
2. **Assess scope** — query Cloud Audit Logs for `dataAccess` log entries on the affected
   collection over the exposure window:
   - GCP Console > Logging > Filter: `resource.type="datastore_database"` +
     `protoPayload.resourceName` contains the collection path.
   - Export to BigQuery if the volume is large.
3. **Count affected users** — identify which `userId` values had their data accessed by
   principals other than themselves.
4. **Preserve evidence** — export the raw audit log entries to Cloud Storage for any
   potential regulatory or legal review before the 400-day GCP log retention window closes.

---

## 3. Remediate

1. **Patch the Firestore rules** — write the correct, least-privilege rule for the affected
   collection. Follow the existing rule conventions in `firestore.rules`:
   - Owner-only read: `request.auth.uid == resource.data.userId`
   - Participant-only read (messages): `request.auth.uid in resource.data.participantIds`
   - Admin-only write: `request.auth.token.admin == true`
2. **Deploy the patched rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```
3. **Notify affected users** if personal data (messages, prayer content, health signals,
   location data) was accessed by unauthorized parties:
   - GDPR Article 33: notify the supervisory authority within 72 hours of confirmed breach.
   - GDPR Article 34 / CCPA: notify affected users if high risk to their rights and freedoms.
   - Draft the notification with legal counsel; do not speculate on scope in communications.
4. **Revoke any leaked session tokens** for affected users if the exposure included
   authentication-adjacent data:
   ```bash
   firebase auth:export users.json  # backup first
   # Then use Admin SDK: auth.revokeRefreshTokens(uid)
   ```

---

## 4. Review

- **Add a deny test** for the specific exposure pattern to `rules-tests/` immediately after
  the patch. The test should assert that the previously-allowed read now returns `PERMISSION_DENIED`.
  Example structure:
  ```javascript
  it('denies cross-user read on private prayer', async () => {
    const db = testEnv.authenticatedContext('other-user').firestore();
    await assertFails(db.doc('prayerRequests/prayer1').get());
  });
  ```
- Run `npm run test:rules` locally to confirm the new deny test passes before merging.
- Schedule a **quarterly Firestore rules review** — audit every collection for owner-only
  vs. public vs. admin access against the intended product behavior.
- Review the THREAT_MODEL.md at `docs/security/THREAT_MODEL.md` and update the affected
  section with the new attack vector and mitigating control.
- Add the specific collection path to the `rules-test` CI job's coverage matrix so it is
  permanently tested on every PR.
