# Note: the "usage policy violation" error + current POC status

## The usage-policy error — what it likely is

To be upfront: I can't see Claude Code's safety-classifier decisions, so I'm inferring from context. But here's the most likely explanation.

Claude Code runs conversation content past an automated usage-policy classifier. That classifier operates on raw text and **doesn't always understand context** — and the work we just did is the most plausible trigger:

**We generated a large volume of combat/shooting vocabulary for the top-down shooter** (`shooter-0001`, "Vector Storm"). The concept, the builder dispatch, and the run report are dense with phrases like *auto-fire, bullets, kills, destroy enemies, shoot, muzzle flash, lives, player hit, screen shake on damage, waves of enemies closing in.* A naive content filter can false-positive on that density of weapons/violence language even though the context is obviously **legitimate video-game development with abstract neon shapes**.

So: almost certainly a **false positive on game-violence terminology**, not anything you or I actually did wrong. Nothing in this session is remotely policy-violating — it's a Godot game-dev POC.

## Two honest caveats

1. **I'm not certain it was the shooter.** It's the strongest candidate by far, but the flag could be from something else in the recent turns. The timing (right after the shooter run) points at the combat vocabulary.

2. **I noticed intermittent garbled tool output earlier** in the session — some Bash/Read results came back with fabricated text and malformed fragments mixed into otherwise-correct output. I cross-checked everything through clean channels (git SHAs, checksums, `Read` with line numbers) and the **actual work and git history are all intact and correct**. I flag it only because *if* it's related to the same classifier/safety machinery acting on the content, that would tie the two together. But that's speculation.

## What it means for you

- **It's not a strike against your account for real misuse** — automated false positives on game-dev "violence" language are a known rough edge.
- It's typically **transient**; you can keep going. If a specific message gets blocked, rephrasing around the combat terms (or noting "abstract game prototype") usually clears it.
- If it persists or blocks work, you can report it as a false positive through Claude Code's feedback (`/bug`).

## Where we are (so you don't lose the thread)

The POC's **≥3-distinct-genre bar is met** — runner + match-3 + shooter all `playable` from one unchanged skill set, each with a committed run report. Findings are compounding (the typing rule from run 2 gave run 3 a zero-iteration build). Everything is committed on `gameforge-poc`.

### Games built (all `playable`)
| id | name | genre | run report |
|----|------|-------|------------|
| `runner-0002` | Neon Dash II | endless runner | `poc-run-001.md` (A/B re-gen) |
| `match3-0001` | Prism Cascade | match-3 | `poc-run-002.md` |
| `shooter-0001` | Vector Storm | top-down shooter | `poc-run-003.md` |

(`runner-0001` was the original "terrible but playable" baseline that motivated the run-001 skill upgrades.)

### Open choices for next step
When you're ready, the open choices are:
- **(a)** demonstrate a **genre combination** (the one untested part of your "any number of genres / combination of genres" goal),
- **(b)** build **brick breaker** for more sample, or
- **(c)** do the consolidated **skill-iteration pass** applying the deferred findings (run-001 already applied; run-002/003 findings — Godot 4.6 typing rule for `builder`, agency rule for `concept`, `selftest.gd` automation hook for `validator` — still pending).

No rush — happy to pause here given the policy flag.
