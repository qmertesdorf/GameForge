"""THROWAWAY — opaque-gen -> clean-alpha token cutout via rembg.
Removes the background, autocrops to the subject, centers it in a square with a
transparent margin so the token is one complete subject with clean edges
(satisfies the asset-skill 'token framing & crop integrity' rule).
Usage: python _cutout.py <input.png> <output.png> [margin_frac=0.10]
"""
import sys
from rembg import remove
from PIL import Image

inp, outp = sys.argv[1], sys.argv[2]
margin = float(sys.argv[3]) if len(sys.argv) > 3 else 0.10

img = Image.open(inp).convert("RGBA")
out = remove(img)                      # U2Net background removal -> alpha
bbox = out.getbbox()                   # tight bounds of non-transparent pixels
if bbox:
    out = out.crop(bbox)
w, h = out.size
side = max(w, h)
pad = int(side * margin)
canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
canvas.paste(out, ((canvas.width - w) // 2, (canvas.height - h) // 2), out)
canvas.save(outp)
# Report edge cleanliness: count opaque pixels touching any border (should be ~0).
px = canvas.load()
W, H = canvas.size
edge = 0
for x in range(W):
    if px[x, 0][3] > 8: edge += 1
    if px[x, H - 1][3] > 8: edge += 1
for y in range(H):
    if px[0, y][3] > 8: edge += 1
    if px[W - 1, y][3] > 8: edge += 1
print(f"WROTE {outp} size={canvas.size} opaque_border_px={edge}")
