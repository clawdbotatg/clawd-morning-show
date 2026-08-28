// stage 4b worker: vgpu (headless WebGPU) renders the animated show
// background to <workdir>/bg.mp4 — scrolling floor grid, voice-reactive
// waveform + horizon glow, and a black stage panel with a glowing border
// wherever the avatar lands (the clips ship on pure black; the panel makes
// the square read as set design). Purely optional: 04b-bg.sh treats ANY
// failure here as "no bg" and 05-render falls back to the black frame.
//
// usage: node render_bg.mjs <workdir>
// env: INTRO_S (audio delay, lib.sh), FFMPEG (encoder/decoder path)
import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { init, effect, target } from "vgpu/node";

const WORK = process.argv[2];
if (!WORK) { console.error("usage: render_bg.mjs <workdir>"); process.exit(2); }
const FFMPEG = process.env.FFMPEG || "ffmpeg";
const INTRO_S = parseFloat(process.env.INTRO_S || "2");
const W = 1280, H = 720, FPS = 24; // 05 renders -r 24; match it

const plan = JSON.parse(readFileSync(join(WORK, "plan.json"), "utf8"));
const TOTAL = plan.total + 0.5; // headroom; 05 -t TOTAL trims exactly
const pip = plan.layout && plan.layout.pip;
const pipS = pip ? pip.start : -1, pipE = pip ? pip.end : -1;

// voice.norm.wav exists on a re-render; first pass has only voice.mp3.
// Levels are self-normalized to the 98th percentile, so either works.
const voice = ["voice.norm.wav", "voice.mp3"].map((f) => join(WORK, f)).find(existsSync);
if (!voice) { console.error("no voice audio in workdir"); process.exit(2); }

const pcm = execFileSync(FFMPEG, [
  "-v", "quiet", "-i", voice, "-ac", "1", "-ar", "48000", "-f", "f32le", "-",
], { maxBuffer: 1 << 28 });
const samples = new Float32Array(pcm.buffer, pcm.byteOffset, pcm.byteLength / 4);
const frames = Math.ceil(TOTAL * FPS);
const win = Math.floor(48000 / FPS);
const raw = new Float32Array(frames);
for (let f = 0; f < frames; f++) {
  const t = f / FPS - INTRO_S; // 05 delays the audio by INTRO_S
  if (t < 0) continue;
  const s0 = Math.floor(t * 48000);
  let acc = 0;
  for (let i = s0; i < Math.min(s0 + win, samples.length); i++) acc += samples[i] * samples[i];
  raw[f] = Math.sqrt(acc / win);
}
const peak = [...raw].sort((a, b) => b - a)[Math.floor(frames * 0.02)] || 1;
const levels = new Float32Array(frames);
let sm = 0;
for (let f = 0; f < frames; f++) {
  const v = Math.min(raw[f] / peak, 1);
  sm = v > sm ? sm + (v - sm) * 0.55 : sm + (v - sm) * 0.12; // fast attack, slow decay
  levels[f] = sm;
}

// avatar geometry, matching 05-render's overlays exactly
const rectFull = [360 / W, 160 / H, 560 / W, 560 / H];
const rectPip = [940 / W, 360 / H, 300 / W, 300 / H];

// ---- price sparklines (fetch_prices.mjs → prices.json; all optional) ----
// three fixed slots in the top corners, clear of the centered title and the
// story card zone (y≥140): btc / eth stacked left, $CLAWD featured right.
// Series are normalized to 0..1 here; a missing/flat series draws nothing.
const SPARK_RECTS = [
  [36 / W, 28 / H, 300 / W, 56 / H],   // btc
  [36 / W, 84 / H, 300 / W, 112 / H],  // eth
  [980 / W, 28 / H, 1244 / W, 88 / H], // $CLAWD (x0,y0,x1,y1)
];
const sparkFlags = [0, 0, 0, 0];
const sparkData = new Float32Array(144); // 3 series × 48 samples
try {
  const prices = JSON.parse(readFileSync(join(WORK, "prices.json"), "utf8"));
  ["btc", "eth", "clawd"].forEach((k, s) => {
    const ser = prices[k] && prices[k].series;
    if (!ser || ser.length !== 48) return;
    const mn = Math.min(...ser), mx = Math.max(...ser);
    if (!(mx > mn)) return;
    const pad = (mx - mn) * 0.12;
    for (let i = 0; i < 48; i++) sparkData[s * 48 + i] = (ser[i] - mn + pad) / (mx - mn + 2 * pad);
    sparkFlags[s] = 1;
  });
} catch { /* no prices.json — no sparklines */ }
const sparkVecs = () => Array.from({ length: 36 }, (_, i) => [sparkData[i * 4], sparkData[i * 4 + 1], sparkData[i * 4 + 2], sparkData[i * 4 + 3]]);

