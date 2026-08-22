#!/usr/bin/env node
// Run clawd-video-chat's OWN avatar code to decide which clip shows when.
//
// We don't reimplement the rig's `clawdVid` state machine — we cut it out of
// the vendored assets/rig/index.html and execute it here against fake <video>
// elements that fire `playing`/`ended` on the real clip durations, feeding it
// the same events the live page gets (each TTS chunk's audio.onplay ->
// chatting(), queue drained -> idle(true) after 250ms). The TTS chunking
// (sentence regexes + max chunk) is lifted from the same file and run with
// the same loop. Every visible cut (the overlay "snap") is recorded.
//
// usage: plan_avatar.mjs rig.html words.json script.txt intro_s outro_s mouth_lag_s audio_s \
//          d_idle1 d_idle2 d_chat seed plan.json avatar.filter
// mouth_lag_s: the chatting clip's mouth starts moving that long after its
// first frame, so every chatting() cut is fired that much BEFORE the audio
// it belongs to (audio itself is delayed by intro+lag in the render).
import fs from "node:fs";

const a = process.argv.slice(2);
if (a.length !== 13) { console.error("usage: see header"); process.exit(2); }
const [rigHtml, wordsJson, scriptTxt, introS, outroS, lagS, audioS, dI1, dI2, dCh, seed, outPlan, outFilter] = a;
const INTRO = +introS, OUTRO = +outroS, LAG = +lagS, AUDIO = +audioS;
const AUDIO_AT = INTRO + LAG;   // when the voice actually starts in the show
const DUR = { "clawdassets/idle_1.mp4": +dI1, "clawdassets/idle_2.mp4": +dI2, "clawdassets/chatting_1.mp4": +dCh };
const html = fs.readFileSync(rigHtml, "utf8");

// ── 1. lift the rig's code ───────────────────────────────────────────────────
const s0 = html.indexOf("const clawdVid = (() => {");
if (s0 < 0) throw new Error("rig: clawdVid block not found");
const endMark = "\n})();";
const s1 = html.indexOf(endMark, s0);
const clawdVidSrc = html.slice(s0, s1 + endMark.length);

const lift = (name) => {
  const m = html.match(new RegExp(`^\\s*const ${name}\\s*=\\s*(.+?);\\s*(?://.*)?$`, "m"));
  if (!m) throw new Error(`rig: ${name} not found`);
  return new Function(`return (${m[1]});`)();
};
const TTS_FIRST_RE = lift("_TTS_FIRST_RE");
const TTS_SENT_RE = lift("_TTS_SENT_RE");
const TTS_MAX_CHUNK = lift("_TTS_MAX_CHUNK");

// ── 2. TTS chunking, the rig's loop verbatim (stream drained, then final) ──
function chunkText(fullText) {
  const out = [];
  let upTo = 0, idx = 0;
  for (;;) {
    const newPart = fullText.slice(upTo);
    if (!newPart) break;
    const re = idx === 0 ? TTS_FIRST_RE : TTS_SENT_RE;
    const m = newPart.match(re);
    if (m) { out.push(m[1]); upTo += m[0].length; idx++; continue; }
    if (newPart.length >= TTS_MAX_CHUNK) {
      const cut = newPart.lastIndexOf(" ", TTS_MAX_CHUNK);
      const split = cut > 40 ? cut : TTS_MAX_CHUNK;
      out.push(newPart.slice(0, split)); upTo += split; idx++; continue;
    }
    out.push(newPart); break;   // isFinal: remainder is the last chunk
  }
  return out.map(t => t.trim()).filter(Boolean);
}

