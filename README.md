# GameForge (POC)

An AI pipeline that turns a one-line prompt into a playable mobile game, built as Claude Agent Skills. See `docs/superpowers/specs/2026-05-30-gameforge-poc-design.html` for the design.

## Pinned Godot version

`4.6.3.stable` — **source of truth** for every manifest's `build.engine_version`. Both machines must match (§11). Update here and in existing manifests if you bump it.

## Layout

- `.claude/skills/` — the `concept`, `builder`, `validator` skills.
- `manifests/<id>.json` — one manifest per title (the spine; §5).
- `games/<id>/` — generated Godot projects.
- `tools/manifest.mjs` — the manifest CLI (`create` / `set-status` / `merge` / `validate`).
- `schema/manifest.schema.json` — the manifest schema.

## The loop

prompt → `concept` → `builder` → `validator` → human playtest → edit the responsible `SKILL.md` → repeat across ≥3 genres. The deliverable is **better skills**, not the games.

## Manifest CLI

```
node tools/manifest.mjs create <id> "<name>"     # new skeleton, status=concept
node tools/manifest.mjs merge  <id> '<json>'      # deep-merge a partial (e.g. the concept block)
node tools/manifest.mjs set-status <id> <status>  # concept→generated→validated→playable | →failed
node tools/manifest.mjs validate <id>             # schema-check; exit 1 if invalid
```

## Tests

`npm test`
