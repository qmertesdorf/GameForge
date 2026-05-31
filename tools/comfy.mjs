import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");

export const COMFY_HOST = process.env.COMFY_HOST || "http://127.0.0.1:8188";
export const TEMPLATES_DIR = process.env.GAMEFORGE_COMFY_TEMPLATES || join(__dirname, "comfy-templates");
export const GAMES_DIR = process.env.GAMEFORGE_GAMES_DIR || join(REPO_ROOT, "games");

// Map a %token% to the recipe field that fills it. master_resolution fills the
// square master's width AND height. A resolver returning undefined is a hard
// error so a missing field fails loudly (attributable to the recipe), never
// silently leaving a literal "%prompt%" in the graph.
const TOKENS = {
  "%checkpoint%": (r) => r.checkpoint,
  "%prompt%": (r) => r.prompt,
  "%negative%": (r) => r.negative ?? "",
  "%seed%": (r) => r.seed,
  "%steps%": (r) => r.steps,
  "%cfg%": (r) => r.cfg,
  "%sampler%": (r) => r.sampler,
  "%width%": (r) => r.master_resolution,
  "%height%": (r) => r.master_resolution,
  "%lora%": (r) => r.lora
};

// Deep-clone `template` and substitute placeholder strings with recipe values.
// Pure: no network, no disk, no mutation of the input.
export function injectRecipe(template, recipe) {
  const walk = (node) => {
    if (Array.isArray(node)) return node.map(walk);
    if (node && typeof node === "object") {
      const out = {};
      for (const [k, v] of Object.entries(node)) out[k] = walk(v);
      return out;
    }
    if (typeof node === "string" && Object.prototype.hasOwnProperty.call(TOKENS, node)) {
      const value = TOKENS[node](recipe);
      if (value === undefined) {
        throw new Error(`comfy: recipe is missing the field for placeholder ${node}`);
      }
      return value;
    }
    return node;
  };
  return walk(template);
}
