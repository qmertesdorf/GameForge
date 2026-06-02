# Arcane Deckbuilder — Quality-Push Vertical Slice (Design Spec)

**Date:** 2026-06-02
**Status:** Approved (brainstorming complete) → next step: implementation plan
**Owner thread:** Depth quality push — "make new games, hone in on a higher quality bar"

---

## 1. Purpose & framing

Build **one excellent game** — a wizards' arcane-duel roguelike deckbuilder, as a **tight vertical slice** — and use the difficulty of building it to **upgrade the GameForge skills**. The two deliverables are co-equal:

1. A deckbuilder that genuinely crosses the bar from "tech demo" to "I'd keep playing this."
2. Concretely upgraded `builder` / `asset` / `validator` `SKILL.md` files that now know how to handle a **systems-heavy, UI-heavy, turn-based** genre — a class of game the loop has never produced.

This is grounded in the project's stated deliverable: **better skills, not the games.** The game is the vehicle that surfaces skill gaps.

### How it runs (process)

Drive it through the normal loop **exactly as designed** — `concept → builder → validator → asset → audio` — and treat every place a skill *cannot* produce a good deckbuilder as the actual finding. Fix the responsible `SKILL.md`, not just the game.

**Risk flagged & accepted:** a full deckbuilder may be too large for the `builder` skill to one-shot. If it stalls, decompose the build into stages the skill can handle (combat engine → cards → run/map → rewards → meta) and **codify that decomposition into the skill** — which is itself a valuable skill upgrade. Do *not* fall back to hand-authoring the game for speed; that produces zero skill improvement and defeats the project's purpose.

### Success criteria

- A playable run from first combat through boss, with win/lose screens.
- The 3-element combo system creates visibly different viable builds.
- Visual + juice + audio land at a bar the owner judges "I'd actually play this" (not "neat demo").
- At least the `validator` skill (turn-based Method) and likely `builder`/`asset` skills gain documented, reusable upgrades.

### Quality axes (owner-stated, all in scope)

1. **Visual polish** — cohesive art, real background (not flat fill), proper sizing, readable composition.
2. **Game feel / juice** — animation, screen shake, particles, tweened motion, satisfying feedback.
3. **Core-loop depth** — fun for 60+ seconds; escalation, scoring tension.
4. **Cohesion / theme** — art, audio, UI, mechanics feel like one intentional product.
5. **Expandable depth** — a concrete reason to keep playing (meta-progression seed).

---

## 2. Theme & identity

**Arcane duel (wizards).** A lone mage faces a sequence of monsters, casting elemental spell cards. Classic, readable, and maximally **SVG-friendly** (geometric sigils, glows, mana crystals) — which is the reliable art path for this project (vs the rougher raster pipeline).

- **Palette:** deep indigo / violet base, with element accents — fire (amber/orange), ice (cyan/white), lightning (electric yellow/violet).
- **Motifs:** runic circles, mana crystals, glowing sigils, spell glyphs.

---

## 3. Game design (the vertical slice)

### 3.1 Combat engine (core)

- **Player:** HP ~70, **Block** (resets at start of player turn), **Mana** 3/turn.
- **Turn loop:** draw 5 → play cards (spend mana) → end turn → enemy acts → statuses tick → repeat.
- **Piles:** draw / hand / discard. Reshuffle discard into draw when draw empties.
- **Win/lose:** enemy HP 0 = win; player HP 0 = lose.
- **Enemy intent:** telegraphed above the enemy each turn ("attacks for 9", "defends", "enrages"). The telegraph turns each turn into a solvable puzzle.

### 3.2 Elements as the depth engine

Three elements that **combo across each other** — the source of build variety:

| Element | Status / effect | Role |
|---|---|---|
| **Fire** | **Burn** — DoT stacks; tick at end of enemy turn, decrement | Setup / sustained damage |
| **Ice** | **Block** + **Chill** — gain block; Chill makes enemy skip its next attack | Defense / tempo |
| **Lightning** | **Chain / Overload** — multi-hit; **bonus damage to Burning or Chilled targets** | Payoff / cash-in |

Fire and Ice set up a status; Lightning cashes it in for bonus damage. This is the discoverable synergy that drives "one more run to try a lightning build."

### 3.3 Content

- **Card pool ~16**, starter deck of 10. Cards span **Attack / Skill / Power** types across the 3 elements plus a couple of neutral combo-enablers (draw, extra mana). Indicative pool (builder/concept finalize exact numbers):
  - *Neutral:* Arcane Bolt (1 mana, deal 6), Ward (1 mana, +5 block), Meditate (1 mana, draw 2), Mana Surge (combo enabler).
  - *Fire:* Ember (deal + apply Burn), Flame Lash (bigger + Burn), Immolate (heavy + Burn), Wildfire (Power: attacks apply Burn).
  - *Ice:* Frost Shard (small dmg + block), Glacial Wall (block), Freeze (apply Chill), Blizzard (dmg + Chill).
  - *Lightning:* Spark (0-cost chip), Chain Lightning (bonus vs status), Overload (Power: +dmg to afflicted), Thunderclap (dmg + draw).
