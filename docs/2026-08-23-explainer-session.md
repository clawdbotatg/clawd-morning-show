# 2026-08-23 — the explainer: "clawd, explain this thread" → video

Handoff log for another agent (or future me). The durable contract lives in
`CLAUDE.md` ("The explainer" section); this file is the why, the traps, and
what I verified vs assumed. Companion to
`2026-08-22-speed-headlines-session.md` (the morning-show format this
reuses).

## What exists now, in one paragraph

`./scripts/make-explainer.sh <tweet url|id> ["what was asked"]` fetches a
whole X thread through clawd-twitter's credentials, writes it as a
digest-shaped `brief.md`, and runs the SAME five pipeline stages with
`SHOW_KIND=explainer` → `out/show-x-<rootid>.mp4`: a 45–80s clip of clawd
giving a tl;dr, then an eli5, then (only if they're substantive) what the
replies add. Verified end-to-end on @jayair's DeepSeek v4 Flash post:
74s wall clock cold, 1s re-run, 69s video, clean script, Austin approved
the sample. Commit `86cccde`, pushed.

## Design decision that made it cheap: one input format

The whole pipeline (parser, prompt plumbing, cards, captions, comp) keys on
clawd-morning-update's `digest.md` shape. Instead of teaching stages a
second format, `fetch-thread.mjs` EMITS that shape:

```
# twitter vibe — x-<rootid>
> @author's thread, explained          ← becomes stories.json "headline"
<context para, contains the thread URL> ← "intro"; make-show greps the URL out for the ticker
_N tweets fetched …_
## the thread
<full thread text joined, as the blurb — the model reads this>
- [@author](url) (likes♥ rts🔁): <tweet>   ← the cards render these
## what it quotes        (only if the root quote-tweets something)
## the replies           (only if any survive the junk filter)
```

So `digest_parse.py`, `render_cards.mjs`, `build_captions.py`,
`plan_avatar.mjs`, `05-render.sh` needed zero or tiny changes. If you add a
third show kind, do the same: make the fetcher speak digest.md.

## The X-fetch layer (`scripts/fetch-thread.mjs`)

- **Credentials are clawd-twitter's.** It imports
  `../../clawd-twitter/lib/clients.js` (`bearerClient()`); node resolves
  `twitter-api-v2` from THAT repo's node_modules, so this repo gains no dep
  and clawd-twitter is not edited. `CLAWD_TWITTER=<path>` overrides the
  location.
- **What the bearer token can do (probed live, 2026-08-23):**
  `v2.singleTweet` works; `v2.search("conversation_id:<id> …")` works
  (recent search = last 7 days only — an old thread will fetch the chain
  but come back with 0 replies/continuation; the build still works).
  `note_tweet` fields carry the FULL text of long posts — without them you
  get 280 chars and "…".
- **Traps already hit, don't re-hit:**
  - A tagged tweet is often a RETWEET: the first fetch built a brief around
    the literal "RT @jayair: …" shell. The fetcher now follows a
    `retweeted` ref to the original before doing anything else.
  - Reply junk: the most-liked "reply" on the test thread was "@x @y lmao".
    Replies are filtered — strip leading @mentions and URLs, require ≥40
    chars of substance. The tag-handler prompt does NOT need to worry
    about this.
  - Output is keyed by the ROOT tweet id (printed on stdout), not the input
    id — two people tagging different replies of one thread share a build.
- Cost: ~$0.005/post read; the chain is ~2–20 singleTweet calls +
  `THREAD_REPLIES` (default 30) + up to 50 for the author's own
  continuation. Call it ~$0.20–0.40 per new thread.

## What `SHOW_KIND=explainer` actually switches

All of it went in as small `case`/env forks — grep `SHOW_KIND` to find every
site. Defaults are the morning show; nothing about the 7:40 job changed.

| where | morning | explainer |
|---|---|---|
| `01-script.sh` prompt | `prompts/host.md` | `prompts/explainer.md` |
| `01-script.sh` validator | 3 stories + 10–12 headlines, 250–290w | 1–3 stories, 0 headlines, 110–200w (hard 50–260) |
| `02-tts.sh` truncation floor | 45s | `MIN_AUDIO_S=20` (a 40s explainer is fine, a 40s morning show is a truncated TTS) |
| `05-render.sh` frame | "clawd morning show" / date | `FRAME_TITLE="clawd explains"` / `FRAME_SUB="@author's thread, explained"` |
| ticker | digest headline | the thread link (grepped from stories.json intro) |
| stdout | suggested gm tweet | `suggested reply: tl;dr of this thread 🦞` |
| output | `out/show-<date>.mp4` | `out/show-x-<rootid>.mp4` (SHOW_DATE=x-<rootid>) |

Shared, deliberately: the slop-phrase regex (both kinds), the `<break>` tag
plumbing (explainer just has no headline segments so no tags), the account
picker (`pick_account.py` — the test run routed to the `ef` login), cards,
captions, avatar plan, sync self-check.

`prompts/explainer.md` shape: free intro line (<15 words, names the author),
story 1 = tl;dr (the claim/number, 2–3 sentences), story 2 = eli5 (optional),
story 3 = what the replies add (optional, only if real pushback), fixed
outro "that's the tl;dr. the thread's linked below." Attribution rule is in
the prompt: a thread's claim is reported as the author's claim.

## Idempotency (the wrapper's one subtle bit)

`make-explainer.sh` always re-fetches (cheap), but `brief.md` embeds a
"fetched at" timestamp — naively mv'ing it in would dirty the mtime and
re-run claude + ElevenLabs every time. The wrapper diffs old vs new WITH the
`_…fetched…_` line stripped and keeps the OLD file when nothing real
changed. Verified: second run = "thread unchanged", every stage "fresh:",
1.0s, zero API calls. If the thread GREW (new replies), the diff is real and
it rebuilds — that's wanted.

## How I verified (same rules as CLAUDE.md: pixels and measured audio)

- Frames extracted from the rendered mp4 at both cards — right title lines,
  thread card shows @jayair's real post, replies card shows substantive
  replies (after the junk filter), captions painted (explainer paints all
  captions; only the morning show's headline cards suppress theirs).
- `05-render.sh` sync self-check green (voice onset 2.01s vs cut 2.0s).
- Script read in full — no slop, numbers spelled out, claims attributed.
- Do NOT trust `open` on an already-open mp4 (QuickTime shows the stale
  copy): close-then-open, or send the file over Telegram/chat.

## Not done / next (the actual remaining work)

1. **The tag → video hookup lives in clawd-twitter and is NOT built.**
   `scripts/watch-mentions.js` there already classifies mentions into
   "real asks" (`state/asks.jsonl`, telegrams Austin within 5 min). The
   handler needs to: take an ask that means "explain this", run
   `cd ../clawd-morning-show && ./scripts/make-explainer.sh <url> "<ask>"`,
   then `node scripts/reply-video.js <tagging tweet id> <mp4> "tl;dr of
   this thread 🦞"`. Exit ≠0 → no video, reply with text. ~75s blocking —
   decide whether the daemon spawns it detached. **Before touching that
   repo, re-read its `docs/autonomous-posting.md` and my
   `check-sibling-repos-before-scheduling` memory — I collided with
   parallel work there once already this weekend.**
2. Recent-search only reaches 7 days back: an older thread explains fine
   but loses replies/continuation. If that bites, `read-x.js`'s CDP path
   (Austin's logged-in clone, laptop only) is the escape hatch.
3. Untested edges: a thread whose root is deleted mid-fetch; a
   quote-of-a-quote (only one hop is fetched); a non-English thread.

## File map (this session's additions)

| file | role |
|---|---|
| `scripts/fetch-thread.mjs` | X thread → `thread.json` + digest-shaped `brief.md`; prints root id |
| `scripts/make-explainer.sh` | fetch → diff-keep brief → `SHOW_KIND=explainer make-show.sh` |
| `prompts/explainer.md` | the tl;dr/eli5 prompt |
| `scripts/{make-show,01-script,02-tts,05-render}.sh` | the SHOW_KIND forks (table above) |
| `out/work-x-<rootid>/` | brief.md, thread.json, script/voice/plan/cards |
| `out/show-x-<rootid>.mp4` | the deliverable |

Sample kept on disk: `out/show-x-2090596382306361380.mp4` (jayair/DeepSeek).
Commit: `86cccde` on `clawdbotatg/clawd-morning-show` main.
