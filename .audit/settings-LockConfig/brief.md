# settings-LockConfig — brief

**Purpose.** Choose which lock screen runs and how the built-in one looks, and reach
fingerprint unlock.

**Primary action.** Use Hyprlock, because it decides whether half the page does anything.

**Hierarchy.**
1. **Lock Screen** — Use Hyprlock, Launch on startup.
2. **Appearance** — Show locked text, Material shape characters, Lock widget size and
   position. All three style `LockSurface`, which never shows while Hyprlock is on, so
   they are disabled then, and the section's info tooltip says why. They used to sit in
   the first section looking live.
3. **Security** — Unlock keyring, Require password to power off, then Fingerprint as a
   `ConfigNavRow` with its enrolment state as the summary.

**Reference.** Android 16 Settings → Security & privacy → Device unlock: switches first,
biometrics as a row that opens its own page.

**Interaction.** Widget defaults only. The Fingerprint row is carded now, so it ends the
Security run with the outer radius instead of sitting bare under it.

**Edge states.** fprintd missing, fingerprint off, still checking, none enrolled and N
enrolled each have their own summary line (unchanged).

**Cost.** None.

**Delete.** The hand-copied Fingerprint row, which is the shared `ConfigNavRow` now.

**Out of scope.** `FingerprintConfig.qml` (done in `sw-fingerprint`).
