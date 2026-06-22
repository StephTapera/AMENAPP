# §2.2 — Auth State Machine Contract

One continuous flow. **No parallel sign-in vs sign-up trees.** A single owner
(`ContentView` state machine) presents onboarding — `OnboardingFlowView`'s independent
`fullScreenCover` in `AMENAPPApp` is removed (fixes the D-02 P0 crash).

## Nodes & transitions
```
cold_launch
  → check_identity_hint (Keychain, see IdentityHint.md)
      → recognized?  → welcome_back ──tap──▶ reauth_gate
      → none?        → entry (choose method)
  → identifier_capture (phone | email | apple | google)
      → lookup_existing  →  existing? sign-in branch : new? sign-up branch   (SAME screens, branched copy)
  → verify
      → phone:  OTP        (.oneTimeCode autofill, resend cooldown, expiry)
      → email:  magic-link PRIMARY  | password FALLBACK   (§7.3 = both)
      → apple:  assertion  (persist name once; real relay email; getCredentialState on launch)
  → [new user] age_gate (DOB → AgeAssuranceService) ─ ALL methods, incl. social (fixes D-01)
      → under-minimum → blocked
      → teen → teen tier · adult → adult tier
  → [new user] profile_setup (username → photo → faith opt-ins → permissions, in-context)
  → versioned_consent (termsVersion + privacyVersion + acceptedAt persisted)
  → reauth_gate (Face ID / OTP) when restoring a recognized session   (§7.1)
  → e2ee_state_resolution (keys present? : recovery_required → IdentityHint.md §recovery)
  → home
```

## Rules
- **No method forks.** Email and phone each have ONE entry that branches on identifier lookup.
  `emailAlreadyInUse` → inline "Sign in instead"; `userNotFound` → inline "Create account"
  (fixes B-03, D-04). Apple/Google already single-button — keep.
- **Single phone surface.** Consolidate `PhoneVerificationView` + `AmenPhoneAuthView` →
  one component (country picker, `.oneTimeCode`, server-rate-limited via `AuthenticationViewModel`).
  Delete the duplicate view-model (fixes A-05, B-04, B-07).
- **Age gate is universal.** Social sign-in routes first-time users through DOB before
  `needsOnboarding`; `ageVerified` means ID/selfie-verified, never self-declared (fixes D-01, D-03).
- **Returning social users** are routed by `checkOnboardingStatus`, not a forced
  `needsOnboarding = true` (fixes H-08).
- **Single completion flag** `hasCompletedOnboarding` + `schemaVersion`; migrate the 3 legacy
  fields once (fixes D-07).
- **State survives** backgrounding + deep-link resume: persist step **and** in-progress payload,
  or reset to step 0 if payload missing — never land on completion with blank fields (fixes D-08).
- **Username availability** via App Check'd callable `checkUsernameAvailability` (boolean only,
  rate-limited) — no raw client enumeration of `users` (fixes D-09).
- **Versioned consent** gate re-presents acceptance when stored version < current (fixes D-06).
- **Resilience:** `credentialAlreadyInUse` on phone → explicit disambiguation, never silent
  account switch (fixes H-01). Email/password sign-in gets the same `isNetworkAvailable()`
  pre-flight as phone (fixes H-04). `isNetworkAvailable()` races a 3s timeout (fixes H-05).
  Magic-link handler with missing Keychain email prompts re-entry instead of silent return (fixes H-03).
