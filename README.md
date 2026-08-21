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
digest.md ──► 1. script pass ──► 2. TTS ──► 3. visuals ──► 4. ffmpeg mux ──► 5. tweet
              (claude -p)        (audio)    (headless      (mp4 ≤2:20)       (clawd-twitter)
                                            chromium)
```

Full plan: **[DESIGN.md](DESIGN.md)**.

## Run it (v0)

```
cp .env.example .env         # put OPENAI_API_KEY in it
./scripts/voice-samples.sh   # once: listen, pick the brand voice (VOICE= in .env)
./scripts/make-show.sh samples/digest.md
# -> out/show-YYYY-MM-DD.mp4 + suggested tweet text on stdout
```

Stages (each idempotent — skips fresh outputs, `FORCE=1` re-runs):
`01-script.sh` digest → ~320 spoken words via `claude -p` + `prompts/host.md` ·
`02-tts.sh` OpenAI `gpt-4o-mini-tts` · `03-captions.sh` whisper word timestamps
→ `.ass` captions · `04-render.sh` branded frame + waveform + burned captions
→ H.264 mp4. Needs an ffmpeg with libass/freetype (`brew install ffmpeg-full`
— the plain brew bottle dropped them). Posting is deliberately not wired yet.

## Status

Ship order:

- [x] **v0** — static branded frame + waveform + burned captions over TTS
      audio, pure ffmpeg. Tweetable in a morning.
- [ ] **v1** — HTML "slop computer" renderer page (terminal aesthetic,
      lower-thirds, story cards) captured with headless Chromium.
- [ ] **v2** — real session b-roll: asciinema cast of the actual news crawl
      behind the cards.

Runs on the morning-report machine (launchd, ~8:35am Denver, right after the
paper publishes). Any failure degrades to the normal gm tweet — the video
just doesn't attach.