- **Run = ~5 nodes:** Combat → Combat → **Rest** (heal a % *or* remove a card) → **Elite** (drops a relic) → **Boss** (more HP, nastier multi-turn intent pattern).
- **Card reward:** **pick 1 of 3** after each combat (with a skip option) — the central deckbuilding decision.
- **Relics:** start with 1 passive relic; earn 1 from the elite. Minimal but present. (e.g. "Ember Heart: at start of combat, apply 1 Burn to the enemy.")

### 3.4 Expandable depth (meta-progression seed)

Beating the boss writes a small save file (`user://save.json`) that:
- **Unlocks 1 new card** into the future-run pool, and
- Reveals an **ascension toggle** (enemies gain HP/damage on the next run).

Persisted state: unlocked cards, ascension level, best result. This is a **seed** of meta-progression, not a full tree — honest scope note: real long-term retention is a v2 concern. The seed gives a concrete "you earned something, go again harder" loop.

---

## 4. Quality execution

### 4.1 Game feel / juice (deterministic, tween/particle-based — headless-safe)

- Cards lift on hover, arc to center on play, resolve, sweep to discard.
- **Number pop-ups** for damage/block; enemy **hit-flash + screen shake scaled to damage**; block shield shimmer; mana orbs drain/fill; HP bars tween.
- **Status icons** (flame / snowflake) with stack counts on the enemy; enemy death = dissolve + particle burst.
- Intent telegraph animates in at the start of the enemy turn.

### 4.2 Visual polish (asset pass — SVG path)

- **Real background** — arcane chamber: deep indigo→violet gradient, a glowing runic circle on the floor, floating motes. Explicitly **not a flat fill** (the project's #1 recurring complaint).
- **Card frames** — element-colored borders, a per-element sigil, cost gem, readable type band. Cards are ~90% of what the player looks at, so the polish budget concentrates here.
- **Distinct enemy silhouettes** per encounter (imp / frost-wraith / golem / boss archmage), themed and properly sized.
- Styled UI: HP/mana, intent icon above enemy, end-turn button, pile counts.

### 4.3 Audio (locked settings from prior work)

- **SFX:** per-element card play (fire whoosh / ice crackle / lightning zap), card draw, block chime, hit thud, victory & defeat stings.
- **BGM:** low, melodic arcane ambient loop (per the locked audio settings — melody-forced, anti-drone, correct bed volume_db).

---

## 5. Validation (the hard new part — a real skill finding)

The `validator` skill has only ever checked **real-time** games (does it open, does the loop tick). Turn-based needs a genuinely different self-test, which is expected to require a **new validator "Method" for turn-based games:**

- **Seeded RNG** so the self-test is deterministic.
- A **scripted turn** in `selftest.gd`: start combat → assert a hand was drawn → play a card → assert mana spent + damage/effect applied → end turn → assert the enemy acted and statuses ticked → force-kill the enemy → assert the reward (pick-1-of-3) screen appears → assert run advances.
- Assert win/lose transitions and the meta save-file write on boss kill.

This validator upgrade is one of the concrete skill deliverables of this work.

---

## 6. Architecture & components

Built as a Godot 4.6.3 project under `games/<id>/` driven by a manifest, following existing project conventions. Logical units (each independently understandable/testable):

- **CombatState** — pure data + rules: HP/block/mana/piles/statuses, `play_card`, `end_turn`, `enemy_act`, win/lose detection. Seedable RNG. No rendering. (This is what `selftest.gd` drives.)
- **CardDB** — card definitions (id, name, element, cost, type, effect). Data-driven so the pool is easy to extend.
- **EnemyDB** — enemy definitions (HP, intent script).
- **RunController** — node map (~5 nodes), progression, reward screens, rest, relic grants.
- **CombatView** — renders CombatState; owns juice (tweens, pop-ups, shake, particles). Reads state, never owns rules.
- **MetaSave** — read/write `user://save.json` (unlocks, ascension, best).
- **UI** — HP/mana, intent, hand, end-turn, pile counts, reward picker, win/lose screens.

**Data flow:** input → CombatView calls CombatState methods → CombatState mutates and returns events → CombatView animates events. RunController orchestrates combats and rewards. MetaSave reads at boot, writes on boss win.

**Separation principle:** rules (CombatState) are fully decoupled from rendering (CombatView) so the self-test can exercise the entire game logic headlessly without a viewport.

---

## 7. Scope guardrails (YAGNI)

**In:** one mage, 3 elements, ~16 cards, ~5-node run, 1 status per element, 2 relics, pick-1-of-3 rewards, full juice/art/audio, win/lose, 1-card meta unlock + ascension toggle.

**Explicitly out (v2):** multiple characters, branching map, 30+ card pool, full relic system, deep meta tree, daily seeds, card upgrade system. We extend a tight slice later; we do not build wide now.

---

## 8. Open items for the implementation plan

- Decide the manifest `id` (e.g. `deckbuilder-0001`) and concept block shape — does the existing `concept` skill schema express card pools / run nodes, or does it need additive fields?
- Determine whether `builder` can one-shot this or needs the staged decomposition (§1 risk), and codify whichever path is taken.
- Define the turn-based validator Method concretely (§5) as a validator `SKILL.md` addition.
- Confirm SVG asset path can carry card-frame + enemy-silhouette volume, or whether any raster is warranted.