const shader = /* wgsl */ `
  struct Params {
    time: f32, level: f32, aspect: f32, pad: f32,
    rect: vec4f,
    sparkflags: vec4f,
    hist: array<vec4f, 16>,
    sparks: array<vec4f, 36>,
  }
  @group(0) @binding(0) var<uniform> params: Params;

  fn hash(p: vec2f) -> f32 {
    return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453);
  }

  fn sdRoundRect(p: vec2f, half: vec2f, r: f32) -> f32 {
    let q = abs(p) - half + vec2f(r);
    return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
  }

  fn sparkRect(s: i32) -> vec4f { // x0,y0,x1,y1 — mirror of SPARK_RECTS in JS
    if (s == 0) { return vec4f(${SPARK_RECTS[0].join(", ")}); }
    if (s == 1) { return vec4f(${SPARK_RECTS[1].join(", ")}); }
    return vec4f(${SPARK_RECTS[2].join(", ")});
  }

  fn sparkColor(s: i32) -> vec3f {
    if (s == 0) { return vec3f(0.85, 0.52, 0.12); } // btc amber
    if (s == 1) { return vec3f(0.42, 0.52, 0.88); } // eth blue-violet
    return vec3f(0.22, 0.85, 0.45);                 // $CLAWD house green
  }

  @fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
    let px = vec2f(uv.x * params.aspect, uv.y);
    let lvl = params.level;

    var col = mix(vec3f(0.010, 0.016, 0.028), vec3f(0.020, 0.034, 0.052),
                  uv.y + 0.06 * sin(params.time * 0.13 + uv.x * 2.0));

    let hy = 0.585;
    if (uv.y > hy) {
      let d = (uv.y - hy) + 0.0001;
      let persp = 0.055 / d;
      let gx = abs(fract((uv.x - 0.5) * persp * 2.4) - 0.5);
      let gz = abs(fract(persp * 1.4 - params.time * 0.55) - 0.5);
      let lw = 0.03 + d * 0.05;
      let line = smoothstep(lw, lw * 0.2, min(gx, gz)) * smoothstep(0.0, 0.10, d);
      col += vec3f(0.05, 0.26, 0.15) * line * (0.5 + 0.6 * lvl);
      col += vec3f(0.10, 0.45, 0.25) * exp(-d * 220.0) * (0.6 + 1.2 * lvl);
      col += vec3f(0.04, 0.20, 0.11) * exp(-d * 40.0) * (0.3 + 0.7 * lvl);
    } else {
      let sp = uv * vec2f(96.0, 54.0);
      let cell = floor(sp);
      let star = step(0.992, hash(cell));
      let pos = vec2f(hash(cell + 1.3), hash(cell + 2.7));
      let dd = length((fract(sp) - pos) * vec2f(1.0, 0.5625));
      let tw = 0.5 + 0.5 * sin(params.time * 1.7 + hash(cell + 7.0) * 40.0);
      col += vec3f(0.35, 0.5, 0.45) * star * tw * smoothstep(0.12, 0.0, dd) * 0.6 * smoothstep(hy, 0.1, uv.y);
    }

    // voice waveform ribbon. The title ("clawd morning show", y 34..80) and
    // date (y 96..120) drawtext over this band; the ribbon is dim enough to
    // read as a scope glow under the header — checked on frames, not guessed.
    // Tapered to the center band so the corner sparklines own the corners.
    let wy = 0.085;
    let idx = clamp(i32(uv.x * 63.0), 0, 63);
    let h = params.hist[idx / 4][idx % 4];
    let amp = 0.003 + h * 0.075;
    let dy = abs(uv.y - wy);
    let taper = smoothstep(0.25, 0.32, uv.x) * (1.0 - smoothstep(0.68, 0.75, uv.x));
    let wave = smoothstep(amp, amp * 0.15, dy) * taper;
    col += vec3f(0.10, 0.42, 0.24) * wave * (0.15 + 0.85 * h) * 0.55;
    col += vec3f(0.05, 0.20, 0.12) * smoothstep(0.09, 0.0, dy) * (0.05 + 0.25 * h) * 0.55 * taper;

    // price sparklines (btc / eth / $CLAWD): glowing polyline + soft area
    // fill in fixed corner rects; the last point pulses with the voice.
    for (var s = 0; s < 3; s++) {
      if (params.sparkflags[s] < 0.5) { continue; }
      let r = sparkRect(s);
      let gx0 = r.x; let gy0 = r.y; let gx1 = r.z; let gy1 = r.w;
      if (uv.x < gx0 - 0.004 || uv.x > gx1 + 0.008 || uv.y < gy0 - 0.02 || uv.y > gy1 + 0.02) { continue; }
      let tx = clamp((uv.x - gx0) / (gx1 - gx0), 0.0, 1.0);
      let fi = tx * 47.0;
      let i0 = clamp(i32(fi), 0, 46);
      let fr = fi - f32(i0);
      let base = s * 48;
      let a = params.sparks[(base + i0) / 4][(base + i0) % 4];
      let b = params.sparks[(base + i0 + 1) / 4][(base + i0 + 1) % 4];
      let v = mix(a, b, fr);
      let ly = gy1 - v * (gy1 - gy0);
      let sc = sparkColor(s);
      let d = abs(uv.y - ly);
      col += sc * smoothstep(0.005, 0.0008, d);                       // line
      col += sc * exp(-d * 220.0) * 0.30;                             // glow
      if (uv.y > ly && uv.y < gy1 + 0.01) {                           // area fill
        col += sc * 0.05 * (1.0 - (uv.y - ly) / (gy1 - gy0 + 0.01));
      }
      let lastV = params.sparks[(base + 47) / 4][(base + 47) % 4];
      let pe = length(vec2f((uv.x - gx1) * params.aspect, uv.y - (gy1 - lastV * (gy1 - gy0))));
      col += sc * exp(-pe * 420.0) * (0.5 + 0.8 * lvl);               // live dot
    }

    // avatar stage panel: pure black interior + glowing border
    let rc = params.rect;
    let cpx = vec2f((rc.x + rc.z * 0.5) * params.aspect, rc.y + rc.w * 0.5);
    let half = vec2f(rc.z * 0.5 * params.aspect, rc.w * 0.5);
    let sd = sdRoundRect(px - cpx, half, 0.02);
    let border = exp(-abs(sd) * 130.0) * (0.35 + 0.65 * lvl);
    col += vec3f(0.07, 0.34, 0.19) * border;
    col = mix(col, vec3f(0.0), smoothstep(0.004, -0.002, sd));

    col *= 0.94 + 0.06 * sin(uv.y * 720.0 * 3.14159);
    let v = uv - 0.5;
    col *= 1.0 - dot(v, v) * 0.55;

    return vec4f(col, 1.0);
  }
`;

