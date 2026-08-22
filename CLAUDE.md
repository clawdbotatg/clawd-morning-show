# clawd-morning-show — orientation for an agent

`README.md` is the user-facing overview and `DESIGN.md` the original plan.
This file is what you need to *work on* it without re-learning the traps.
Written 2026-08-21 after building v0 → v1 in one day; every "don't" below
was paid for.

## What it is, in one paragraph

A daily ~2-minute mp4 of clawd reading the morning news, ready to tweet.
Input: `clawd-morning-update`'s `state/digest.md` (markdown of the gmsers.com
paper). Output: `out/show-YYYY-MM-DD.mp4` + a suggested tweet on stdout.
One entry point, five idempotent stages, pure ffmpeg for the mux, no
screen capture, no live session. Posting is **deliberately not wired**
(Austin wants to watch outputs before it auto-tweets).

```
./scripts/make-show.sh samples/digest.md
```

## The one principle: one clawd everywhere

The voice and the face are **not this project's to choose** — they are
clawd-video-chat's (the Zoom/OBS rig, `github.com/clawdbotatg/clawd-video-chat`).
Everything here reuses that rig's assets and, where possible, *executes its
code* rather than reimplementing it. Austin was explicit and repeatedly
angry when this was violated. If a question is "what should clawd sound /
look / move like", the answer is "whatever clawd-video-chat does" — go read
it, or run it.

### Voice (ElevenLabs) — the trap that burned three renders
- **Voice ID `Q4oILuo4P8VeXtE6FMLI`** = "Matthew Schmitz – Warm Mountain Man"
  (ElevenLabs library voice), model **`eleven_flash_v2_5`**, voice_settings
  **stability 0.65 / similarity_boost 0.5 / use_speaker_boost true / speed 1.2**
  (speed 1.2 is what makes the drawl conversational). Source of truth: the
  `.env` of clawd-video-chat **on leftclaw** — the machine that runs the rig.
  It is *not* on this box; Austin fetched it by hand.
- **Do not trust either of the two other IDs you'll find on disk:**
  - `uIZsnBL0YK1S5j69bAih` ("Samantha") is in the **harness's**
    `.clawd-harness.env`. The harness exports it into every agent shell, and
    clawd-video-chat's own code comments warn it "ended up speaking in the
    harness's voice". I used it first. Wrong.
  - `nPczCjzI2devNBz1zQrb` ("Brian") is the rig's *hardcoded fallback* in
    `server.py` and its `.env.example`. I used it second. Also wrong — the
    real `.env` overrides it.
- `scripts/02-tts.sh` defaults to Matthew Schmitz so the harness leak can't
  win silently; `.env` (gitignored) holds `ELEVENLABS_API_KEY` +
  `ELEVENLABS_VOICE_ID`. The key on this box was copied from the harness env.
- TTS goes through the **`with-timestamps`** endpoint: audio + character
  alignment in one call → `words.json`. There is no whisper stage; an
  OpenAI-TTS + whisper version existed for an hour and was deleted.
- The voice reads ~150 wpm; the script budget (270–300 words) is set for
  that. The 2:20 cap is X's non-premium video ceiling; 02 and 05 both die
  loudly above 140s.

### Face (the avatar clips)
- `assets/{idle_1,idle_2,chatting_1}.mp4` are vendored from the rig's
  `clawdassets/` (624×624, 24fps, 5.1s / 5.2s / 9.0s).
- **They are on pure black, not chroma-green** (README of the rig says green;
  the pixels say 0,0,0). So there is no keying: the show background is pure
  black and the square clip is overlaid as-is. Keying black would eat the
  tux. Don't "fix" this back to colorkey.
- `chatting_1` is **mid-speech at frame 0** (mouth open at 0.00s, closed at
  0.50s, open at 0.75s — tiled and looked at). No lead between the cut to
  chatting and the voice: `MOUTH_LAG_S=0` in `lib.sh`. An earlier 0.6s "lead"
  came from a frame-diff that was measuring a head bob. Look at frames, not
  at diff numbers.

### Clip selection — the rig's code runs here, literally
`scripts/plan_avatar.mjs` cuts the `clawdVid` IIFE and the TTS-chunking
regexes (`_TTS_FIRST_RE`, `_TTS_SENT_RE`, `_TTS_MAX_CHUNK`) out of the
**vendored rig `index.html`** (`assets/rig/index.html`, refreshed by
`scripts/fetch-rig.sh`, source commit in `assets/rig/SOURCE`) and executes
them in node against fake `<video>` elements that fire `playing`/`ended` on
the real clip durations, feeding the same events the live page gets: each
TTS chunk's `audio.onplay` → `chatting()`, queue drained → `idle(true)` after
250ms. Every overlay "snap" is recorded as a cut → `plan.json` segments →
ffmpeg trims/concat. Nothing reimplements the state machine.

