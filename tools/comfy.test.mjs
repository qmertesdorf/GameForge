import { test, expect, describe } from "vitest";
import { injectRecipe } from "./comfy.mjs";

// A tiny stand-in for an exported ComfyUI graph: nodes keyed by id, each with
// class_type + inputs. Placeholder tokens are plain strings like "%prompt%".
function fixtureTemplate() {
  return {
    "4": { class_type: "CheckpointLoaderSimple", inputs: { ckpt_name: "%checkpoint%" } },
    "6": { class_type: "CLIPTextEncode", inputs: { text: "%prompt%", clip: ["4", 1] } },
    "7": { class_type: "CLIPTextEncode", inputs: { text: "%negative%", clip: ["4", 1] } },
    "5": { class_type: "EmptyLatentImage", inputs: { width: "%width%", height: "%height%", batch_size: 1 } },
    "3": {
      class_type: "KSampler",
      inputs: {
        seed: "%seed%", steps: "%steps%", cfg: "%cfg%", sampler_name: "%sampler%",
        model: ["4", 0], positive: ["6", 0], negative: ["7", 0], latent_image: ["5", 0]
      }
    },
    "9": { class_type: "SaveImage", inputs: { images: ["8", 0] } }
  };
}

function fullRecipe() {
  return {
    name: "hero",
    checkpoint: "dreamshaperXL.safetensors",
    prompt: "a small round forest spirit",
    negative: "logo, watermark, text",
    seed: 123456,
    sampler: "dpmpp_2m",
    steps: 30,
    cfg: 6.5,
    master_resolution: 512,
    layerdiffuse: true
  };
}

describe("injectRecipe", () => {
  test("replaces scalar placeholders with recipe values (master_resolution → width & height)", () => {
    const out = injectRecipe(fixtureTemplate(), fullRecipe());
    expect(out["4"].inputs.ckpt_name).toBe("dreamshaperXL.safetensors");
    expect(out["6"].inputs.text).toBe("a small round forest spirit");
    expect(out["7"].inputs.text).toBe("logo, watermark, text");
    expect(out["5"].inputs.width).toBe(512);
    expect(out["5"].inputs.height).toBe(512);
    expect(out["3"].inputs.seed).toBe(123456);
    expect(out["3"].inputs.steps).toBe(30);
    expect(out["3"].inputs.cfg).toBe(6.5);
    expect(out["3"].inputs.sampler_name).toBe("dpmpp_2m");
  });

  test("leaves non-placeholder values (wiring arrays, literals) untouched", () => {
    const out = injectRecipe(fixtureTemplate(), fullRecipe());
    expect(out["6"].inputs.clip).toEqual(["4", 1]);
    expect(out["5"].inputs.batch_size).toBe(1);
    expect(out["9"].inputs.images).toEqual(["8", 0]);
    expect(out["3"].class_type).toBe("KSampler");
  });

  test("does not mutate the input template", () => {
    const tpl = fixtureTemplate();
    injectRecipe(tpl, fullRecipe());
    expect(tpl["6"].inputs.text).toBe("%prompt%");
    expect(tpl["5"].inputs.width).toBe("%width%");
  });

  test("throws a clear error when a required field is missing", () => {
    const r = fullRecipe();
    delete r.prompt;
    expect(() => injectRecipe(fixtureTemplate(), r)).toThrow(/prompt/);
  });
});
