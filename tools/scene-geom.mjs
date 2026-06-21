// Deterministic scene-tree GEOMETRY pre-filter for the visual-audit gate — the
// testable seam that turns three geometric defect classes into facts ahead of the
// VLM lens fan-out: off-viewport clipping, opaque occlusion, and missing-texture
// nodes. Pure scoring lives here; the thin Godot op (scene_geometry.gd) only reads
// the live tree's geometry — the same pure-JS-seam + thin-Godot split as contrast.mjs.
//
// CLI:
//   node tools/scene-geom.mjs check <game-dir> [--clip-tol N] [--opaque-alpha A]
//
// BOUNDARY: sees only introspectable CanvasItem geometry (Control rects, textured
// Node2D). Art drawn via custom _draw()/draw_texture() is invisible here and stays
// the composition/collision VLM lens's job — a low `checked` count means the game
// draws in code, not that the screen is clean.

// --- geometry helpers (pure) ---------------------------------------------
// rect = [x, y, w, h]; viewport = [w, h].
function offViewport(rect, [vw, vh], tol) {
  const [x, y, w, h] = rect;
  const out = Math.max(-x, -y, x + w - vw, y + h - vh); // worst overshoot on any side
  const clippedPx = Math.max(0, Math.round(out));
  const fully = x >= vw || y >= vh || x + w <= 0 || y + h <= 0;
  return { clippedPx, fully, clipped: clippedPx > tol }; // clipped only when overshoot EXCEEDS tol (tol px of bleed is tolerated)
}

// effective opacity of a node as an occluder, vs the opaqueAlpha bar.
function isOpaque(n, opaqueAlpha) {
  const base = n.fill_a != null ? n.fill_a : (n.has_texture ? 1 : 0);
  return base * (n.mod_a ?? 1) >= opaqueAlpha;
}
// paint-above: higher z_index wins; ties broken by walk order (paint).
function isAbove(a, b) {
  const za = a.z_index ?? 0, zb = b.z_index ?? 0;
  if (za !== zb) return za > zb;
  return (a.paint ?? 0) > (b.paint ?? 0);
}
// rect a fully contains rect b (within tol on every side).
function contains(a, b, tol) {
  return b[0] >= a[0] - tol && b[1] >= a[1] - tol &&
         b[0] + b[2] <= a[0] + a[2] + tol && b[1] + b[3] <= a[1] + a[3] + tol;
}
// area of intersection of two rects (0 if disjoint).
function overlapArea(a, b) {
  const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]);
  const r = Math.min(a[0] + a[2], b[0] + b[2]), btm = Math.min(a[1] + a[3], b[1] + b[3]);
  const w = r - x, h = btm - y;
  return w > 0 && h > 0 ? w * h : 0;
}

export function scoreGeometry(nodes, viewport, { clipTol = 2, opaqueAlpha = 0.9 } = {}) {
  const vis = nodes.filter((n) => n.visible);
  const occluders = vis.filter((n) => isOpaque(n, opaqueAlpha));
  const hard = [];
  const advisory = [];
  let checked = 0;
  for (const n of vis) {
    const victim = !!(n.is_text || n.interactive);
    if (victim) {
      checked++;
      const ov = offViewport(n.rect, viewport, clipTol);
      if (ov.clipped)
        hard.push({ kind: "offscreen", path: n.path, class: n.class, rect: n.rect, clippedPx: ov.clippedPx, fully: ov.fully });
    }
    // occlusion: is some opaque higher node sitting over this one?
    let fullyOccluded = false;
    for (const c of occluders) {
      if (c === n || !isAbove(c, n)) continue;
      if (contains(c.rect, n.rect, clipTol)) {
        if (victim) {
          hard.push({ kind: "occluded", victim: { path: n.path, class: n.class, rect: n.rect }, occluder: { path: c.path, class: c.class } });
          fullyOccluded = true;
        }
        break;
      }
    }
    if (!fullyOccluded) {
      const over = occluders.find((c) => c !== n && isAbove(c, n) && overlapArea(c.rect, n.rect) > 0);
      if (over)
        advisory.push({ kind: "overlap", path: n.path, class: n.class, rect: n.rect, over: over.path });
    }
  }
  const ok = hard.length === 0;
  const bboxes = [...hard, ...advisory].map((f) => ({ kind: f.kind, path: f.path ?? f.victim?.path, rect: f.rect ?? f.victim?.rect }));
  return { ok, viewport, checked, hard, advisory, bboxes };
}
