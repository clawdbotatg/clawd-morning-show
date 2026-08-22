# 2026-08-22 — speed-headline format + the scheduling mistake

Session log, written for Austin. TLDR first.

## TLDR

- The show's format changed: **intro → 3 stories → 10–12 one-line headlines
  with a ~1s beat between each → outro.** Pushed as `db008f0`. Tomorrow's
  7:40 build (clawd-twitter's `com.clawd.twitter-show`) calls this repo's
  `make-show.sh`, so the 8:02 autonomous gm thread posts the new format with
  nothing further to install.
- I also **wrongly added a duplicate launchd job + Telegram ping** to this
  repo without checking clawd-twitter, then removed it the same hour
  (`fbafff2`, `98483ce`). Nothing about the clawd-twitter chain was touched.
- Side fix: a freshness bug that re-ran plan+render on every invocation
  (`fb11861`). A re-run with nothing changed is now 0.3s, zero API calls.
- Today's clip at `out/show-2026-08-22.mp4` (1:56) is the new format. The
  Telegram video you got at 10:04 was my test — ignore it.

## 1. Format change (commit `db008f0`)

### What you asked for
Fewer "headline + what that means" stories (the synthesis loop got
repetitive and slopped — "half the timeline thinks X, the other half Y"),
then a dense run of bare headlines: read, pause, read, pause.

### What changed

**`prompts/host.md`** — rewritten. Shape: intro (fixed line) → exactly 3
stories, 35–50 words, fact-first, only the first may end on one "so what"
sentence, never the words "what it means" → 10–12 headlines, one spoken
sentence each, 6–14 words, pulled from the rest of the digest (unused
sections, tweets inside used sections, "also big this morning") → outro
(fixed line). 250–290 words, hard cap 300. All lowercase like clawd types
(acronyms stay caps so TTS spells them). Explicit slop ban list.

**`scripts/01-script.sh`** (validator) — enforces the shape (3 stories, then
15–22 headlines accepted, stories strictly before headlines), resolves each
headline's `handle` against the digest's tweets, and **rejects a slop regex**
(`half the timeline`, `timeline's split/divided/arguing/debating`, `it's not
X, it's Y`, `the real story`, `here's the thing`, `in other words`, `the
takeaway`, `what this means`, `what it means`) so the existing corrective
retry fires instead of shipping it. Lesson learned on the spot: the model
routed around a prompt-only ban in one regen (went from "split" to
"arguing") — the regex is what holds. Freshness now also keys on
`prompts/host.md` so editing the prompt re-runs the pass.

**The pause between headlines** is an ElevenLabs `<break time="0.9s" />` tag
written into `script.txt` before each headline (`HEADLINE_BREAK_S` in
`scripts/lib.sh`). Measured with a 40-char test call first: paragraph
breaks alone gave ~0.6s, the tag gives ~1.0s (replaces, doesn't add), and
the with-timestamps alignment returns the tag as zero-width characters. So:
- `scripts/02-tts.sh` skips `<…>` spans when folding characters into words
- `scripts/plan_avatar.mjs` strips tags from the text before chunking
- `scripts/03-captions.sh`'s dev fallback strips them too
- tags never enter `script.json` (validator rejects `<`/`>` in segment text)
Word counts on both sides must stay equal or the plan dies with
"chunk/word mismatch".

**On screen** — `plan.json` `layout.stories` became `layout.cards`: every
story AND headline segment, each holding the stage until the next starts,
PIP window from first card to outro. `scripts/render_cards.mjs` writes
`cards/card-<n>.png` over both kinds: story cards unchanged (title + top 3
tweets); **headline cards** = the spoken line at 38px over the ONE tweet it
was read off, or "from <section>" when it came from a blurb — never a
fallback tweet (the first cut put an unrelated @ethereum post under the
Nethermind line). `scripts/04-cards.sh` / `05-render.sh` follow the rename.
Captions whose chunk falls inside a headline card get `mode:"headline"` and
`build_captions.py` doesn't paint them — the card already shows the line
big; painting it twice looked sloppy.

### Verified (pixels + measured audio, not plans)
- Frames extracted from the rendered mp4 at a story and at three headline
  cards — correct card, correct tweet, no duplicate caption.
- `words.json` gaps: ~0.95–1.1s before every headline vs 0.6–0.7 at
  paragraph breaks.
- Stage 5's sync self-check passed (voice onset 2.02s vs chatting cut 2.0s).
- Today's output: 116s, 3 stories (~15–18s each) + 11 headlines (~4–6s each).

### Not done
You asked for ~30 more seconds of headlines, then cancelled it ("never mind
it is good"). That edit was rejected before it ran; nothing from it is on
disk. If you want it later: headline count in the validator + prompt, word
budget, and the 140s cap in `02-tts.sh` / `05-render.sh` (X non-premium
ceiling) all need to move together.

## 2. The scheduling mistake (commits `fb11861` → `fbafff2` → `98483ce`)

You said "ship it and document it and make sure tomorrow goes live with this
new format." I read this repo's own CLAUDE.md, which still said scheduling
was a TODO and posting was "deliberately not wired", and built it:
`launchd/com.clawd.morning-show.plist` (7:45 Denver) + `scripts/cron.sh`
that waited for the digest, ran `make-show.sh`, and sent the mp4 + suggested
tweet to your Telegram via clawd-twitter's `tg-send.js`. I test-fired it
through launchd (`launchctl kickstart`) — that is the 10:04 Telegram video.

What I had not done was look one directory over. `clawd-twitter` already had,
from your other thread the same day (`docs/autonomous-posting.md` there):
- 7:40 `com.clawd.twitter-show` → `scripts/morning-show.sh` waits for the
  digest, runs **this repo's** `make-show.sh`, writes `state/morning-show.json`
- 8:02 `com.clawd.twitter-morning` → autonomous gm thread: gm + image, the
  clip as tweet 2, gmsers link as tweet 3, then embeds the video atop
  gmsers.com/<date>. No approval. "No more asking me in the morning about
  anything."

My job duplicated the 7:40 build and re-added a morning Telegram ping you had
just asked to stop. After you pointed me at the doc I:
- `launchctl bootout`'d `com.clawd.morning-show` and deleted its plist from
  `~/Library/LaunchAgents` (verified gone; `twitter-show` and
  `twitter-morning` still loaded, untouched)
- `git rm`'d `launchd/` and `scripts/cron.sh`; removed the lock/log files it
  had left in `out/`
- rewrote the CLAUDE.md + README sections that claimed posting wasn't wired
  to point at clawd-twitter's chain, with a note that this repo has no
  launchd job and no posting code on purpose
- saved a memory note so a future session checks `launchctl list | grep
  clawd` and clawd-twitter's doc before adding any schedule or ping

I never edited anything in `clawd-twitter`, `clawd-morning-update`, or their
launchd jobs.

## 3. Freshness fix (commit `fb11861`, kept)

While testing the launchd job I noticed stage 3 re-ran on every invocation:
`words.json` and `plan.json` landed in the same second and `[ out -nt in ]`
is false on equal mtimes — the same trap CLAUDE.md already recorded for
stage 1 (where it had re-billed claude + ElevenLabs). `skip_if_fresh` in
`scripts/lib.sh` now tests `! in -nt out` ("not older"), which fixes the
class. Verified: a no-op `make-show.sh` run is 0.33s with all 8 stage checks
reporting fresh and no API calls.

## Tomorrow's check (from clawd-twitter's handoff doc)

```bash
tail -30 ../clawd-twitter/state/show.log      # 7:40 build: "ready: …show-2026-08-23.mp4"
tail -30 ../clawd-twitter/state/morning.log   # 8:02 post: "posted 🦞 https://x.com/…"
ls ../clawd-twitter/state/.posted-gm-2026-08-23
```

The build should log "3 stories + 11 headlines on stage" (or 10–12) from
`plan_avatar.mjs`. 2026-08-23 8:02 is the first live unattended morning run
of the autonomous thread — that part is the other thread's work, not mine.

## Commits (all pushed to `clawdbotatg/clawd-morning-show` main)

| commit | what |
|---|---|
| `db008f0` | format: 3 stories then a rapid headline run (`<break>` beats, headline cards, slop regex) |
| `fb11861` | launchd job + Telegram ping (mistake) **and** the equal-mtime freshness fix |
| `fbafff2` | remove the launchd job + cron.sh |
| `98483ce` | docs: schedule + posting are clawd-twitter's |