const script = fs.readFileSync(scriptTxt, "utf8").trim();
const words = JSON.parse(fs.readFileSync(wordsJson, "utf8")).words;
const chunks = chunkText(script);
// map chunks -> word timings by cumulative word count (chunk cuts are on whitespace)
const chunkTimes = [];
let wi = 0;
for (const text of chunks) {
  const n = text.split(/\s+/).length;
  if (wi + n > words.length) throw new Error(`chunk/word mismatch at chunk ${chunkTimes.length}`);
  chunkTimes.push({ text, start: words[wi].start + AUDIO_AT });   // when this chunk is heard
  wi += n;
}
if (wi !== words.length) throw new Error(`chunk words ${wi} != alignment words ${words.length}`);
const speechEnd = AUDIO_AT + AUDIO;
const TOTAL = speechEnd + OUTRO;

// ── 3. discrete-event clock + seeded random ─────────────────────────────────
let now = 0, seq = 0;
const timers = [];
const schedule = (t, fn) => { const id = ++seq; timers.push({ t, id, fn }); return id; };
const cancel = (id) => { const i = timers.findIndex(x => x.id === id); if (i >= 0) timers.splice(i, 1); };
const runUntil = (T) => {
  for (;;) {
    timers.sort((x, y) => x.t - y.t || x.id - y.id);
    const e = timers[0];
    if (!e || e.t > T) break;
    timers.shift(); now = e.t; e.fn();
  }
  now = T;
};
let h = 1779033703 ^ [...String(seed)].reduce((acc, c) => Math.imul(acc ^ c.charCodeAt(0), 3432918353) >>> 0, 0);
const rng = () => { h = Math.imul(h ^ (h >>> 15), 2246822507); h = Math.imul(h ^ (h >>> 13), 3266489909); return ((h ^= h >>> 16) >>> 0) / 4294967296; };

// ── 4. just enough DOM for clawdVid ─────────────────────────────────────────
const cuts = [];
class El {
  constructor(tag) { this.tag = tag; this.children = []; this.parentNode = null; this.style = {}; this.id = ""; this.offsetHeight = 624; this._cls = new Set(); this._ls = {}; this.className = ""; }
  get classList() { const el = this; return {
    add: (...c) => { c.forEach(x => el._cls.add(x)); if (c.includes("snap") && el._isOverlayOf === "clawdVideo") cuts.push({ t: now, clip: el.src }); },
    remove: (...c) => c.forEach(x => el._cls.delete(x)), contains: (c) => el._cls.has(c) }; }
  appendChild(c) { c.parentNode = this; this.children.push(c); return c; }
  insertBefore(n, ref) { n.parentNode = this; const i = this.children.indexOf(ref); this.children.splice(i < 0 ? this.children.length : i, 0, n); return n; }
  addEventListener(ev, fn, o) { (this._ls[ev] ||= []).push({ fn, once: !!(o && o.once) }); }
  removeEventListener(ev, fn) { if (this._ls[ev]) this._ls[ev] = this._ls[ev].filter(l => l.fn !== fn); }
  dispatch(ev) { for (const l of (this._ls[ev] || []).slice()) { if (l.once) this.removeEventListener(ev, l.fn); l.fn({ type: ev, target: this }); } }
  removeAttribute(n) { if (n === "src") this._src = ""; if (n === "id") this.id = ""; }
}
class Video extends El {
  constructor() { super("video"); this._src = ""; this.paused = true; this.loop = false; this._t0 = 0; this._ct = 0; this._endT = null; this.videoWidth = 624; this.videoHeight = 624; }
  get src() { return this._src; }
  set src(v) { this._src = v; this.paused = true; this._ct = 0; if (this._endT) { cancel(this._endT); this._endT = null; } }
  get currentTime() { return this.paused ? this._ct : now - this._t0; }
  set currentTime(v) { this._t0 = now - v; this._ct = v; }
  play() {
    const src = this._src;
    if (this._endT) { cancel(this._endT); this._endT = null; }
    schedule(now, () => {
      if (this._src !== src) return;
      this.paused = false; this._t0 = now - this._ct; this.dispatch("playing");
      const d = DUR[src]; if (d == null) throw new Error("unknown clip " + src);
      if (!this.loop) this._endT = schedule(this._t0 + d, () => { this.paused = true; this._ct = d; this._endT = null; this.dispatch("ended"); });
    });
    return Promise.resolve();
  }
  cloneNode() { const v = new Video(); v._src = this._src; v.id = this.id; v._isOverlayOf = this.id; return v; }
}
const byId = {};
for (const id of ["clawdVideo", "clawdVideoMin"]) {
  const v = new Video(); v.id = id; v.src = "clawdassets/idle_1.mp4";   // the page's <video autoplay src=idle_1>
  const holder = new El("div"); holder.appendChild(v);
  byId[id] = v;
}
if (byId.clawdVideo.src) cuts.push({ t: 0, clip: byId.clawdVideo.src });
Object.values(byId).forEach(v => v.play());   // autoplay
const document = { getElementById: (id) => byId[id], createElement: (t) => new El(t) };
const fakeMath = Object.create(Math, { random: { value: rng } });
const fakeDate = { now: () => Math.round(now * 1000) };
const clawdVid = new Function("document", "setTimeout", "clearTimeout", "requestAnimationFrame", "Date", "Math", "console",
  clawdVidSrc + "\nreturn clawdVid;")(
  document, (fn, ms) => schedule(now + (ms || 0) / 1000, fn), cancel, (fn) => schedule(now, fn), fakeDate, fakeMath,
  { log() {}, warn() {}, error() {} });

