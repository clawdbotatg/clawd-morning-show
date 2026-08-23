#!/usr/bin/env node
// Read an X thread for the explainer: the tagged/linked tweet, the reply chain
// up to its root, the author's own continuation, the quoted tweet if any, and
// the top replies — then write it as a digest-shaped brief.md so the rest of
// the pipeline (digest_parse → 01-script → cards) runs unchanged.
//
// X access is clawd-twitter's: this imports its lib/clients.js (bearer token
// from that repo's .env) and never edits that repo. Reads are billed per post
// (~$0.005): ~10 for the chain + THREAD_REPLIES for the reply search.
//
// usage: fetch-thread.mjs <tweet url | id> <outdir> ["what was asked"]
//   -> outdir/thread.json (raw) + outdir/brief.md (digest shape) ; prints the id
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const [arg, outDir, ask] = process.argv.slice(2);
if (!arg || !outDir) { console.error("usage: fetch-thread.mjs <tweet url|id> <outdir> [ask]"); process.exit(2); }
const id = (arg.match(/status\/(\d+)/) || arg.match(/^(\d+)$/) || [])[1];
if (!id) { console.error(`fetch-thread: no tweet id in ${arg}`); process.exit(2); }
const REPLIES = parseInt(process.env.THREAD_REPLIES || "30", 10);

const here = path.dirname(fileURLToPath(import.meta.url));
const TW = process.env.CLAWD_TWITTER || path.resolve(here, "../../clawd-twitter");
const { bearerClient } = await import(path.join(TW, "lib/clients.js"));
const c = bearerClient();

const FIELDS = {
  "tweet.fields": "created_at,public_metrics,author_id,conversation_id,referenced_tweets,note_tweet,entities",
  expansions: "author_id,referenced_tweets.id,referenced_tweets.id.author_id",
  "user.fields": "username,name,public_metrics",
};
const users = new Map();
const norm = (t, inc) => {
  for (const u of inc?.users || []) users.set(u.id, u);
  const u = users.get(t.author_id);
  const m = t.public_metrics || {};
  // note_tweet carries the full text of long posts; expand t.co links to their display form
  let text = t.note_tweet?.text || t.text || "";
  for (const url of t.entities?.urls || []) if (url.expanded_url) text = text.replace(url.url, url.expanded_url);
  for (const url of t.note_tweet?.entities?.urls || []) if (url.expanded_url) text = text.replace(url.url, url.expanded_url);
  return { id: t.id, author: u?.username || "i", name: u?.name || "", followers: u?.public_metrics?.followers_count || 0,
           created_at: t.created_at, likes: m.like_count || 0, rts: m.retweet_count || 0, replies: m.reply_count || 0,
           conversation_id: t.conversation_id, refs: t.referenced_tweets || [], text: text.replace(/\s+/g, " ").trim(),
           url: `https://x.com/${u?.username || "i"}/status/${t.id}` };
};
const one = async (tid) => { const r = await c.v2.singleTweet(tid, FIELDS); if (!r.data) throw new Error(`tweet ${tid}: ${JSON.stringify(r.errors || r).slice(0, 200)}`); return norm(r.data, r.includes); };

// 1. the tweet, then up the reply chain to the root (a tagged reply usually sits under the thing to explain)
let start = await one(id);
const rt = start.refs.find(r => r.type === "retweeted");   // a tagged RT: explain the original, not the RT shell
if (rt) start = await one(rt.id);
const chain = [start];
for (let hops = 0; hops < 20; hops++) {
  const up = chain[0].refs.find(r => r.type === "replied_to");
  if (!up) break;
  try { chain.unshift(await one(up.id)); } catch (e) { console.error(`fetch-thread: chain stops — ${e.message}`); break; }
}
const root = chain[0];

// 2. the author's own continuation below the root (the thread proper), plus the top replies by others
const q = async (query, n) => {
  const r = await c.v2.search(query, { max_results: Math.min(Math.max(n, 10), 100), ...FIELDS });
  return (r.data?.data || []).map(t => norm(t, r.includes));
};
let own = [], others = [];
try { own = await q(`conversation_id:${root.conversation_id} from:${root.author}`, 50); } catch (e) { console.error(`fetch-thread: own-thread search failed — ${e.message}`); }
try { others = await q(`conversation_id:${root.conversation_id} -from:${root.author} -is:retweet`, REPLIES); } catch (e) { console.error(`fetch-thread: reply search failed — ${e.message}`); }
// 3. a quoted tweet is half the context of a quote-tweet
let quoted = null;
const qref = root.refs.find(r => r.type === "quoted");
if (qref) { try { quoted = await one(qref.id); } catch (e) { console.error(`fetch-thread: quoted ${qref.id} — ${e.message}`); } }

const seen = new Set();
const thread = [...chain, ...own.sort((a, b) => a.id.localeCompare(b.id))].filter(t => t.author === root.author && !seen.has(t.id) && seen.add(t.id));
// a reply is worth a card only if it says something: strip the leading @mentions and want ≥40 chars left
const substance = t => t.text.replace(/^(@\w+\s+)+/, "").replace(/https?:\/\/\S+/g, "").trim();
const top = others.filter(t => t.text && !seen.has(t.id) && substance(t).length >= 40)
  .sort((a, b) => (b.likes + b.rts) - (a.likes + a.rts)).slice(0, 6);
const when = new Date(root.created_at).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "America/Denver" });
const num = n => n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, "") + "k" : String(n);
const bullet = t => `- [@${t.author}](${t.url}) (${num(t.likes)}♥ ${num(t.rts)}🔁): ${t.text}`;

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "thread.json"), JSON.stringify({ id, root: root.id, ask: ask || "", thread, quoted, replies: top, fetched: new Date().toISOString() }, null, 1));
const lines = [
  `# twitter vibe — x-${root.id}`, "",
  `> @${root.author}'s thread, explained`, "",
  `${ask ? `someone asked clawd: "${ask}". ` : ""}@${root.author} (${root.name}, ${num(root.followers)} followers) posted this on ${when}: ${thread.length} tweet${thread.length === 1 ? "" : "s"}, ${num(root.likes)} likes, ${num(root.replies)} replies. link: ${root.url}`, "",
  `_${thread.length + top.length + (quoted ? 1 : 0)} tweets fetched ${new Date().toLocaleTimeString("en-US", { timeZone: "America/Denver" })} MT._`, "",
  `## the thread`,
  thread.map(t => t.text).join(" "),
  ...thread.map(bullet), "",
];
if (quoted) lines.push(`## what it quotes`, `@${root.author} was quoting @${quoted.author}: ${quoted.text}`, bullet(quoted), "");
if (top.length) lines.push(`## the replies`, `the most-liked replies under it.`, ...top.map(bullet), "");
lines.push("---", `_source: fetch-thread.mjs via clawd-twitter (bearer), ${root.url}_`, "");
fs.writeFileSync(path.join(outDir, "brief.md"), lines.join("\n"));
console.error(`fetch-thread: @${root.author} root ${root.id}: ${thread.length} in thread, ${top.length} replies${quoted ? ", 1 quoted" : ""} -> ${outDir}/brief.md`);
console.log(root.id);
