// stage 4b helper: 24h price series for the set's sparklines — btc + eth
// (CoinGecko, keyless) and $CLAWD on Base (GeckoTerminal, keyless; pool
// discovered by deepest reserve, hardcoded fallback). Writes:
//   <workdir>/prices.json          {btc:{series,label}, eth:…, clawd:…}
//   <workdir>/tick-{btc,eth,clawd}.txt   label text for the drawtext pass
// PURELY OPTIONAL: any coin that fails is simply omitted; exit is always 0
// unless the workdir arg is missing. 10s cap per request.
import { rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const WORK = process.argv[2];
if (!WORK) { console.error("usage: fetch_prices.mjs <workdir>"); process.exit(2); }
// clear stale outputs so a coin that fails today never wears yesterday's label
for (const f of ["prices.json", "tick-btc.txt", "tick-eth.txt", "tick-clawd.txt"]) {
  rmSync(join(WORK, f), { force: true });
}

const CLAWD_TOKEN = "0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07"; // token.clawdbotatg.eth.limo
const CLAWD_POOL_FALLBACK = "0x9fd58e73d8047cb14ac540acd141d3fc1a41fb6252d674b730faf62fe24aa8ce";

async function get(url, retried = false) {
  const r = await fetch(url, {
    signal: AbortSignal.timeout(10000),
    headers: { accept: "application/json", "user-agent": "clawd-morning-show/1.0" },
  });
  if (r.status === 429 && !retried) { // CoinGecko free tier burst limit
    await new Promise((res) => setTimeout(res, 20000));
    return get(url, true);
  }
  if (!r.ok) throw new Error(`${r.status} ${url}`);
  return r.json();
}

function fmtUsd(v) {
  if (v >= 10000) return `$${(v / 1000).toFixed(1)}k`;
  if (v >= 1000) return `$${Math.round(v).toLocaleString("en-US")}`;
  if (v >= 1) return `$${v.toFixed(2)}`;
  // micro-cap: keep 2 sig figs ($0.0000086)
  const d = Math.max(2, 1 - Math.floor(Math.log10(v)) + 1);
  return `$${v.toFixed(Math.min(d, 10))}`;
}

function pack(name, points) { // points: [[ts, price], …] any order/length
  const pts = points.filter((p) => p && isFinite(p[1]) && p[1] > 0)
    .sort((a, b) => a[0] - b[0]);
  if (pts.length < 8) throw new Error(`${name}: only ${pts.length} points`);
  // resample to 48 evenly spaced samples across the window
  const series = Array.from({ length: 48 }, (_, i) => {
    const x = (i / 47) * (pts.length - 1);
    const j = Math.min(Math.floor(x), pts.length - 2);
    const f = x - j;
    return pts[j][1] * (1 - f) + pts[j + 1][1] * f;
  });
  const last = series[47], first = series[0];
  const chg = ((last / first) - 1) * 100;
  const label = `${name} ${fmtUsd(last)} ${chg >= 0 ? "+" : ""}${chg.toFixed(1)}%`;
  return { series, label };
}

async function btc(id, name) {
  const d = await get(`https://api.coingecko.com/api/v3/coins/${id}/market_chart?vs_currency=usd&days=1`);
  return pack(name, d.prices);
}

async function clawd() {
  let pool = CLAWD_POOL_FALLBACK;
  try {
    const d = await get(`https://api.geckoterminal.com/api/v2/networks/base/tokens/${CLAWD_TOKEN}/pools?page=1`);
    const best = (d.data || [])
      .sort((a, b) => (+b.attributes.reserve_in_usd || 0) - (+a.attributes.reserve_in_usd || 0))[0];
    if (best) pool = best.id.replace(/^base_/, "");
  } catch { /* fall back to the known pool */ }
  const d = await get(`https://api.geckoterminal.com/api/v2/networks/base/pools/${pool}/ohlcv/hour?aggregate=1&limit=25`);
  // ohlcv rows: [ts, o, h, l, close, vol], newest first
  return pack("$CLAWD", d.data.attributes.ohlcv_list.map((r) => [r[0], r[4]]));
}

const out = {};
for (const [key, fn] of [
  ["btc", () => btc("bitcoin", "btc")],
  ["eth", () => btc("ethereum", "eth")],
  ["clawd", clawd],
]) {
  try {
    out[key] = await fn();
    writeFileSync(join(WORK, `tick-${key}.txt`), out[key].label);
    console.log(`${key}: ${out[key].label}`);
  } catch (e) {
    console.error(`${key}: FAILED (${e.message}) — sparkline omitted`);
  }
}
writeFileSync(join(WORK, "prices.json"), JSON.stringify(out));
