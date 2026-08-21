# clawd-morning-show

clawd **reads** the morning news instead of writing it: a daily ~2-minute
recorded video of clawd talking through the headlines in plain English,
auto-tweeted every morning alongside the [gmsers.com](https://gmsers.com)
paper.

Born from [this reply](https://x.com/chrishobcroft/status/2090788967125790948)
to the gmsers launch: *"why doesn't your clawdbotatg have their own slop
computer where they read the news instead of write it? … watching and
listening instead of reading."*

## How

Fully headless — no OBS, no screen recording, no live session. A third
renderer over data [`clawd-morning-update`](https://github.com/clawdbotatg/clawd-morning-update)
already produces daily:

```
digest.md ──► 1. script pass ──► 2. TTS ──► 3. clawd avatar ──► 4. ffmpeg mux ──► 5. tweet
              (claude -p)        (audio)       comp             (mp4 ≤2:20)       (clawd-twitter)
                                            (idle/chatting loops
                                             + captions, pure ffmpeg)
```

The on-screen clawd is the same avatar the Zoom/OBS rig shows
([clawd-video-chat](https://github.com/clawdbotatg/clawd-video-chat)'s
`clawdassets/` idle/chatting clips, vendored in `assets/`) — one clawd
everywhere. Note the clips ship on pure **black**, not chroma-green, so the
comp overlays them on a black card instead of keying (keying black would eat
the tux).

Full plan: **[DESIGN.md](DESIGN.md)**.

## Run it (v0)

```
cp .env.example .env         # ElevenLabs creds — same as clawd-video-chat's
./scripts/make-show.sh samples/digest.md
# -> out/show-YYYY-MM-DD.mp4 + suggested tweet text on stdout
```

Stages (each idempotent — skips fresh outputs, `FORCE=1` re-runs):
`01-script.sh` digest → ~290 spoken words via `claude -p` + `prompts/host.md` ·
`02-tts.sh` ElevenLabs `with-timestamps` — **clawd's existing clawd-video-chat
voice** (`ELEVENLABS_VOICE_ID`), audio + word timings in one call (no key →
loud macOS `say` fallback) · `03-captions.sh` timings → burned `.ass` captions ·
`04-render.sh` avatar comp: idle cold-open → seam-hidden chatting loop for the
narration → idle outro, headline ticker + burned captions → H.264 mp4. Needs
an ffmpeg with libass/freetype (`brew install ffmpeg-full` — the plain brew
bottle dropped them). Posting is deliberately not wired yet.

## Status

Ship order:

- [x] **v0** — clawd avatar comp (idle/chatting loops from clawd-video-chat)
      + headline ticker + burned captions over TTS audio, pure ffmpeg.
- [ ] **v1** — the "slop computer" set dressing AROUND the avatar (terminal
      aesthetic, story cards, per-pause idle/chatting switching), HTML page
      captured with headless Chromium. The avatar stays the centerpiece.
- [ ] **v2** — real session b-roll: asciinema cast of the actual news crawl
      behind the cards.

Runs on the morning-report machine (launchd, ~8:35am Denver, right after the
paper publishes). Any failure degrades to the normal gm tweet — the video
just doesn't attach.
