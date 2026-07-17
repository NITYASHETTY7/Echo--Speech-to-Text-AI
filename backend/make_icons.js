// Regenerate app icons from public/logo.svg → assets/icon.png + assets/icon.ico
// Usage:  node make_icons.js   (needs devDeps: sharp, png-to-ico)
const fs = require('fs');
const sharp = require('sharp');
const mod = require('png-to-ico');
const pngToIco = (typeof mod === 'function') ? mod : mod.default;

const svg = fs.readFileSync('public/logo.svg');
fs.mkdirSync('assets', { recursive: true });

(async () => {
  await sharp(svg, { density: 384 }).resize(512, 512).png().toFile('assets/icon.png');
  const bufs = [];
  for (const s of [16, 24, 32, 48, 64, 128, 256]) {
    bufs.push(await sharp(svg, { density: 384 }).resize(s, s).png().toBuffer());
  }
  fs.writeFileSync('assets/icon.ico', await pngToIco(bufs));
  console.log('Wrote assets/icon.png and assets/icon.ico');
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