// ── 5. feed it the show's events, exactly as the live page would ────────────
for (const c of chunkTimes) schedule(c.start - LAG, () => clawdVid.chatting(script));   // audio.onplay per chunk, led by the mouth lag
schedule(speechEnd, () => schedule(now + 0.25, () => clawdVid.idle(true)));       // drain -> idle after 250ms
runUntil(TOTAL);

// ── 6. cuts -> segments -> filtergraph ──────────────────────────────────────
const segs = [];
for (let i = 0; i < cuts.length; i++) {
  const end = i + 1 < cuts.length ? cuts[i + 1].t : TOTAL;
  const dur = end - cuts[i].t;
  if (dur > 1e-3) segs.push({ clip: cuts[i].clip.replace("clawdassets/", "").replace(".mp4", ""), dur: +dur.toFixed(4) });
}
const idx = { idle_1: 2, idle_2: 3, chatting_1: 4 };
const uses = Object.fromEntries(Object.keys(idx).map(k => [k, segs.map((s, i) => s.clip === k ? i : -1).filter(i => i >= 0)]));
const lines = [];
for (const [clip, i] of Object.entries(idx)) {
  const n = uses[clip].length; if (!n) continue;
  lines.push(n > 1 ? `[${i}:v]split=${n}` + uses[clip].map((_, j) => `[${clip}_${j}]`).join("") : `[${i}:v]null[${clip}_0]`);
}
segs.forEach((s, k) => lines.push(`[${s.clip}_${uses[s.clip].indexOf(k)}]trim=duration=${s.dur},setpts=PTS-STARTPTS[seg${k}]`));
lines.push(segs.map((_, k) => `[seg${k}]`).join("") + `concat=n=${segs.length}:v=1:a=0[avatar]`);
fs.writeFileSync(outFilter, lines.join(";\n"));

const captions = chunkTimes.map((c, i) => ({ text: c.text, start: +c.start.toFixed(3),
  end: +(i + 1 < chunkTimes.length ? chunkTimes[i + 1].start : speechEnd).toFixed(3) }));
fs.writeFileSync(outPlan, JSON.stringify({ total: +TOTAL.toFixed(3), speechEnd, rig: fs.existsSync(rigHtml.replace(/index\.html$/, "SOURCE")) ? fs.readFileSync(rigHtml.replace(/index\.html$/, "SOURCE"), "utf8").trim() : null,
  captions, segments: segs }, null, 1));
const chat = segs.filter(s => s.clip === "chatting_1").reduce((x, s) => x + s.dur, 0);
console.error(`rig plan: ${captions.length} chunks, ${segs.length} segments, chatting ${chat.toFixed(0)}s of ${TOTAL.toFixed(0)}s`);
