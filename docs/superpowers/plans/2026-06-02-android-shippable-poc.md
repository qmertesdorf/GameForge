# Android-shippable POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a GameForge Godot POC provably shippable to Android by closing the deferred Android-toolchain gate (debug APK runs on an emulator; signed AAB built locally) and codifying a durable, toolchain-guarded build seam into the repo tooling.

**Architecture:** Mirror the existing `package.mjs` discipline — a *pure* planner (`buildArtifactPlan`) + preset emitters are unit-tested with no SDK; an *impure* `buildArtifact()` spawns headless Godot and is **guarded by an `ANDROID_HOME`/`ANDROID_SDK_ROOT` probe** so `vitest` (currently 163/163) stays green with no SDK present, exactly like the no-GPU/no-ComfyUI posture. An additive optional `store_pass.build_artifact` manifest field records the result. The build is proven end-to-end on `creature-0001` but its status stays `styled` (the `packaged` gate's owner A/B remains an owner gate).

**Tech Stack:** Node.js ESM (`tools/*.mjs`), `vitest`, JSON Schema (Ajv 2020), headless Godot 4.6.3 (`_console.exe`), Android SDK (platform-tools/`adb`, `emulator`, `avdmanager`), JDK 21 (`keytool`), PowerShell helper.

---

## Context the engineer needs (read before starting)

- **Spec:** `docs/superpowers/specs/2026-06-02-android-shippable-poc-design.md`. This plan implements it.
- **The seam file:** `tools/package.mjs`. Study the existing pattern: pure functions throw loudly with a `package:` prefix (`exportPresetCfg`, `parsePresetCfg`, `assertCfgSafe`, `pngSize`, `sizeBudget`); impure functions spawn Godot through `runGodot(args, label)` resolved by `godotBin()` (honors `GODOT_BIN`, else the winget path); the CLI dispatch lives at the bottom (`async function cli`). New code follows these exact conventions.
- **The tests:** `tools/package.test.mjs` (vitest `describe`/`test`, tmp fixtures via `mkdtempSync`, hand-built 24-byte PNG headers). `tools/manifest.test.mjs` validates manifests against the schema via the exported `validate()`.
- **Godot binary** (memory `godot-binary-path`): `C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe`. The `godot` PATH shim does NOT persist across sessions; restore it in PowerShell (see that memory). `godotBin()` already resolves this path, so `buildArtifact()` does not need the shim.
- **Proof target:** `creature-0001`. It already has `asset_pass` + `audio_pass` + full `store_pass` + a committed `games/creature-0001/export_presets.cfg` (preset name `"Glade Spirit"`, package `com.gameforge.creature-0001`). Its `name` field is `"Glade Spirit"` — that string IS the Godot export-preset name the build command takes.
- **Machine state** (verified 2026-06-02): Android SDK at `C:\Users\quint\AppData\Local\Android\Sdk` (platform-tools/`adb`, `emulator`, build-tools 33.0.1, platforms android-31 & android-33-ext4, system-images), Godot 4.6.3 export templates at `%APPDATA%\Godot\export_templates\4.6.3.stable`, Microsoft OpenJDK 21. Gaps filled by Task 9: `ANDROID_HOME` unset, no debug keystore, no AVD, Godot editor settings not pointed at the SDK.
- **CI-safety contract (non-negotiable):** Tasks 1–8 are offline/TDD and MUST keep `vitest` green. Tasks 9–12 run the real toolchain on this machine and are verification-driven (observe/record/adjust), not TDD — Godot's exact AAB/gradle knobs and AVD boot are empirical and flagged as risks in the spec.

### Key design decisions locked here (so later tasks stay consistent)

- **Toolchain guard:** `androidToolchainPresent()` returns `Boolean(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT)`. Env-driven (NOT the hardcoded SDK path) so it is deterministic in tests and on CI. The Task 9 setup helper sets `ANDROID_HOME` for the session, which flips the guard on.
- **Preset/format matrix:** debug build → APK via the prebuilt template (`gradle_build/use_gradle_build=false`), preset name = game `name` (`"Glade Spirit"`), output `build/<id>-debug.apk`. Release build → AAB, which **requires Godot's gradle build enabled** (`gradle_build/use_gradle_build=true` + an installed Android build template) — this is the *standard* AAB path, distinct from authoring custom gradle source for native plugins (which the spec rejected). Preset name = `"<name> Release"`, output `build/<id>-release.aab`.
- **One cfg, two presets:** the committed `export_presets.cfg` carries `[preset.0]` (debug APK) AND `[preset.1]` (release AAB) so a single project root supports both builds.
- **Release signing without committing secrets:** `buildArtifact()` for `buildType==="release"` sets Godot's signing env vars (`GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD`) on the spawned process from a git-ignored local config. The committed cfg contains NO keystore paths or passwords.
- **Two verify layers:** `verify()` stays pure/no-SDK and only validates the **shape** of a recorded `build_artifact` (CI-safe). A new impure `verifyBuildArtifact()` checks the real file (exists + ZIP magic `PK\x03\x04`) only when the toolchain is present, else skips.

---

## File structure

- **Modify** `tools/package.mjs` — add `androidToolchainPresent()`, `exportPresetsFile()`, `buildArtifactPlan()`, `buildArtifact()`, `verifyBuildArtifact()`; extend `exportPresetCfg()` (format/buildType/presetIndex) and `verify()` (build_artifact shape check); extend the CLI (`build`, `verify-build`).
- **Modify** `tools/package.test.mjs` — new `describe` blocks for every pure/guarded function above.
- **Modify** `schema/manifest.schema.json` — additive optional `store_pass.build_artifact`.
- **Modify** `tools/manifest.test.mjs` — schema acceptance/rejection tests for `build_artifact`.
- **Modify** `.gitignore` — ignore `games/*/build/` and the local signing config.
- **Create** `tools/android-setup.ps1` — idempotent one-time machine setup helper.
- **Modify** `.claude/skills/packager/SKILL.md` — add the build step; update the deferred-gates section.
- **Modify** `.claude/skills/validator/SKILL.md` — extend Method 5 with the toolchain-guarded build assertion.
- **Modify** `README.md` — add an "Android export (build/ship)" section.
- **Create** `docs/superpowers/specs/2026-06-02-play-console-submission.md` — Play submission doc (Phase B).
- **Modify (on-machine proof)** `games/creature-0001/export_presets.cfg` (regenerate with both presets) and `manifests/creature-0001.json` (record `build_artifact`).

---

## Task 1: Harden `.gitignore` for build outputs and signing secrets

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\.gitignore`

- [ ] **Step 1: Add the build-dir and signing-config ignores**

`*.apk`, `*.aab`, `*.keystore`, `*.p12` are already ignored by extension. Add the per-game build directory and the local-only signing config. Append after the existing "Secrets — never commit" block:

```gitignore
# Per-game Android build outputs (APK/AAB already ignored by extension; this
# also keeps the build dir itself out of git status)
games/*/build/

# Local-only Android signing config (paths + passwords for the release keystore).
# The release keystore is referenced by buildArtifact() via env vars sourced from
# this file; it MUST NOT be committed.
tools/android-signing.local.json
*-signing.local.json
```

- [ ] **Step 2: Verify the ignores resolve**

Run: `git -C C:/Users/quint/git/mobile-gen check-ignore -v games/creature-0001/build/x.apk tools/android-signing.local.json`
Expected: both paths print a matching `.gitignore` rule (non-empty output, exit 0).

- [ ] **Step 3: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add .gitignore
git -C C:/Users/quint/git/mobile-gen commit -m "chore(android): ignore per-game build dir + local signing config"
```

---

## Task 2: Extend `exportPresetCfg` with format/buildType + add `exportPresetsFile`

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\tools\package.mjs` (the `exportPresetCfg` function, ~lines 76-101)
- Test: `C:\Users\quint\git\mobile-gen\tools\package.test.mjs`

- [ ] **Step 1: Write the failing tests**

Add this `describe` block to `tools/package.test.mjs` (and add `exportPresetsFile` to the import on line 2):

```js
describe("exportPresetCfg format/buildType variants", () => {
  test("debug+apk preset names the prebuilt-template path (gradle off)", () => {
    const parsed = parsePresetCfg(exportPresetCfg({ id: "creature-0001", name: "Glade Spirit", format: "apk", buildType: "debug" }));
    expect(parsed["preset.0"].platform).toBe("Android");
    expect(parsed["preset.0"].name).toBe("Glade Spirit");
    expect(parsed["preset.0"].export_path).toBe("build/creature-0001-debug.apk");
    expect(parsed["preset.0.options"]["gradle_build/use_gradle_build"]).toBe(false);
  });

  test("release+aab preset turns gradle build on and targets a .aab path", () => {
    const parsed = parsePresetCfg(exportPresetCfg({ id: "creature-0001", name: "Glade Spirit", format: "aab", buildType: "release" }));
    expect(parsed["preset.0"].export_path).toBe("build/creature-0001-release.aab");
    expect(parsed["preset.0.options"]["gradle_build/use_gradle_build"]).toBe(true);
  });

  test("presetIndex emits a [preset.N] section with that index", () => {
    const parsed = parsePresetCfg(exportPresetCfg({ id: "x-0001", name: "X", presetIndex: 1 }));
    expect(parsed["preset.1"]).toBeDefined();
    expect(parsed["preset.1"].platform).toBe("Android");
    expect(parsed["preset.1.options"]).toBeDefined();
  });

  test("throws on an unknown format or buildType", () => {
    expect(() => exportPresetCfg({ id: "x", name: "X", format: "ipa" })).toThrow(/format/);
    expect(() => exportPresetCfg({ id: "x", name: "X", buildType: "beta" })).toThrow(/buildType/);
  });

  test("defaults are unchanged (debug apk, preset.0) — back-compat", () => {
    const parsed = parsePresetCfg(exportPresetCfg({ id: "creature-0001", name: "Glade Spirit" }));
    expect(parsed["preset.0"].export_path).toBe("build/creature-0001-debug.apk");
    expect(parsed["preset.0.options"]["package/unique_name"]).toBe("com.gameforge.creature-0001");
  });
});

describe("exportPresetsFile", () => {
  test("emits BOTH a debug-APK preset.0 and a release-AAB preset.1", () => {
    const parsed = parsePresetCfg(exportPresetsFile({ id: "creature-0001", name: "Glade Spirit" }));
    expect(parsed["preset.0"].name).toBe("Glade Spirit");
    expect(parsed["preset.0"].export_path).toBe("build/creature-0001-debug.apk");
    expect(parsed["preset.0.options"]["gradle_build/use_gradle_build"]).toBe(false);
    expect(parsed["preset.1"].name).toBe("Glade Spirit Release");
    expect(parsed["preset.1"].export_path).toBe("build/creature-0001-release.aab");
    expect(parsed["preset.1.options"]["gradle_build/use_gradle_build"]).toBe(true);
    expect(parsed["preset.1.options"]["package/unique_name"]).toBe("com.gameforge.creature-0001");
  });

  test("both presets share the package unique_name", () => {
    const parsed = parsePresetCfg(exportPresetsFile({ id: "x-0001", name: "X" }));
    expect(parsed["preset.0.options"]["package/unique_name"]).toBe("com.gameforge.x-0001");
    expect(parsed["preset.1.options"]["package/unique_name"]).toBe("com.gameforge.x-0001");
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- package.test.mjs`
Expected: FAIL — `exportPresetsFile is not a function`, plus the new `exportPresetCfg` assertions fail (no `gradle_build/use_gradle_build` key yet).

- [ ] **Step 3: Implement the extended `exportPresetCfg` and new `exportPresetsFile`**

Replace the existing `exportPresetCfg` function (`tools/package.mjs` ~lines 76-101) with:

```js
// Generate a minimal-but-valid Godot Android export preset block. Pure.
// format: "apk" (prebuilt template, gradle off) | "aab" (requires gradle build on).
// buildType: "debug" | "release". presetIndex picks the [preset.N] section so a
// single cfg can carry both a debug-APK and a release-AAB preset.
export function exportPresetCfg({ id, name, packageName, exportPath, format = "apk", buildType = "debug", presetIndex = 0 } = {}) {
  if (!id || !name) {
    throw new Error("package: exportPresetCfg requires both { id, name }");
  }
  if (format !== "apk" && format !== "aab") {
    throw new Error(`package: exportPresetCfg format must be "apk" or "aab", got ${JSON.stringify(format)}`);
  }
  if (buildType !== "debug" && buildType !== "release") {
    throw new Error(`package: exportPresetCfg buildType must be "debug" or "release", got ${JSON.stringify(buildType)}`);
  }
  assertCfgSafe(name, "exportPresetCfg name");
  const unique = assertCfgSafe(packageName || `com.gameforge.${id}`, "exportPresetCfg packageName");
  const out = assertCfgSafe(exportPath || `build/${id}-${buildType}.${format}`, "exportPresetCfg exportPath");
  const useGradle = format === "aab"; // AAB output requires Godot's gradle build enabled
  const p = `preset.${presetIndex}`;
  return [
    `[${p}]`,
    "",
    `name="${name}"`,
    `platform="Android"`,
    "runnable=true",
    `export_filter="all_resources"`,
    `include_filter=""`,
    `exclude_filter=""`,
    `export_path="${out}"`,
    "",
    `[${p}.options]`,
    "",
    `gradle_build/use_gradle_build=${useGradle ? "true" : "false"}`,
    `package/unique_name="${unique}"`,
    `package/name="${name}"`,
    ""
  ].join("\n");
}

// Emit a full export_presets.cfg carrying BOTH a debug-APK preset (preset.0,
// named after the game) and a release-AAB preset (preset.1, "<name> Release").
// One file, two presets, so a single project root builds either artifact. Pure.
export function exportPresetsFile({ id, name, packageName } = {}) {
  if (!id || !name) {
    throw new Error("package: exportPresetsFile requires both { id, name }");
  }
  const debug = exportPresetCfg({ id, name, packageName, format: "apk", buildType: "debug", presetIndex: 0 });
  const release = exportPresetCfg({ id, name: `${name} Release`, packageName, format: "aab", buildType: "release", presetIndex: 1 });
  return `${debug}\n${release}`;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- package.test.mjs`
Expected: PASS (all `exportPresetCfg` + `exportPresetsFile` tests green; the pre-existing `exportPresetCfg + parsePresetCfg` block still green since it checks individual keys, not a full object equality).

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add tools/package.mjs tools/package.test.mjs
git -C C:/Users/quint/git/mobile-gen commit -m "feat(package): export-preset format/buildType variants + two-preset emitter"
```

---

## Task 3: Pure `buildArtifactPlan` + `androidToolchainPresent`

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\tools\package.mjs`
- Test: `C:\Users\quint\git\mobile-gen\tools\package.test.mjs`

- [ ] **Step 1: Write the failing tests**

Add to `tools/package.test.mjs` (import `buildArtifactPlan`, `androidToolchainPresent` on line 2; add `join` is already imported). Use `join` so path expectations match Windows separators:

```js
describe("buildArtifactPlan (pure)", () => {
  test("debug+apk → --export-debug, the game preset name, a build/<id>-debug.apk out path", () => {
    const plan = buildArtifactPlan({ id: "creature-0001", name: "Glade Spirit", gamesDir: "/g" });
    expect(plan.format).toBe("apk");
    expect(plan.build_type).toBe("debug");
    expect(plan.preset).toBe("Glade Spirit");
    expect(plan.package).toBe("com.gameforge.creature-0001");
    expect(plan.outPath).toBe(join("/g", "creature-0001", "build", "creature-0001-debug.apk"));
    expect(plan.args).toEqual([
      "--headless", "--path", join("/g", "creature-0001"),
      "--export-debug", "Glade Spirit", plan.outPath
    ]);
  });

  test("release+aab → --export-release, the '<name> Release' preset, a .aab out path", () => {
    const plan = buildArtifactPlan({ id: "creature-0001", name: "Glade Spirit", format: "aab", buildType: "release", gamesDir: "/g" });
    expect(plan.preset).toBe("Glade Spirit Release");
    expect(plan.outPath).toBe(join("/g", "creature-0001", "build", "creature-0001-release.aab"));
    expect(plan.args[3]).toBe("--export-release");
    expect(plan.args[4]).toBe("Glade Spirit Release");
  });

  test("honors an explicit packageName", () => {
    expect(buildArtifactPlan({ id: "x", name: "X", packageName: "com.acme.x", gamesDir: "/g" }).package).toBe("com.acme.x");
  });

  test("throws without id or name", () => {
    expect(() => buildArtifactPlan({ id: "x", gamesDir: "/g" })).toThrow(/name|id/);
    expect(() => buildArtifactPlan({ name: "X", gamesDir: "/g" })).toThrow(/id|name/);
  });

  test("throws on an unknown format or buildType", () => {
    expect(() => buildArtifactPlan({ id: "x", name: "X", format: "ipa", gamesDir: "/g" })).toThrow(/format/);
    expect(() => buildArtifactPlan({ id: "x", name: "X", buildType: "beta", gamesDir: "/g" })).toThrow(/buildType/);
  });
});

describe("androidToolchainPresent", () => {
  test("true only when ANDROID_HOME or ANDROID_SDK_ROOT is set", () => {
    const save = { home: process.env.ANDROID_HOME, root: process.env.ANDROID_SDK_ROOT };
    try {
      delete process.env.ANDROID_HOME; delete process.env.ANDROID_SDK_ROOT;
      expect(androidToolchainPresent()).toBe(false);
      process.env.ANDROID_HOME = "C:/fake/sdk";
      expect(androidToolchainPresent()).toBe(true);
      delete process.env.ANDROID_HOME; process.env.ANDROID_SDK_ROOT = "C:/fake/sdk";
      expect(androidToolchainPresent()).toBe(true);
    } finally {
      if (save.home === undefined) delete process.env.ANDROID_HOME; else process.env.ANDROID_HOME = save.home;
      if (save.root === undefined) delete process.env.ANDROID_SDK_ROOT; else process.env.ANDROID_SDK_ROOT = save.root;
    }
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- package.test.mjs`
Expected: FAIL — `buildArtifactPlan is not a function`, `androidToolchainPresent is not a function`.

- [ ] **Step 3: Implement both functions**

Add to `tools/package.mjs` after `exportPresetsFile` (before the `godotBin` helper section):

```js
// Is the Android toolchain available? Env-driven (NOT the hardcoded SDK path) so
// it is deterministic in tests and on CI. The android-setup helper exports
// ANDROID_HOME for the session, flipping this on. Mirrors the no-GPU/no-ComfyUI
// guard posture — buildArtifact() and verifyBuildArtifact() skip when this is false.
export function androidToolchainPresent() {
  return Boolean(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT);
}

// Pure plan for a headless Godot Android export. No SDK touched — fully unit-testable.
// debug → APK via preset "<name>"; release → AAB via preset "<name> Release"
// (the two presets exportPresetsFile() writes). Returns the spawn args + out path
// so buildArtifact() only has to prepend godotBin() and run it.
export function buildArtifactPlan({ id, name, packageName, format = "apk", buildType = "debug", gamesDir = GAMES_DIR } = {}) {
  if (!id || !name) {
    throw new Error("package: buildArtifactPlan requires both { id, name }");
  }
  if (format !== "apk" && format !== "aab") {
    throw new Error(`package: buildArtifactPlan format must be "apk" or "aab", got ${JSON.stringify(format)}`);
  }
  if (buildType !== "debug" && buildType !== "release") {
    throw new Error(`package: buildArtifactPlan buildType must be "debug" or "release", got ${JSON.stringify(buildType)}`);
  }
  const preset = buildType === "debug" ? name : `${name} Release`;
  const flag = buildType === "debug" ? "--export-debug" : "--export-release";
  const projectDir = join(gamesDir, id);
  const outPath = join(projectDir, "build", `${id}-${buildType}.${format}`);
  return {
    args: ["--headless", "--path", projectDir, flag, preset, outPath],
    outPath,
    package: packageName || `com.gameforge.${id}`,
    preset,
    format,
    build_type: buildType
  };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- package.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add tools/package.mjs tools/package.test.mjs
git -C C:/Users/quint/git/mobile-gen commit -m "feat(package): pure buildArtifactPlan + androidToolchainPresent guard"
```

---

## Task 4: Impure `buildArtifact` (toolchain-guarded spawn) + `verifyBuildArtifact`

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\tools\package.mjs`
- Test: `C:\Users\quint\git\mobile-gen\tools\package.test.mjs`

The spawn path needs a real SDK, so tests only cover the **skip** path (toolchain absent) and the **record-shape** path of `verifyBuildArtifact` against a hand-written ZIP-magic file. Both functions accept an injectable `present` so tests never depend on machine env.

- [ ] **Step 1: Write the failing tests**

Add to `tools/package.test.mjs` (import `buildArtifact`, `verifyBuildArtifact`):

```js
describe("buildArtifact (guarded)", () => {
  test("skips cleanly when the toolchain is absent (no spawn)", () => {
    const r = buildArtifact("creature-0001", { present: false });
    expect(r.skipped).toBe(true);
    expect(r.reason).toMatch(/ANDROID_HOME|toolchain/i);
  });
});

describe("verifyBuildArtifact (guarded)", () => {
  test("skips when the toolchain is absent", () => {
    expect(verifyBuildArtifact("creature-0001", { present: false }).skipped).toBe(true);
  });

  test("passes for a present file whose first bytes are the ZIP magic PK\\x03\\x04", () => {
    const dir = mkdtempSync(join(tmpdir(), "gf-apk-"));
    try {
      const buildDir = join(dir, "creature-0001", "build");
      mkdirSync(buildDir, { recursive: true });
      const apk = join(buildDir, "creature-0001-debug.apk");
      // ZIP local-file-header magic + padding to clear the size floor.
      writeFileSync(apk, Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.alloc(2048)]));
      const r = verifyBuildArtifact("creature-0001", {
        gamesDir: dir, present: true,
        build_artifact: { format: "apk", build_type: "debug", path: "build/creature-0001-debug.apk", bytes: 2052, package: "com.gameforge.creature-0001" }
      });
      expect(r.skipped).toBeUndefined();
      expect(r.ok).toBe(true);
      expect(r.signature_ok).toBe(true);
      expect(r.issues).toEqual([]);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  test("flags a missing file and a bad signature", () => {
    const dir = mkdtempSync(join(tmpdir(), "gf-apk-"));
    try {
      const buildDir = join(dir, "creature-0001", "build");
      mkdirSync(buildDir, { recursive: true });
      writeFileSync(join(buildDir, "creature-0001-debug.apk"), Buffer.from("NOT A ZIP....."));
      const bad = verifyBuildArtifact("creature-0001", {
        gamesDir: dir, present: true,
        build_artifact: { format: "apk", build_type: "debug", path: "build/creature-0001-debug.apk" }
      });
      expect(bad.ok).toBe(false);
      expect(bad.issues.join(" ")).toMatch(/signature|not a zip/i);

      const missing = verifyBuildArtifact("creature-0001", {
        gamesDir: dir, present: true,
        build_artifact: { format: "aab", build_type: "release", path: "build/creature-0001-release.aab" }
      });
      expect(missing.ok).toBe(false);
      expect(missing.issues.join(" ")).toMatch(/absent|not found/i);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- package.test.mjs`
Expected: FAIL — `buildArtifact is not a function`, `verifyBuildArtifact is not a function`.

- [ ] **Step 3: Implement both functions**

Add to `tools/package.mjs` after the `generateSplash`/`budgetReport` impure section (near `verify`). `buildArtifact` reads the manifest for `name`, plans via `buildArtifactPlan`, sets release signing env from the local config, and spawns Godot through the existing `runGodot` helper:

```js
// Source the release-signing env vars Godot reads (GODOT_ANDROID_KEYSTORE_RELEASE_*)
// from a git-ignored local config so no secret is ever committed. Returns the env
// overlay for the spawned process (empty for debug builds). Throws if a release
// build is requested without the config.
function releaseSigningEnv(buildType) {
  if (buildType !== "release") return {};
  const cfgPath = join(REPO_ROOT, "tools", "android-signing.local.json");
  if (!existsSync(cfgPath)) {
    throw new Error(`package: a release build needs signing config at ${cfgPath} (git-ignored). Create it with { "keystore_path", "keystore_user", "keystore_password" }.`);
  }
  const c = JSON.parse(readFileSync(cfgPath, "utf8"));
  for (const k of ["keystore_path", "keystore_user", "keystore_password"]) {
    if (!c[k]) throw new Error(`package: android-signing.local.json is missing "${k}"`);
  }
  return {
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: c.keystore_path,
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: c.keystore_user,
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: c.keystore_password
  };
}

// Build the Android artifact by spawning headless Godot. Toolchain-guarded: returns
// { skipped, reason } when ANDROID_HOME/ANDROID_SDK_ROOT is unset (CI / no-SDK),
// so this is never reached in vitest. On success returns the build_artifact record.
export function buildArtifact(id, { gamesDir = GAMES_DIR, format = "apk", buildType = "debug", present = androidToolchainPresent() } = {}) {
  if (!present) {
    return { skipped: true, reason: "Android toolchain absent (ANDROID_HOME/ANDROID_SDK_ROOT unset) — skipping real export, same posture as no-GPU/no-ComfyUI." };
  }
  const m = readManifest(id);
  if (!m?.name) throw new Error(`package: buildArtifact needs a name in manifests/${id}.json`);
  const plan = buildArtifactPlan({ id, name: m.name, format, buildType, gamesDir });
  mkdirSync(join(gamesDir, id, "build"), { recursive: true });
  const env = { ...process.env, ...releaseSigningEnv(buildType) };
  try {
    execFileSync(godotBin(), plan.args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env });
  } catch (e) {
    const out = `${e.stdout ?? ""}${e.stderr ?? ""}`;
    throw new Error(`package: Godot ${buildType} ${format} export failed: ${out || e.message}`);
  }
  if (!existsSync(plan.outPath)) {
    throw new Error(`package: Godot reported success but no artifact at ${plan.outPath}`);
  }
  const bytes = statSync(plan.outPath).size;
  return {
    format: plan.format,
    build_type: plan.build_type,
    path: plan.outPath.slice(join(gamesDir, id).length + 1).replace(/\\/g, "/"),
    bytes,
    package: plan.package
  };
}

// Assert a recorded build_artifact's real file exists and is a well-formed ZIP
// (APK and AAB are both ZIP containers — first 4 bytes are PK\x03\x04). Guarded:
// skips when the toolchain is absent (binaries are git-ignored, not on CI).
export function verifyBuildArtifact(id, { gamesDir = GAMES_DIR, build_artifact, present = androidToolchainPresent() } = {}) {
  if (!present) return { skipped: true, reason: "toolchain absent — build artifact not checked" };
  const ba = build_artifact || readManifest(id)?.store_pass?.build_artifact;
  const issues = [];
  if (!ba) return { ok: false, issues: ["no build_artifact recorded in store_pass"] };
  const abs = join(gamesDir, id, ba.path);
  if (!existsSync(abs)) {
    issues.push(`build artifact absent: ${ba.path} (not found at ${abs})`);
    return { ok: false, issues, signature_ok: false };
  }
  const bytes = statSync(abs).size;
  if (bytes < 1024) issues.push(`build artifact suspiciously small: ${bytes} bytes`);
  const head = readFileSync(abs).subarray(0, 4);
  const signature_ok = head.equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]));
  if (!signature_ok) issues.push(`build artifact is not a ZIP (bad signature, not an APK/AAB): ${ba.path}`);
  return { ok: issues.length === 0, issues, signature_ok, bytes };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- package.test.mjs`
Expected: PASS (skip paths + the ZIP-magic checks). No Godot is spawned because the tests pass `present: false`/`present: true` explicitly.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add tools/package.mjs tools/package.test.mjs
git -C C:/Users/quint/git/mobile-gen commit -m "feat(package): guarded buildArtifact spawn + verifyBuildArtifact ZIP check"
```

---

## Task 5: Add `store_pass.build_artifact` to the schema

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\schema\manifest.schema.json` (the `store_pass.properties` object, after `export_preset`, ~line 285)
- Test: `C:\Users\quint\git\mobile-gen\tools\manifest.test.mjs`

- [ ] **Step 1: Write the failing tests**

Add to the `describe("validate", ...)` block in `tools/manifest.test.mjs`:

```js
test("accepts a store_pass carrying a build_artifact record", () => {
  const m = validManifest();
  m.store_pass = {
    icon_master: "art/spirit.png",
    build_artifact: { format: "apk", build_type: "debug", path: "build/creature-0001-debug.apk", bytes: 12345678, package: "com.gameforge.creature-0001" }
  };
  expect(validate(m)).toEqual({ valid: true, errors: [] });
});

test("rejects a build_artifact with an unknown format enum", () => {
  const m = validManifest();
  m.store_pass = { build_artifact: { format: "ipa", build_type: "debug" } };
  expect(validate(m).valid).toBe(false);
});

test("rejects an unknown key inside build_artifact", () => {
  const m = validManifest();
  m.store_pass = { build_artifact: { format: "aab", build_type: "release", bogus: true } };
  expect(validate(m).valid).toBe(false);
});

test("build_artifact is optional (no regression for pre-build store_pass)", () => {
  const m = validManifest();
  m.store_pass = { icon_master: "art/spirit.png" };
  expect(validate(m)).toEqual({ valid: true, errors: [] });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- manifest.test.mjs`
Expected: FAIL — the "accepts a build_artifact" / "build_artifact is optional" tests fail because `additionalProperties: false` on `store_pass` currently rejects the unknown `build_artifact` key.

- [ ] **Step 3: Add the schema field**

In `schema/manifest.schema.json`, inside `store_pass.properties`, after the `export_preset` block and before `"icon_master"` (~line 285), insert:

```json
        "build_artifact": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "format": { "enum": ["apk", "aab"] },
            "build_type": { "enum": ["debug", "release"] },
            "path": { "type": "string" },
            "bytes": { "type": "number" },
            "package": { "type": "string" }
          }
        },
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- manifest.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add schema/manifest.schema.json tools/manifest.test.mjs
git -C C:/Users/quint/git/mobile-gen commit -m "feat(schema): additive optional store_pass.build_artifact"
```

---

## Task 6: Wire `build_artifact` into `verify()` + extend the CLI

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\tools\package.mjs` (the `verify` function ~lines 293-350 and the `cli` dispatch ~lines 354-382)
- Test: `C:\Users\quint\git\mobile-gen\tools\package.test.mjs`

- [ ] **Step 1: Write the failing tests**

In the existing `describe("verify (packaging gate)", ...)` block of `tools/package.test.mjs`, add:

```js
test("a well-formed build_artifact record passes verify() with no new issue", () => {
  withFixture((dir, sp) => {
    sp.build_artifact = { format: "apk", build_type: "debug", path: "build/fix-0001-debug.apk", bytes: 1000, package: "com.gameforge.fix-0001" };
    const r = verify("fix-0001", { gamesDir: dir, manifest: manifestFor(sp) });
    expect(r.file_checks_pass).toBe(true);
  });
});

test("a malformed build_artifact record (bad format) is flagged by verify()", () => {
  withFixture((dir, sp) => {
    sp.build_artifact = { format: "exe", build_type: "debug", path: "build/x" };
    const r = verify("fix-0001", { gamesDir: dir, manifest: manifestFor(sp) });
    expect(r.issues.join(" ")).toMatch(/build_artifact.*format|format/);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- package.test.mjs`
Expected: FAIL — the malformed-record test fails (verify() does not yet inspect `build_artifact`).

- [ ] **Step 3: Add the shape check to `verify()`**

In `tools/package.mjs`, inside `verify()`, after the section-5 `bothPasses` line and before `return`, insert a section that validates the **record shape only** (no file touch — keeps verify() pure/CI-safe; the real file is checked by `verifyBuildArtifact`):

```js
  // 6. build artifact record (shape only — the real file is git-ignored and
  // checked by verifyBuildArtifact() when the toolchain is present).
  if (sp.build_artifact) {
    const ba = sp.build_artifact;
    if (ba.format !== "apk" && ba.format !== "aab") issues.push(`build_artifact.format is "${ba.format}", expected apk|aab`);
    if (ba.build_type !== "debug" && ba.build_type !== "release") issues.push(`build_artifact.build_type is "${ba.build_type}", expected debug|release`);
    if (typeof ba.path !== "string" || !ba.path) issues.push(`build_artifact.path is missing`);
  }
```

(Recompute nothing else — `file_checks_pass` already derives from `issues.length === 0`.)

- [ ] **Step 4: Extend the CLI dispatch**

In the `cli` function's `switch (cmd)`, add two cases (after the `preset` case):

```js
    case "build": {
      const m = readManifest(id);
      const format = rest.includes("--aab") ? "aab" : "apk";
      const buildType = rest.includes("--release") ? "release" : "debug";
      const r = buildArtifact(id, { format, buildType, name: m.name });
      console.log(JSON.stringify(r, null, 2));
      if (r.skipped) process.exit(3); // distinct code: "toolchain absent", not a failure
      return;
    }
    case "verify-build": {
      const r = verifyBuildArtifact(id);
      console.log(JSON.stringify(r, null, 2));
      if (r.skipped) return;
      if (!r.ok) process.exit(1);
      return;
    }
```

Update the `USAGE` constant string to include the new verbs:

```js
const USAGE = "usage: node tools/package.mjs <icons|atlas|screenshot|splash|budget|preset|build|verify|verify-build|--check> <id> ...";
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `npm test -- package.test.mjs`
Expected: PASS.

- [ ] **Step 6: Verify the full suite still passes**

Run: `npm test`
Expected: PASS — all suites green, count ≥ 163 plus the new specs.

- [ ] **Step 7: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add tools/package.mjs tools/package.test.mjs
git -C C:/Users/quint/git/mobile-gen commit -m "feat(package): verify() build_artifact shape check + build/verify-build CLI"
```

---

## Task 7: Codify the build step into the packager + validator skills

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\.claude\skills\packager\SKILL.md`
- Modify: `C:\Users\quint\git\mobile-gen\.claude\skills\validator\SKILL.md`

No automated test — this is skill prose. Verify with the `skills.test.mjs` suite (which checks skill frontmatter/structure) at the end.

- [ ] **Step 1: Add the build step to the packager flow**

In `.claude/skills/packager/SKILL.md`, in the "## Flow" section, after the `preset` line in the code block (~line 51), add:

```
node tools/package.mjs build <id>            # build the debug APK via headless Godot (toolchain-guarded: skips with exit 3 if ANDROID_HOME unset)
node tools/package.mjs build <id> --release --aab   # build the signed release AAB (needs tools/android-signing.local.json)
```

Then in the `store_pass` merge example (~line 57), add `\"build_artifact\": { … }` to the recorded object, and add a sentence after it:

```
Record `store_pass.build_artifact` from the `build` command's JSON (format, build_type, path, bytes, package). If the build skipped (exit 3, no Android toolchain), omit `build_artifact` and note the deferred toolchain gate — do not fabricate a record.
```

- [ ] **Step 2: Update the packager "Deferred" section**

In `.claude/skills/packager/SKILL.md`, replace the first bullet of "## Deferred (named gates — track, do not fake)" (the "Actual APK build" bullet, ~line 73) with:

```
- **APK/AAB build is now in scope** (no longer deferred): `node tools/package.mjs build <id>` shells out to headless Godot, guarded by `ANDROID_HOME`. On a toolchain-equipped machine it produces a debug APK (and `--release --aab` a signed AAB) and records `store_pass.build_artifact`. Without the SDK it skips cleanly (exit 3) — the same no-GPU/no-ComfyUI posture. The one-time machine setup (debug keystore, Godot editor SDK path, AVD) is documented in `README.md` → "Android export" + `tools/android-setup.ps1`.
- **Real store submission** (Play developer account, release-keystore custody, listing copy, content rating, legal) → owner-gated. The signed AAB is built locally now; uploading it is the owner step documented in `docs/superpowers/specs/2026-06-02-play-console-submission.md`.
```

- [ ] **Step 3: Add the toolchain-guarded build assertion to validator Method 5**

In `.claude/skills/validator/SKILL.md`, in "## Method 5 — Packaging gate", after item 6 ("Regression guard") and before item 7 ("Cross-modal cohesion A/B"), insert:

```
6b. **Build artifact (toolchain-guarded; CI-skipped).** When `store_pass.build_artifact` is recorded, `package.mjs verify` already checks its **shape** (format/build_type/path) headlessly with no SDK. When the **Android toolchain is present** (`ANDROID_HOME`/`ANDROID_SDK_ROOT` set), additionally run `node tools/package.mjs verify-build <id>` to assert the real file exists and is a well-formed APK/AAB (ZIP magic `PK\x03\x04`, non-trivial size). When the toolchain is **absent**, this command skips cleanly (prints `skipped:true`, exit 0) — the build artifact is git-ignored and never present on a clean checkout, so CI is unaffected. A recorded-but-broken artifact is a `packager`/`package.mjs` finding.
```

- [ ] **Step 4: Note the status ceremony for this milestone**

In `.claude/skills/validator/SKILL.md`, in Method 5's closing paragraph (the one starting "On failure, record the specific issue…", ~line 123), append:

```
 Note (Android-shippable POC, 2026-06-02): proving the **build toolchain** on a game — recording `build_artifact` and passing `verify-build` — does **not** by itself advance status to `packaged`. The `packaged` gate still requires both owner A/B confirmations (`styled` visual + `scored` audio) and the item-7 cross-modal cohesion A/B. A game whose build is proven but whose A/Bs are still pending (e.g. creature-0001) stays at its current status. The build seam proves shippability of the *pipeline*, not polish of the *game*.
```

- [ ] **Step 5: Verify skill structure still parses**

Run: `npm test -- skills.test.mjs`
Expected: PASS (frontmatter/structure checks unaffected).

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add .claude/skills/packager/SKILL.md .claude/skills/validator/SKILL.md
git -C C:/Users/quint/git/mobile-gen commit -m "docs(skills): codify Android build step in packager + validator Method 5 (toolchain-guarded)"
```

---

## Task 8: README "Android export" section + setup helper

**Files:**
- Modify: `C:\Users\quint\git\mobile-gen\README.md` (insert a new section after "## Audio asset tool (M1.6)", before "## Tests")
- Create: `C:\Users\quint\git\mobile-gen\tools\android-setup.ps1`

- [ ] **Step 1: Write the setup helper**

Create `tools/android-setup.ps1` — idempotent machine setup. It generates the debug keystore, exports `ANDROID_HOME` for the session, and prints the editor-settings keys the engineer must confirm. It does NOT mutate Godot editor settings blindly (that file is machine-global) — it prints exactly what to set.

```powershell
# tools/android-setup.ps1 — one-time Android export setup for this machine.
# Idempotent: safe to re-run. Sources nothing secret into git.
$ErrorActionPreference = "Stop"

$Sdk = "C:\Users\quint\AppData\Local\Android\Sdk"
if (-not (Test-Path $Sdk)) { throw "Android SDK not found at $Sdk — install it first." }

# 1. Session env (the package.mjs toolchain guard keys off these).
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk
$env:Path += ";$Sdk\platform-tools;$Sdk\emulator;$Sdk\cmdline-tools\latest\bin"
Write-Host "ANDROID_HOME set to $Sdk (this session)."

# 2. Debug keystore (Godot's expected androiddebugkey / android / android).
$Keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
if (-not (Test-Path $Keystore)) {
  New-Item -ItemType Directory -Force (Split-Path $Keystore) | Out-Null
  & keytool -genkeypair -v -keystore $Keystore -storepass android -keypass android `
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 `
    -dname "CN=Android Debug,O=Android,C=US"
  Write-Host "Generated debug keystore at $Keystore."
} else {
  Write-Host "Debug keystore already present at $Keystore."
}

# 3. Editor settings the engineer must confirm in Godot's editor_settings-4.tres
#    (%APPDATA%\Godot\editor_settings-4.tres) for headless CLI export to find the SDK + keystore:
Write-Host ""
Write-Host "Confirm these keys in %APPDATA%\Godot\editor_settings-4.tres (open Godot once, Editor > Editor Settings > Export > Android):"
Write-Host "  export/android/android_sdk_path = `"$Sdk`""
Write-Host "  export/android/debug_keystore   = `"$Keystore`""
Write-Host "  export/android/debug_keystore_user = `"androiddebugkey`""
Write-Host "  export/android/debug_keystore_pass = `"android`""
Write-Host ""
Write-Host "For a release AAB also: install the Android build template (Godot: Project > Install Android Build Template)"
Write-Host "and create tools/android-signing.local.json (git-ignored) with { keystore_path, keystore_user, keystore_password }."
```

- [ ] **Step 2: Add the README section**

In `README.md`, after line 71 (the M1.6 `See …feasibility-notes.md` line) and before "## Tests", insert:

````markdown
## Android export (build/ship)

`tools/package.mjs` carries a **toolchain-guarded** Godot Android export seam — the same pure-planner + impure-spawn + no-SDK-skip pattern as the raster/audio tools. The pure `buildArtifactPlan` and the preset emitters are unit-tested with no SDK; `buildArtifact()` spawns headless Godot and **skips cleanly when `ANDROID_HOME`/`ANDROID_SDK_ROOT` is unset** (CI posture).

```
node tools/package.mjs build <id>                  # debug APK  → games/<id>/build/<id>-debug.apk
node tools/package.mjs build <id> --release --aab  # signed AAB → games/<id>/build/<id>-release.aab
node tools/package.mjs verify-build <id>           # assert the built file is a well-formed APK/AAB (skips w/o SDK)
```

The `packager` skill runs `build` after generating store assets and records `store_pass.build_artifact` (format, build_type, path, bytes, package). `validator` Method 5 runs `verify-build` when the toolchain is present. Build outputs and keystores are **git-ignored** (`games/*/build/`, `*.apk`, `*.aab`, `*.keystore`).

**One-time machine setup** (run `tools/android-setup.ps1`, then confirm the printed Godot editor-settings keys):
1. **Android SDK** at `C:\Users\quint\AppData\Local\Android\Sdk`; export `ANDROID_HOME`/`ANDROID_SDK_ROOT` and add `platform-tools`/`emulator` to PATH.
2. **Debug keystore** at `~/.android/debug.keystore` via `keytool` (alias `androiddebugkey`, store/key pass `android`).
3. **Godot editor settings** (`%APPDATA%\Godot\editor_settings-4.tres`): set `export/android/android_sdk_path` + the debug-keystore keys — headless CLI export reads these.
4. **AVD** via `avdmanager` (verify a system-image boots in `emulator` before relying on it).

**Release signing (Phase B):** the committed `export_presets.cfg` carries NO secrets. `buildArtifact()` for a release build sets Godot's `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD` env vars from `tools/android-signing.local.json` (git-ignored). AAB output requires Godot's **gradle build** enabled (`gradle_build/use_gradle_build=true` in the release preset) and an installed Android build template — this is the standard AAB path, not custom native gradle source. Play Console submission steps live in `docs/superpowers/specs/2026-06-02-play-console-submission.md`.
````

- [ ] **Step 3: Verify nothing broke**

Run: `npm test`
Expected: PASS — docs/helper changes don't touch tested code; count still ≥ 163 + new specs.

- [ ] **Step 4: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add README.md tools/android-setup.ps1
git -C C:/Users/quint/git/mobile-gen commit -m "docs(android): README export section + idempotent android-setup.ps1 helper"
```

---

## Task 9: One-time machine setup (debug keystore, Godot SDK path, AVD)

> **Verification-driven, not TDD.** This touches the real machine. Observe and record actual output; do not assume PASS.

**Files:** none committed (machine config). Produces `~/.android/debug.keystore`, edits `%APPDATA%\Godot\editor_settings-4.tres`, creates an AVD.

- [ ] **Step 1: Run the setup helper**

Run (PowerShell): `& C:\Users\quint\git\mobile-gen\tools\android-setup.ps1 *> C:\Users\quint\git\mobile-gen\_android_setup.txt 2>&1`
Then Read `_android_setup.txt`.
Expected: `ANDROID_HOME set…`, debug keystore generated (or already present), and the printed editor-settings keys.

- [ ] **Step 2: Point Godot's editor settings at the SDK + keystore**

Open Godot once (`Editor > Editor Settings > Export > Android`) and set the four keys the helper printed, OR edit `%APPDATA%\Godot\editor_settings-4.tres` directly. Then confirm headless can read them — capture a probe of an Android export validation:

Run: `$env:ANDROID_HOME = "C:\Users\quint\AppData\Local\Android\Sdk"; & "<godot _console.exe>" --headless --path C:\Users\quint\git\mobile-gen\games\creature-0001 --export-debug "Glade Spirit" C:\Users\quint\git\mobile-gen\games\creature-0001\build\_probe.apk *> C:\Users\quint\git\mobile-gen\_android_probe.txt 2>&1`
Then Read `_android_probe.txt`.
Expected (success): an APK at `build/_probe.apk`. If it errors with "Android SDK path is invalid" / "Unable to find keystore", fix the editor-settings keys and re-probe. If it errors that the export template is missing, confirm `%APPDATA%\Godot\export_templates\4.6.3.stable` exists. Record the exact error if any — that error IS the deliverable insight if setup is incomplete.

- [ ] **Step 3: Create + boot an AVD**

Run: `& "$env:ANDROID_HOME\cmdline-tools\latest\bin\avdmanager.bat" list avd *> C:\Users\quint\git\mobile-gen\_avd_list.txt 2>&1` and Read it. If no AVD exists, create one against an installed system-image (list with `sdkmanager --list_installed` or check `$env:ANDROID_HOME\system-images`), e.g.:
`& "$env:ANDROID_HOME\cmdline-tools\latest\bin\avdmanager.bat" create avd -n gf_pixel -k "system-images;android-33;google_apis;x86_64" -d pixel_6`
Then boot headless-friendly: `& "$env:ANDROID_HOME\emulator\emulator.exe" -avd gf_pixel -no-snapshot -no-boot-anim` (run in background) and wait for boot:
`& "$env:ANDROID_HOME\platform-tools\adb.exe" wait-for-device shell getprop sys.boot_completed` → expect `1`.
Expected: an AVD boots to a home screen. If the system-image is missing, install it via `sdkmanager` first; if HAXM/Hyper-V blocks it, record that as the AVD risk the spec flagged and fall back to whatever image boots.

- [ ] **Step 4: Clean up the probe APK**

Run: `Remove-Item C:\Users\quint\git\mobile-gen\games\creature-0001\build\_probe.apk -ErrorAction SilentlyContinue; Remove-Item C:\Users\quint\git\mobile-gen\_android_*.txt, C:\Users\quint\git\mobile-gen\_avd_list.txt -ErrorAction SilentlyContinue`
(No commit — these are machine config + scratch, git-ignored or transient.)

---

## Task 10: Phase A — build the debug APK and run it on the emulator

> **Verification-driven.** The POC gate: a debug APK that installs and runs.

**Files:** `games/creature-0001/build/creature-0001-debug.apk` (git-ignored), a screenshot.

- [ ] **Step 1: Regenerate creature-0001's export_presets.cfg with both presets**

Run: `node C:\Users\quint\git\mobile-gen\tools\package.mjs preset creature-0001` currently prints a single preset; instead use the new two-preset emitter. Run a tiny node one-liner to write the file:
`node -e "import('./tools/package.mjs').then(m=>{const fs=require('fs');fs.writeFileSync('games/creature-0001/export_presets.cfg', m.exportPresetsFile({id:'creature-0001',name:'Glade Spirit'}));console.log('wrote')})"` (from repo root).
Then Read `games/creature-0001/export_presets.cfg` and confirm it has `[preset.0]` (Glade Spirit, debug apk, gradle false) and `[preset.1]` (Glade Spirit Release, aab, gradle true).

- [ ] **Step 2: Build the debug APK**

Run: `$env:ANDROID_HOME = "C:\Users\quint\AppData\Local\Android\Sdk"; node C:\Users\quint\git\mobile-gen\tools\package.mjs build creature-0001 *> C:\Users\quint\git\mobile-gen\_build.txt 2>&1`
Then Read `_build.txt`.
Expected: JSON `{ format: "apk", build_type: "debug", path: "build/creature-0001-debug.apk", bytes: <>, package: "com.gameforge.creature-0001" }`. If it reports `skipped`, `ANDROID_HOME` was not set in this process — set it and re-run. If Godot errors, record the exact line and fix (almost always editor-settings SDK/keystore from Task 9).

- [ ] **Step 3: Verify the built APK is well-formed**

Run: `$env:ANDROID_HOME = "C:\Users\quint\AppData\Local\Android\Sdk"; node C:\Users\quint\git\mobile-gen\tools\package.mjs verify-build creature-0001`
Expected: `{ ok: true, signature_ok: true, ... }`.

- [ ] **Step 4: Install + launch on the booted AVD**

Run: `& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r C:\Users\quint\git\mobile-gen\games\creature-0001\build\creature-0001-debug.apk` → expect `Success`.
Run: `& "$env:ANDROID_HOME\platform-tools\adb.exe" shell monkey -p com.gameforge.creature-0001 -c android.intent.category.LAUNCHER 1` → launches the app.
Give it ~5s, then screenshot:
`& "$env:ANDROID_HOME\platform-tools\adb.exe" exec-out screencap -p > C:\Users\quint\git\mobile-gen\games\creature-0001\store\screenshots\android-emulator.png`
Then Read that PNG (the Read tool renders images) to confirm the game is actually on screen (spirit + glade backdrop + HUD), not a crash dialog.
Expected: the running game is visible. If a crash/ANR dialog shows, pull the logcat (`adb logcat -d *:E > _logcat.txt`), record the error, and attribute it (builder/asset/audio) — a legible failure is still a POC success.

- [ ] **Step 5: Record the Phase-A result (no status change)**

Note the APK bytes + emulator screenshot path for the Task 12 manifest merge. Do not advance status. Remove `_build.txt`/`_logcat.txt` scratch.

---

## Task 11: Phase B — release keystore, signed AAB, submission doc

> **Verification-driven.** Builds the signed AAB now; actual Play upload is owner-gated.

**Files:** release keystore (git-ignored, outside or `*.keystore`), `tools/android-signing.local.json` (git-ignored), `games/creature-0001/build/creature-0001-release.aab` (git-ignored), `docs/superpowers/specs/2026-06-02-play-console-submission.md` (committed).

- [ ] **Step 1: Generate a release keystore (git-ignored) + local signing config**

Run (PowerShell): generate a release keystore outside the repo or as a `*.keystore` (ignored):
`& keytool -genkeypair -v -keystore C:\Users\quint\.android\gameforge-release.keystore -storepass <PICK> -keypass <PICK> -alias gameforge -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=GameForge,O=GameForge,C=US"`
Then create `tools/android-signing.local.json` (git-ignored — confirm with `git check-ignore`):
```json
{ "keystore_path": "C:\\Users\\quint\\.android\\gameforge-release.keystore", "keystore_user": "gameforge", "keystore_password": "<PICK>" }
```
Confirm: `git -C C:/Users/quint/git/mobile-gen status --short` shows NEITHER the keystore nor the json (both ignored).

- [ ] **Step 2: Install the Android build template (required for AAB)**

AAB output needs Godot's gradle build. Install the build template for the project: in Godot open `games/creature-0001`, `Project > Install Android Build Template` (creates `games/creature-0001/android/`). Confirm `games/creature-0001/android/build` exists. (If this adds many files, ensure they're handled per repo convention — the `android/` build template is typically git-ignored; add `games/*/android/` to `.gitignore` if Godot generates it and we don't want it committed. Record the decision.)

- [ ] **Step 3: Build the signed AAB**

Run: `$env:ANDROID_HOME = "C:\Users\quint\AppData\Local\Android\Sdk"; node C:\Users\quint\git\mobile-gen\tools\package.mjs build creature-0001 --release --aab *> C:\Users\quint\git\mobile-gen\_aab.txt 2>&1`
Then Read `_aab.txt`.
Expected: JSON with `format: "aab", build_type: "release", path: "build/creature-0001-release.aab"`. If Godot errors that AAB needs gradle build / build template, complete Step 2 and re-run. If signing fails, re-check the env vars sourced from `android-signing.local.json`. Record the exact error if it doesn't succeed — Godot's headless AAB path is the spec's flagged risk; a legible blocker is a valid outcome.

- [ ] **Step 4: Verify the AAB + confirm signature**

Run: `node C:\Users\quint\git\mobile-gen\tools\package.mjs verify-build creature-0001` after temporarily recording the AAB (or call `verifyBuildArtifact` against the aab path). Optionally confirm the signature with `jarsigner -verify` or `bundletool` if available.
Expected: `{ ok: true, signature_ok: true }` for the `.aab`.

- [ ] **Step 5: Write the Play Console submission doc**

Create `docs/superpowers/specs/2026-06-02-play-console-submission.md` documenting the owner-gated path: (1) create a Play developer account; (2) create the app + listing (title, short/full description, the store icon `ic_play_store.png`, screenshots from `store/screenshots/`, the feature graphic — flag if missing); (3) content rating questionnaire; (4) data-safety form; (5) set up an internal-testing track; (6) upload `creature-0001-release.aab`; (7) release-keystore custody (back up the keystore + passwords — losing it means you can never update the app). Mark each owner-gated step. Reference the locally-built AAB as the input.

- [ ] **Step 6: Commit the doc (only the doc — binaries/keystore/config stay ignored)**

```bash
git -C C:/Users/quint/git/mobile-gen add docs/superpowers/specs/2026-06-02-play-console-submission.md .gitignore
git -C C:/Users/quint/git/mobile-gen commit -m "docs(android): Play Console submission path (owner-gated) + ignore android build template"
```

(Include `.gitignore` only if Step 2 added a `games/*/android/` ignore.)

---

## Task 12: Record `build_artifact` on creature-0001, keep status `styled`, finalize

**Files:**
- Modify: `manifests/creature-0001.json` (record `store_pass.build_artifact`; add the emulator screenshot)
- Modify: `games/creature-0001/export_presets.cfg` (the two-preset file from Task 10 Step 1)

- [ ] **Step 1: Record the build artifact in the manifest**

Run (from repo root, fill in the real bytes from Task 10):
```
node tools/manifest.mjs merge creature-0001 "{\"store_pass\": {\"build_artifact\": {\"format\": \"apk\", \"build_type\": \"debug\", \"path\": \"build/creature-0001-debug.apk\", \"bytes\": <BYTES>, \"package\": \"com.gameforge.creature-0001\"}}}"
```
Note: `merge` deep-merges, so this adds `build_artifact` without disturbing the existing `store_pass` arrays. If `merge` replaces `store_pass` wholesale, instead re-supply the full `store_pass` with `build_artifact` added (check `tools/manifest.mjs` merge semantics first — the packager skill notes "arrays replace wholesale").

- [ ] **Step 2: Add the emulator screenshot to store_pass.screenshots (optional but real)**

If the Task 10 emulator screenshot is worth keeping as a store asset, add it to `store_pass.screenshots[]` as `{ name: "android-emulator", px: "<WxH>", source: "store/screenshots/android-emulator.png" }`. Confirm its dimensions via `node tools/package.mjs` pngSize path or skip if redundant.

- [ ] **Step 3: Validate the manifest + run the no-SDK verify**

Run: `node tools/manifest.mjs validate creature-0001` → expect valid.
Run: `node tools/package.mjs verify creature-0001` → expect `file_checks_pass: true` (the new build_artifact shape check passes; binaries are not checked here).
Confirm status is still `styled`: `node tools/manifest.mjs` read or grep — it must NOT have advanced to `packaged`.

- [ ] **Step 4: Update the store_pass notes to reflect the proven build**

Edit `manifests/creature-0001.json` `store_pass.notes` to record: the debug APK was built + installed + run on the emulator (screenshot), the signed AAB was built locally (Phase B), `build_artifact` recorded; status intentionally held at `styled` (owner A/B for `styled`/`scored` + cross-modal cohesion remain owner gates; the build proves the *toolchain*, not the game's polish).

- [ ] **Step 5: Full test suite green**

Run: `npm test`
Expected: PASS — all suites, count ≥ 163 + the new specs from Tasks 2–6.

- [ ] **Step 6: Commit**

```bash
git -C C:/Users/quint/git/mobile-gen add manifests/creature-0001.json games/creature-0001/export_presets.cfg games/creature-0001/store/screenshots/android-emulator.png
git -C C:/Users/quint/git/mobile-gen commit -m "feat(creature-0001): record proven Android build_artifact; two-preset cfg; status held styled"
```

- [ ] **Step 7: Update memory**

Update `android-shippable-poc.md` (and the `MEMORY.md` pointer) to reflect: plan executed, build seam landed + vitest green, debug APK ran on emulator (screenshot), signed AAB built, submission doc committed, creature-0001 `build_artifact` recorded, status held `styled`. Record any empirical findings/blockers from Tasks 9–11 (AAB/gradle, AVD boot) as durable notes.

---

## Self-review (completed during planning)

**Spec coverage:**
- Spec §"Design 1" (env setup) → Task 8 (helper + README) + Task 9 (run it). ✓
- Spec §"Design 2" (build seam + schema): pure `buildArtifactPlan` → Task 3; impure `buildArtifact` → Task 4; `exportPresetCfg` release/AAB variant → Task 2; `store_pass.build_artifact` schema → Task 5; CLI `build` → Task 6. ✓
- Spec §"Design 3" (CI-safety): mocked/guarded spawn, `androidToolchainPresent`, skip-when-absent → Tasks 3, 4, 6; vitest-green checks throughout. ✓
- Spec §"Design 4" (packager skill + validator gate) → Task 7. ✓
- Spec §"Design 5" (Phase B release): keystore, signed AAB, submission doc → Task 11. ✓
- Spec §"Design 6" (proof on creature-0001 + status ceremony: record build_artifact, stay `styled`) → Tasks 10, 12. ✓
- Spec §"Design 7" (offline vitest specs) → Tasks 2–6 each add specs. ✓
- Spec §"Risks" (headless export config, AVD boot, .gitignore hygiene) → Task 1 (.gitignore), Task 9 (probe-before-build for export config + AVD), Tasks 10/11 record empirical blockers. ✓
- Spec "Deliverables" 1–7 → all mapped above. ✓

**Type/name consistency:** `buildArtifactPlan` returns `{ args, outPath, package, preset, format, build_type }` (used identically in Tasks 3, 4, 6). `androidToolchainPresent()` env-driven (Tasks 3, 4, 6). `verifyBuildArtifact` returns `{ skipped | ok, issues, signature_ok, bytes }` (Tasks 4, 6). Schema field `build_artifact: { format, build_type, path, bytes, package }` matches the record `buildArtifact()` returns and the merge in Task 12. `exportPresetsFile` (Task 2) is consumed in Task 10. Preset names: debug = game `name`; release = `"<name> Release"` (consistent in Tasks 2, 3). ✓

**Placeholder scan:** every code step shows the full code; commands have expected output; `<BYTES>`/`<PICK>` are intentional runtime values (real bytes from the build, owner-chosen passwords), not unfilled plan placeholders. ✓
