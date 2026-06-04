# Lens: Colour-accessibility

Used by the `visual-audit` skill (parallel). Contrast + colour-blind safety, judged on the composite. Sibling of the legibility lens; structured separately so it can graduate to its own standalone skill later.

- **Colour-accessibility sweep — contrast + colour-blind safety, judged on the composite.**
  - **Contrast ratio:** every text/icon-vs-its-backing pair clears a legible contrast at true size (target WCAG-ish ≥4.5:1 body, ≥3:1 large/bold). Thin light text on a mid-tone panel, or dark numerals on a dark badge, fail. Fix by solidifying/darkening the backing and lifting the text value — not by enlarging alone.
  - **Never encode meaning by hue alone.** State is signalled by colour (fire=amber, ice=cyan, lightning, Burn vs Chill, danger=red, mana=blue, health=green, affordable vs unaffordable). ~8% of players are red-green colour-blind and cheap phone panels in glare crush hue — so every colour-coded state must ALSO carry a non-colour cue (icon, shape, label, position). A red "can't afford" tint with no other signal, or Burn/Chill distinguished only by warm-vs-cool, is a FINDING. (This title's burn/chill/attack/defend icons are the right pattern — verify each colour-coded state actually has one.)
  - **Differ in VALUE, not only hue.** Two semantic colours sharing lightness (a red and a green at the same brightness) collapse for colour-blind users and in glare; ensure paired/opposed states also differ in brightness.
  - **Simulate it:** eyeball the frame desaturated/grayscale (kills hue, exposes value-only collisions) and mentally through a red-green filter — if two states become indistinguishable, add a non-colour cue.
