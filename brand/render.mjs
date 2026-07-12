#!/usr/bin/env node
// Wickelfinder — SVG -> PNG Renderer
// Rendert die Brand-SVGs zu exakt dimensionierten PNGs.
// Lokal ausführen:  npx --yes sharp-cli ...  ODER:  node render.mjs   (mit installiertem sharp)
// Empfohlen:        npx --yes --package=sharp node render.mjs
//
// Kein rsvg/inkscape/imagemagick nötig — sharp (libvips) rendert SVG nativ.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import sharp from "sharp";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "render");

// [Quelle, Ziel, Größe, quadratisch-transparent?]
const jobs = [
  ["app-icon-foreground.svg", "render/foreground.png", 1024],
  ["app-icon-background.svg", "render/background.png", 1024],
  ["app-icon-monochrome.svg", "render/monochrome.png", 1024],
  // Vorschau = Foreground auf Background zusammengesetzt (App-Icon-Look)
];

async function renderOne(src, out, size) {
  const svg = readFileSync(join(here, src));
  await sharp(svg, { density: 384 })
    .resize(size, size, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(join(here, out));
  console.log(`✓ ${out}  (${size}×${size})`);
}

async function renderPreview() {
  // App-Icon-Vorschau: Foreground über Background legen (wie das gerundete Launcher-Icon)
  const bg = await sharp(readFileSync(join(here, "app-icon-background.svg")), { density: 384 })
    .resize(1024, 1024).png().toBuffer();
  const fg = await sharp(readFileSync(join(here, "app-icon-foreground.svg")), { density: 384 })
    .resize(1024, 1024, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png().toBuffer();
  await sharp(bg)
    .composite([{ input: fg }])
    .png({ compressionLevel: 9 })
    .toFile(join(outDir, "preview.png"));
  console.log(`✓ render/preview.png  (1024×1024, FG über BG)`);
}

for (const [src, out, size] of jobs) {
  await renderOne(src, out, size);
}
await renderPreview();
console.log("Fertig.");
