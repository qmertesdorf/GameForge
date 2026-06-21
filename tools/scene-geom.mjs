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
  return { clippedPx, fully, clipped: clippedPx > tol };
}

export function scoreGeometry(nodes, viewport, { clipTol = 2, opaqueAlpha = 0.9 } = {}) {
  const vis = nodes.filter((n) => n.visible);
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
  }
  const ok = hard.length === 0;
  const bboxes = [...hard, ...advisory].map((f) => ({ kind: f.kind, path: f.path ?? f.victim?.path, rect: f.rect ?? f.victim?.rect }));
  return { ok, viewport, checked, hard, advisory, bboxes };
}
