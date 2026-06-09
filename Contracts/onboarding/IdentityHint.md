# §2.3 — Identity-Hint / Returning-User Contract

Recognition (convenience) is strictly separated from data access (E2EE). The hint survives
app deletion; the keys do not.

## Storage
- **Keychain**, `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
  `kSecAttrSynchronizable = false`, with the app's access group (so the share/widget extension
  can render it — fixes C-07). **NOT UserDefaults** (fixes C-01, D-05, F-06).
- Keychain survives app deletion on iOS — this is the mechanism. The image blob is NOT stored;
  `profilePhotoURL` is refetched on relaunch.

## Hint schema (small, non-sensitive — no raw email, no tokens)
```
uid · displayName · username · profilePhotoURL (remote)
lastAuthMethod (apple|phone|email)
maskedIdentifier  ("•••• 1234" / "j•••@gmail.com")  — display only
rememberedSessionRef?  — §7.1: a reference only, NEVER a live session token
```
Multi-account = an **array** of hints → account switcher.

## Returning-user UX
- Hint(s) exist → open on **welcome_back**: avatar + "Continue as {name}", "Not you? / Add account".
- Initials-avatar fallback if photo refetch fails.
- One canonical surface. `SmartAccountResumeView` is the chosen one (richest); wire it into
  `ContentView`, delete `AutoLoginSplashView` and the `MinimalAuthenticationView` welcome-back card
  as separate readers (fixes C-03, C-04).
- "Continue as {name}" → **reauth_gate** (Face ID, fallback OTP) before unlock — §7.1. No silent
  token restore. "Switch accounts" performs real re-auth (relabel honestly until fast-switch ships — C-06).

## Recognition ≠ access (the inversion fix — C-02)
- **Recognizing** the user = Keychain hint (survives delete).
- **Decrypting** Tier S/C content = E2EE keys, which **do NOT survive reinstall**.
- A reinstalled user is greeted by name, then routed into **E2EE recovery** — never shown a
  "logged in but content silently empty" state.

### Key lifecycle (must be implemented)
- `AMENEncryptionService.wipeAllKeys()` — `SecItemDelete` every identity/SPK/OPK/ratchet tag.
  Called from `performFullSignOutCleanup()` **and** `AccountDeletionService.clearLocalState()`
  (closes the C-02 cross-account leak + orphaned-keys-after-reinstall hole).
- On explicit sign-out: clear the identity hint **and** all legacy `cachedUsername`/`cachedPhotoURL`/
  `currentUser*` keys (fixes F-03). "Switch account" keeps the hint; "Sign out" / "Not you" clears it.

## E2EE recovery model (§7.2 = all layers, in priority order)
1. **Recovery phrase** (default, E2EE-preserving): 12-word phrase generated at first key creation;
   re-derives keys on reinstall. Server never sees keys.
2. **iCloud Keychain escrow**: opt-in backup to the user's iCloud Keychain; auto-restore on reinstall
   under the same Apple ID.
3. **Server-escrowed blob** (last resort): encrypted key blob released after strong re-auth; explicitly
   NOT offered for the most sensitive Tier S content without user consent.

welcome_back → `e2ee_state_resolution`: if keys absent, present recovery options in the above order.
