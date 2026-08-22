#!/usr/bin/env node
// Story stage cards: for each story segment, the theme title + the 3 tweets
// that carry it, rendered as a dark X-style card stack and screenshotted
// with the machine's cached Playwright Chromium (no network — the digest
// has no avatar images, so avatars are initial-letter discs).
// usage: render_cards.mjs stories.json script.json outdir   -> outdir/story-<n>.png
import fs from "node:fs";
import path from "node:path";
import { readdirSync, existsSync } from "node:fs";
import { chromium } from "playwright-core";

const [storiesJson, scriptJson, outDir] = process.argv.slice(2);
if (!outDir) { console.error("usage: render_cards.mjs stories.json script.json outdir"); process.exit(2); }
const stories = JSON.parse(fs.readFileSync(storiesJson, "utf8"));
const segs = JSON.parse(fs.readFileSync(scriptJson, "utf8")).segments.filter(s => s.kind === "story");
fs.mkdirSync(outDir, { recursive: true });

// same resolution as clawd-harness tools/uiprobe.mjs: newest cached headless shell
function findChromium() {
  const cache = path.join(process.env.HOME, "Library/Caches/ms-playwright");
  if (!existsSync(cache)) return null;
  for (const prefix of ["chromium_headless_shell-", "chromium-"]) {
    const dirs = readdirSync(cache).filter(d => d.startsWith(prefix)).sort().reverse();
    for (const d of dirs) {
      for (const rel of ["chrome-mac/headless_shell", "chrome-mac-arm64/headless_shell",
                         "chrome-mac/Chromium.app/Contents/MacOS/Chromium", "chrome-mac-arm64/Chromium.app/Contents/MacOS/Chromium"]) {
        const p = path.join(cache, d, rel); if (existsSync(p)) return p;
      }
    }
  }
  return null;
}
const exec = process.env.CHROMIUM || findChromium();
if (!exec) { console.error("render_cards: no cached playwright chromium (npx playwright install chromium)"); process.exit(2); }

const W = 860, H = 420;
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const fmtN = n => n >= 1000 ? (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "k" : String(n);
const hue = h => [...h].reduce((a, c) => (a * 31 + c.charCodeAt(0)) % 360, 7);

function pickTweets(theme, text) {
  const mentioned = new Set((text.toLowerCase().match(/[a-z0-9_]+/g) || []));
  return [...theme.tweets]
    .map(t => ({ ...t, score: (t.likes + t.rts) + (mentioned.has(t.handle.toLowerCase()) ? 1e6 : 0) }))
    .sort((a, b) => b.score - a.score)
    .filter(t => t.text)
    .slice(0, 3);
}

function page(theme, tweets, n, total) {
  const cards = tweets.map(t => `
    <div class="tw">
      <div class="av" style="background:hsl(${hue(t.handle)} 55% 42%)">${esc(t.handle[0].toUpperCase())}</div>
      <div class="body">
        <div class="head"><span class="handle">@${esc(t.handle)}</span>
          <span class="meta">${[t.likes && `♥ ${fmtN(t.likes)}`, t.rts && `🔁 ${fmtN(t.rts)}`].filter(Boolean).join(" · ")}</span></div>
        <div class="text">${esc(t.text)}</div>
      </div>
    </div>`).join("");
  return `<!doctype html><meta charset="utf-8"><style>
    * { box-sizing: border-box; margin: 0; }
    body { width: ${W}px; background: #000; color: #e8e8ea; overflow: hidden;
           font: 18px/1.32 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    .stage { width: ${W}px; max-height: ${H}px; padding: 14px 18px 16px; display: flex; flex-direction: column; gap: 10px;
             background: #0a0f0a; border: 1px solid #1e4527; border-radius: 14px; }
    .title { display: flex; align-items: baseline; gap: 12px; padding: 0 2px 6px; border-bottom: 1px solid #1e4527; }
    .title h2 { font: 700 26px/1.15 Menlo, Monaco, monospace; color: #66ff66; letter-spacing: -0.01em; flex: 1; }
    .title .n { font: 13px Menlo, Monaco, monospace; color: #33aa44; white-space: nowrap; }
    .tw { display: flex; gap: 12px; padding: 10px 12px; background: #121a14; border: 1px solid #1c2a1f; border-radius: 12px; }
    .av { width: 44px; height: 44px; border-radius: 50%; flex: none; display: grid; place-items: center;
          font: 700 20px -apple-system, sans-serif; color: #fff; }
    .body { min-width: 0; flex: 1; }
    .head { display: flex; justify-content: space-between; gap: 10px; font-size: 16px; margin-bottom: 3px; }
    .handle { color: #9ad0a8; font-weight: 700; }
    .meta { color: #6f8f77; white-space: nowrap; }
    .text { color: #e8e8ea; font-size: 18px; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
  </style><body><div class="stage">
    <div class="title"><h2>${esc(theme.title)}</h2><span class="n">story ${n} of ${total} · gmsers.com</span></div>
    ${cards}
  </div></body>`;
}

const browser = await chromium.launch({ executablePath: exec });
try {
  const pg = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  let i = 0;
  for (const s of segs) {
    const theme = stories.themes.find(t => t.title === s.theme);
    if (!theme) throw new Error(`story theme not in stories.json: ${s.theme}`);
    const tweets = pickTweets(theme, s.text);
    await pg.setContent(page(theme, tweets, i + 1, segs.length));
    const out = path.join(outDir, `story-${i}.png`);
    await pg.locator(".stage").screenshot({ path: out });   // content-sized, ≤ H
    console.error(`card ${i}: ${theme.title} (${tweets.map(t => "@" + t.handle).join(" ")}) -> ${out}`);
    i++;
  }
} finally { await browser.close(); }