const gpu = await init({ adapter: "hardware" });
const t = target(gpu, { size: [W, H] });
const hist = new Float32Array(64);
const histVecs = () => Array.from({ length: 16 }, (_, i) => [hist[i * 4], hist[i * 4 + 1], hist[i * 4 + 2], hist[i * 4 + 3]]);
const fx = effect(gpu, shader, {
  set: { params: { time: 0, level: 0, aspect: W / H, pad: 0, rect: rectFull, sparkflags: sparkFlags, hist: histVecs(), sparks: sparkVecs() } },
});

const ff = spawn(FFMPEG, [
  "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", `${W}x${H}`,
  "-r", String(FPS), "-i", "-",
  "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", join(WORK, "bg.mp4"),
], { stdio: ["pipe", "ignore", "pipe"] });
let ffErr = "";
ff.stderr.on("data", (d) => (ffErr += d));

const t0 = Date.now();
for (let f = 0; f < frames; f++) {
  const time = f / FPS;
  hist.copyWithin(0, 1);
  hist[63] = levels[f];
  const inPip = pipS >= 0 && time >= pipS && time < pipE;
  fx.set({ params: { time, level: levels[f], rect: inPip ? rectPip : rectFull, hist: histVecs() } }); // sparks are static — set once at init
  fx.draw(t);
  const pixels = await t.read();
  if (!ff.stdin.write(Buffer.from(pixels))) {
    await new Promise((r) => ff.stdin.once("drain", r));
  }
}
ff.stdin.end();
const code = await new Promise((r) => ff.on("close", r));
await gpu.settled();
gpu.dispose();
if (code !== 0) { console.error("bg encode failed:", ffErr.slice(-500)); process.exit(1); }
const dt = (Date.now() - t0) / 1000;
console.log(`bg: ${frames} frames @ ${W}x${H} in ${dt.toFixed(1)}s -> bg.mp4`);
