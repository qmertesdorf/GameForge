# Play Console submission — `creature-0001` ("Glade Spirit")

**Status:** owner-gated. The signed release **AAB is built locally** by the repo tooling
(`node tools/package.mjs build creature-0001 --release --aab` →
`games/creature-0001/build/creature-0001-release.aab`, git-ignored). Everything below —
creating a Play developer account, uploading the bundle, completing the policy forms — is a
**human owner step** that requires a Google Play Console account and legal/business decisions
the build pipeline cannot and should not make. This doc is the runbook for that step.

This is the *pipeline* deliverable for the Android-shippable POC: it proves a GameForge title
can be carried all the way to a Play-uploadable artifact. It does **not** advance
`creature-0001` past `styled` — game polish (the owner A/B gates) is a separate axis.

---

## Inputs already produced by the repo

| Play Console field | Repo artifact | Notes |
| --- | --- | --- |
| App bundle (AAB) | `games/creature-0001/build/creature-0001-release.aab` | Signed with the release keystore (below). Git-ignored. Rebuild any time with the `build … --release --aab` command. |
| App icon (512×512) | `games/creature-0001/store/icons/ic_play_store.png` | The Play "hi-res icon". |
| Adaptive launcher icon | `store/icons/ic_adaptive_foreground.png` + `ic_adaptive_background.png` | Baked into the AAB; not uploaded separately. |
| Phone screenshots | `games/creature-0001/store/screenshots/screen-1.png` (720×1280, portrait) | **Play requires ≥ 2 phone screenshots.** Capture at least one more before submitting (a second gameplay moment). The emulator screenshot is unusable (the AVD renders Godot black — see the POC notes), so capture on desktop or a real device. |
| Feature graphic (1024×500) | **MISSING — must be produced.** | Required for the store listing. Generate via the `packager`/`asset` path or author one; the boot splash (`store/splash.png`) is a starting point, not a substitute. |
| Listing copy | Derive from `concept.theme` in `manifests/creature-0001.json` | premise: "a cozy autumn-woodland folktale of a small forest spirit foraging glowing seeds"; tone: "warm, gentle, a touch melancholy". |
| Package name | `com.gameforge.creature_0001` | The sanitized, Android-legal id (hyphen → underscore). **Immutable once published** — chosen deliberately. |

---

## Release keystore custody (read this first — it is the highest-stakes item)

- The release keystore is at `C:\Users\quint\.android\gameforge-release.keystore`
  (RSA 2048, alias `gameforge`, 10000-day validity, self-signed). It is **git-ignored**
  (`*.keystore`) and lives **outside** the repo working tree's tracked files.
- Its password lives in `tools/android-signing.local.json` (git-ignored —
  `*-signing.local.json`). `buildArtifact()` reads that file and sets
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` on the spawned Godot process, so **no
  secret is ever committed**.
- **Back up the keystore file AND its password to a password manager / offline vault now.**
  If you lose either, you can **never publish an update** to this app under the same package
  name — Play permanently ties an app to its signing key. (Play App Signing, below, mitigates
  this but you still must not lose the *upload* key without enrolling first.)
- **Strongly recommended:** enroll in **Play App Signing** at first upload. Google then holds
  the *app signing key*; your keystore becomes only the *upload key*, which Google can reset if
  lost. This is the standard, safer path for new apps.

---

## Owner-gated submission steps

Each step is a human action in the Play Console (https://play.google.com/console). Marked
**[OWNER]** because it needs the developer account, payment, and legal/business judgment.

1. **[OWNER] Create a Play developer account.** One-time US$25 registration; identity
   verification. No GameForge Play account exists yet — this is the first true blocker.

2. **[OWNER] Create the app.** "Create app" → default language, app name "Glade Spirit",
   type **Game**, free. Accept the developer program policies.

3. **[OWNER] Store listing.** Short description + full description (derive from
   `concept.theme`), the 512 hi-res icon (`ic_play_store.png`), the **feature graphic**
   (must be produced — see table), and **≥ 2 phone screenshots** (capture a second).
   Choose a category (Casual / Arcade) and add contact details + a privacy-policy URL
   (required even for a no-data game — host a minimal one).

4. **[OWNER] Content rating questionnaire.** Complete the IARC questionnaire. "Glade Spirit"
   is non-violent/cozy → expect an Everyone/PEGI 3 rating. Honest answers only.

5. **[OWNER] Data safety form.** Declare what data the app collects/shares. This POC build
   collects **no user data** and has no network/ads/analytics → answer accordingly. Re-verify
   against the actual build (no third-party SDKs are wired in).

6. **[OWNER] Target audience & content, ads declaration, government-app/news flags.** For a
   cozy game: not directed at children-only unless chosen; **no ads**; not a government/news
   app. Answer the standard policy gates.

7. **[OWNER] Set up Play App Signing** (see custody note) and an **Internal testing** track
   (fastest, up to 100 testers, no review wait for the first internal release). Prefer internal
   testing over Production for a POC.

8. **[OWNER] Upload the AAB.** Internal testing → Create release → upload
   `games/creature-0001/build/creature-0001-release.aab`. Confirm Play accepts the bundle
   (version code, target SDK, signing). Add release notes. Roll out to the internal track and
   add your own Google account as a tester.

9. **[OWNER] Verify on a device.** Install via the internal-testing opt-in link on a real
   Android phone and confirm the game renders + plays (the one visual confirmation the emulator
   could not give — see the POC emulator caveat).

---

## What the repo guarantees vs. what the owner must do

- **Repo (automated, proven):** a signed, well-formed `.aab` whose package name is Android-legal,
  built reproducibly through the toolchain-guarded `package.mjs` seam, verified by
  `verify-build` (ZIP magic + size). Rebuildable on any toolchain-equipped machine.
- **Owner (manual, gated):** the developer account, all policy/rating/data forms, listing copy
  and graphics decisions, keystore custody, and the actual upload + release. None of these can
  be safely automated.

## To rebuild the AAB later

```powershell
$env:ANDROID_HOME = "C:\Users\quint\AppData\Local\Android\Sdk"
$env:JAVA_HOME    = "C:\Program Files\Microsoft\jdk-21.0.10.7-hotspot"
node tools/package.mjs build creature-0001 --release --aab   # → games/creature-0001/build/creature-0001-release.aab
node tools/package.mjs verify-build creature-0001            # asserts the .aab is a well-formed bundle
```

Requires `tools/android-signing.local.json` present (git-ignored) and the Android build
template installed at `games/creature-0001/android/build/` (Godot: *Project → Install Android
Build Template*, version must match the Godot pin `4.6.3.stable`).
