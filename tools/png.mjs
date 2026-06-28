import { inflateSync, deflateSync } from "node:zlib";

// Minimal, dependency-free PNG decoder for the asset-QC gate. ComfyUI's SaveImage
// emits 8-bit, non-interlaced PNGs — RGB (colour type 2) for opaque sdxl and RGBA
// (type 6) for LayerDiffuse. We support exactly those; anything else throws loudly
// (attributable) rather than decoding to silent garbage. Pure: Buffer in, pixels
// out — no network, no disk, no GPU. Keeping it in-process is the whole point:
// comfy.mjs stays CI-mockable and GPU-free.

const SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

// Decode a PNG Buffer → { width, height, channels (3|4), data: Uint8Array }.
// `data` is row-major, `channels` bytes per pixel, 0..255.
export function decodePng(buf) {
  if (!Buffer.isBuffer(buf)) buf = Buffer.from(buf);
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIG)) {
    throw new Error("png: not a PNG (bad signature)");
  }
  let off = 8;
  let ihdr = null;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString("ascii", off + 4, off + 8);
    const dataStart = off + 8;
    const dataEnd = dataStart + len;
    if (dataEnd > buf.length) throw new Error(`png: truncated chunk ${type}`);
    if (type === "IHDR") {
      ihdr = {
        width: buf.readUInt32BE(dataStart),
        height: buf.readUInt32BE(dataStart + 4),
        bitDepth: buf[dataStart + 8],
        colorType: buf[dataStart + 9],
        interlace: buf[dataStart + 12]
      };
    } else if (type === "IDAT") {
      idat.push(buf.subarray(dataStart, dataEnd));
    } else if (type === "IEND") {
      break;
    }
    off = dataEnd + 4; // skip the 4-byte CRC
  }
  if (!ihdr) throw new Error("png: missing IHDR");
  if (ihdr.bitDepth !== 8) throw new Error(`png: unsupported bit depth ${ihdr.bitDepth} (only 8 supported)`);
  if (ihdr.interlace !== 0) throw new Error("png: interlaced PNGs are not supported");
  const channels = ihdr.colorType === 2 ? 3 : ihdr.colorType === 6 ? 4 : 0;
  if (!channels) throw new Error(`png: unsupported colour type ${ihdr.colorType} (only 2=RGB, 6=RGBA supported)`);

  const { width, height } = ihdr;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  if (raw.length < (stride + 1) * height) throw new Error("png: inflated data too short for declared dimensions");

  const out = new Uint8Array(stride * height);
  let prev = new Uint8Array(stride); // the row above (zeros for row 0)
  let rp = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[rp++];
    const cur = out.subarray(y * stride, y * stride + stride);
    for (let i = 0; i < stride; i++) {
      const x = raw[rp++];
      const a = i >= channels ? cur[i - channels] : 0; // left
      const b = prev[i];                                // up
      const c = i >= channels ? prev[i - channels] : 0; // up-left
      let v;
      switch (filter) {
        case 0: v = x; break;
        case 1: v = x + a; break;
        case 2: v = x + b; break;
        case 3: v = x + ((a + b) >> 1); break;
        case 4: v = x + paeth(a, b, c); break;
        default: throw new Error(`png: unknown filter type ${filter} on row ${y}`);
      }
      cur[i] = v & 255;
    }
    prev = cur;
  }
  return { width, height, channels, data: out };
}

// --- Encoder -------------------------------------------------------------
// Minimal filter-None PNG encoder: enough to write the pixelize output (small
// native-res sprites/backgrounds). 8-bit, non-interlaced, RGB (type 2) or RGBA
// (type 6) — the mirror of decodePng's supported set. Pure: pixels in, Buffer out.
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; }
  return t;
})();
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (~c) >>> 0;
}
function pngChunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

// Encode raw row-major pixels → PNG Buffer. channels: 3 (RGB) or 4 (RGBA).
export function encodePng(width, height, channels, data) {
  if (channels !== 3 && channels !== 4) throw new Error(`png: encode supports 3 or 4 channels, got ${channels}`);
  const stride = width * channels;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: None
    Buffer.from(data.subarray(y * stride, y * stride + stride)).copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([SIG, pngChunk("IHDR", ihdr), pngChunk("IDAT", deflateSync(raw)), pngChunk("IEND", Buffer.alloc(0))]);
}