Why this matters: I first wrote a Python copy of the state machine from
*reading* the code, and it was wrong. Running the real code showed that
every clip variant aliases to the same three files, so
`chatting_1 === BUILDING` and `idle_2 === THINKING`, both in `LOOPING_SRCS`
→ the rig sets `<video loop>` on them. **Chatting hard-loops for the whole
speech** (the per-sentence re-fire is a no-op while `_chatting` is true), and
the rig's "crossfade" is a snap to the new clip followed by a fade between
two copies of the *same* clip — visually a hard cut. Today's plan is
typically 3 segments: idle_1 (2s cold open) → chatting looped → random idle
outro. The ffmpeg inputs are `-stream_loop -1` to match `<video loop>`.

If the rig changes, run `scripts/fetch-rig.sh`; if its DOM contract changes
(new element ids, new events), `plan_avatar.mjs`'s fake DOM needs to follow.
The gitleaks bip39 rule false-positives on that html's English comments —
there is a path-scoped allowlist for `assets/rig/index.html` in
`~/.config/gitleaks/gitleaks.toml` (this machine only; a new box needs it
too or the commit hook blocks).

## Pipeline — stages, contracts, knobs

All stages `set -euo pipefail`, skip when their output is newer than their
input (`skip_if_fresh`), `FORCE=1` re-runs, and `die` loudly. Shared helpers
and the timeline constants (`INTRO_S=2`, `OUTRO_S=3`, `MOUTH_LAG_S=0`) are in
`scripts/lib.sh`. Work dir: `out/work-<date>/`.

1. **`01-script.sh`** digest.md → `stories.json` (`digest_parse.py`) →
   `claude -p --model sonnet` with `prompts/host.md` → **JSON segments**
   `{kind: intro|story|headline|outro, theme, handle?, text}` validated
   against the digest's `##` headings (exact match after case-fold), retried
   once on invalid / out-of-range, → `script.json` + `script.txt` (segments
   joined by blank lines; this is what TTS reads).
   - **Show shape (2026-08-22, Austin's call):** intro → **exactly 3
     stories** (fact-first; only the first may end on a one-line "so what")
     → **10–12 one-sentence headlines** ("read the headline, pause, read the
     headline") → outro. The old 5–6 × (headline + "what it means") loop got
     repetitive and slopped ("half the timeline thinks X, the other half
     Y"). The validator enforces the shape AND rejects a slop-phrase regex
     (`timeline's split/arguing`, `it's not X, it's Y`, `what it means`…) so
     the corrective pass fires instead of shipping it; the prompt bans the
     same list. The model *will* route around a prompt-only ban (it went
     from "split" to "arguing" in one regen) — extend the regex, not just
     the prose.
   - **The headline beat is an ElevenLabs `<break time="0.9s" />` tag**
     (`HEADLINE_BREAK_S` in lib.sh) written into `script.txt` before each
     headline. Paragraph breaks alone gave ~0.6s; the tag gives ~1.0s (it
     replaces, not adds). Measured: the with-timestamps alignment returns the
     tag as zero-width characters, so 02 skips `<…>` spans when folding
     words and `plan_avatar.mjs` strips tags from the text — word counts on
     both sides must stay equal or the plan dies with "chunk/word mismatch".
     Tags never enter `script.json` (validator rejects `<`/`>` in text).
   - Freshness also keys on `prompts/host.md`, so editing the prompt re-runs
     the pass (and, by making `script.txt` newer, re-bills TTS once).
   - `scrub_claude_env` unsets `CLAUDECODE`/`CLAUDE_CODE_*`/`ANTHROPIC_*`
     first — a nested `claude` otherwise runs embedded (no transcript, metered
     billing). Same gotcha as the harness.
   - Trap I hit: feeding the model output to a validator python via
     `python3 - <<'PY'` *and* stdin — the heredoc *is* stdin, so the data is
     gone. Output goes through `script.raw` on disk.
2. **`02-tts.sh`** script.txt → ElevenLabs with-timestamps → `voice.mp3` +
   `words.json` (char alignment folded to words by whitespace). No key → loud
   macOS `say` (Samantha) fallback so the pipeline stays testable; 03 then
   synthesizes uniform timings (captions drift — dev only).
3. **`03-captions.sh`** runs `plan_avatar.mjs` → `plan.json` (`segments`,
   `captions` with `mode`, `layout.pip` + `layout.cards`, `total`) +
   `avatar.filter`; then `build_captions.py` → `captions.ass` in the rig's
   `#speechCaption` style (white bold Helvetica, black stroke, bottom 64px;
   `CapPip` style with a 400px right margin during the PIP window).
   Caption unit = the rig's TTS chunk (a sentence; first chunk on any pause;
   240-char cap), held until the next chunk starts. `layout.cards` is every
   story AND headline segment (`kind` on each), each holding the stage until
   the next starts. Captions whose chunk falls inside a headline card get
   `mode:"headline"` and are **not painted** — the card already shows the
   line big; painting it twice looked sloppy.
4. **`04-cards.sh`** → `render_cards.mjs` → `cards/card-<n>.png`, n over
   both kinds. Story card: 860px-wide theme title + top 3 tweets by
   likes+rts, boosted if the script names the handle. Headline card: the
   spoken line at 38px over the ONE tweet it was read off (`handle` from
   script.json); a blurb-sourced headline (no handle) shows "from <section>"
   instead — never a fallback tweet, which put an unrelated post under the
   line the first time. Initial-letter avatars — the digest carries no image
   URLs. Screenshotted by the machine's cached Playwright Chromium
   (`~/Library/Caches/ms-playwright`, same resolution as the harness's
   `tools/uiprobe.mjs` — plus the newer
   `chrome-headless-shell-mac[-arm64]/chrome-headless-shell` layout, the only
   one a current `npx playwright install` leaves; uiprobe still lacks it).
   `playwright-core` via `package.json`; no network.
5. **`05-render.sh`** the comp, one filter graph read from `show.filter`
   (`-/filter_complex` on ffmpeg ≥7 — ffmpeg 8 removed
   `-filter_complex_script`, and brew's `ffmpeg-full` is 9; the old flag is
   kept for older builds):
   - `loudnorm` runs as a **separate pre-pass** to `voice.norm.wav`. Inline,
     loudnorm emits NOPTS frames and `adelay` after it left the first chunk
     of audio at t=0 while delaying the rest — "gm" played over the idle
     clip. Austin heard it; my plan-side checks didn't. Don't chain them.
   - avatar chain from `avatar.filter` → split → 560px full (centered,
     bottom-flush) outside the PIP window, 300px PIP at (940,360) inside it;
     story cards `-loop 1` inputs overlaid at (40,140) with
     `enable=between(t,start,end)`; bottom ticker (headline · gmsers.com,
     Monaco) at y=684; `subtitles=captions.ass`; audio `adelay` by
     `INTRO_S+MOUTH_LAG_S`.
   - **Sync self-check**: measures the voice onset in the *rendered mp4*
     (silencedetect) against the first chatting cut in `plan.json` and dies
     if they differ by >0.15s. It caught the loudnorm bug. Keep it.
   - Needs an ffmpeg with libass + freetype. brew's plain `ffmpeg` bottle
     dropped them (no `subtitles`, no `drawtext`); **`ffmpeg-full`** is
     keg-only at `/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg` and `check_ffmpeg`
     in lib.sh probes for it (`FFMPEG=` env overrides). Installing it pulls a
     newer `x265` and leaves an older plain `ffmpeg` bottle unable to load
     (`libx265.N.dylib` missing) — `brew upgrade ffmpeg` repairs it.
   - **Freshness trap**: `-nt` is false on an *equal* mtime, and a fast
     stage routinely writes its output in the same second its input landed
     (stage 1's two files; TTS→`words.json`→`plan.json`). With `out -nt in`
     that re-ran `claude -p` + re-billed ElevenLabs on every invocation, and
     after that fix still re-ran plan+render daily. `skip_if_fresh` is now
     `! in -nt out` ("not older"), which is the right test. A fresh re-run
     of `make-show.sh` should take <1s and make no API call — check that
     after touching any skip logic.

`make-show.sh` chains them, exports `HEADLINE` (from `stories.json`) for the
ticker, and prints the suggested tweet. Hard cuts everywhere on purpose
(that's the rig's look); there is no animation yet. A typical show is now
~115s: 3 stories hold ~15–18s each, headlines ~4–6s each.

## Input contract — the real digest.md

`samples/digest.md` is in the **real** format `clawd-morning-update`
writes (`scripts/render.js` + `lib/html.js` `mdTweet`), reconstructed from
the published paper HTML because `state/` is gitignored and lives only on
the morning-report box:

```
# twitter vibe — 2026-08-21
> headline
intro paragraph
_1502 tweets from Austin's home timeline, last 14h, fetched 7:30 AM MT._
## theme title
blurb
- [@handle](https://x.com/handle/status/id) (1.2k♥ 116🔁): text ≤200 chars   (≤4 per theme)
## also big this morning
- …
---
_source: …_
```

My first sample was my own HTML→text dump of the page — a different shape.
If `digest_parse.py` exits with "doesn't look like digest.md", that's the
first thing to check. `digest_parse.py` is the only place that knows the
format; the theme titles it extracts are what `01-script` forces the model
to echo and what `render_cards` keys on.

## How to verify (what actually worked vs what lied)

- **Watch frames, not plans.** Extract with
  `ffmpeg -ss T -i out/show-*.mp4 -frames:v 1 x.png` and look; tile the
  mouth region (`fps=4,crop=…,tile=10x1`) to see motion. Every time I
  reasoned from a number (frame diffs, plan timings) instead of pixels, I
  was wrong.
- **Measure audio in the output file**: `silencedetect`, `astats` RMS per
  100ms. The sync check in 05 does the minimal version automatically.
- **QuickTime does not reload an open file.** `open` on an already-open path
  just refocuses the stale window. Hand Austin:
  `osascript -e 'tell application "QuickTime Player" to close every document' ; open <mp4>`
- Playwright screenshots of the cards are in `out/work-<date>/cards/` —
  look at them before blaming the comp.
- `plan.json` is the readable timeline (segments, captions with times,
  layout); `show.filter` is the exact graph ffmpeg ran.

## Shipping rules here

- Under `~/clawd/`: commit + push when a chunk works, clawdbotatg identity,
  HTTPS, gitleaks hook runs on every commit. Secret scan the staged diff by
  hand too (the `.env` never goes in; `assets/rig/index.html` is allowlisted
  by path only).
- `.gitignore`: `.env`, `out/`, `*.mp3`, `*.mp4` (with `!assets/*.mp4` so the
  vendored clips ship), `node_modules/`, `__pycache__/`.
- Austin's style: TLDR first, plain words, no filler. When he says "use the
  thing we already have", stop designing and go read the thing we already
  have — on the machine that runs it, not a stale local clone.

## Not done / next

- **Posting**: nothing tweets — Austin gets the clip on Telegram and posts
  it himself. `clawd-twitter`'s `tweet-with-image.js` is the fork point
  (`twitter-api-v2` `uploadMedia` does chunked video) if that changes.
- **Schedule — DONE (2026-08-22)**: `launchd/com.clawd.morning-show.plist`
  (installed in `~/Library/LaunchAgents` on this box — the Mac mini *is*
  the morning-report machine) fires `scripts/cron.sh` at **7:45 Denver**,
  after `com.clawd.morning-report` (7:30, done ~7:39) and before
  clawd-twitter's 8:02 gm tweet. The wrapper waits up to 30 min for a
  `digest.md` whose header carries today's date, runs `make-show.sh`, and
  sends the mp4 + suggested tweet to Austin's Telegram with clawd-twitter's
  `tg-send.js` (`.mp4` → `sendVideo`). Failure → a Telegram note, never a
  retry loop; the gm tweet is untouched. Log: `out/cron.log`; lock:
  `out/.ran-show-<date>`; test by hand with
  `launchctl kickstart gui/$(id -u)/com.clawd.morning-show` (a fresh day is
  all "fresh:" + one Telegram send). Login: the plain `~/.claude` dir IS
  signed in — a `claude -p` that says "Not logged in" under `env -i` is
  missing `USER`/`LOGNAME` (Keychain lookup), which launchd provides.
  Re-install after editing the plist:
  `cp launchd/*.plist ~/Library/LaunchAgents/ && launchctl bootout gui/$(id -u)/com.clawd.morning-show; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.clawd.morning-show.plist`.
- **Motion**: PIP drop and card swaps are hard cuts. A 0.3s scale/slide is
  an ffmpeg `overlay` x/y expression over `t` — no new tools.
- **Avatars on cards** are initial-letter discs; the digest has no pfp URLs.
  If clawd-morning-update starts recording them, `render_cards.mjs` is the
  only place to change.
- **Header/ticker** (title, date, headline ticker) are mine, not the rig's.
  Austin has seen them and not objected; they're the first thing to cut if
  "identical to the rig" ever becomes the ask.
- Per-pause idle/chatting switching is *not* a goal — the rig doesn't do it
  either (see the loop finding above).
