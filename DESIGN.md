# clawd morning show — recorded news TLDR video, auto-tweeted

**Prompt:** Chris Hobcroft's reply to the gmsers.com launch
(x.com/chrishobcroft/status/2090788967125790948): *"isn't it a bit 1990s? …
why doesn't clawdbotatg have their own slop computer where they READ the news
instead of write it… watching and listening instead of reading. It could even
host guests."*

Austin's ask: a ~2-minute recorded clip of clawd talking through the morning
headlines in plain English, tweeted every morning — more automated than the
old OBS + shared-browser (clawd-video-chat) rig.

## Key realization: the news pipeline already exists

`clawd-morning-update` (runs on the morning-report machine, launchd
`com.clawd.morning-report`, 8:20am Denver) already:

1. reads the 8:02am home-timeline snapshot from clawd-twitter (no extra API cost)
2. `rank.js` → deterministic theme clustering → `state/brief.json`
3. `claude -p` narrative pass → `state/narrative.json` (headline, intros, blurbs)
4. renders gmsers.com + `state/digest.md` (markdown of the whole report)
5. drops `~/Desktop/recon/twitter/latest.md` for any agent on the box

So the video step is **a second renderer over data already on disk** — the
exact same move the paper itself was ("a second pass over data that would
otherwise be read once and thrown away"). No OBS, no screen, no live session.

## Pipeline (headless, deterministic)

```
digest.md ──► 1. script pass ──► 2. TTS ──► 3. visuals ──► 4. ffmpeg mux ──► 5. tweet
              (claude -p)        (audio)    (headless      (mp4 ≤2:20)       (clawd-twitter)
                                            chromium)
```

1. **Script pass** — `claude -p` with a "morning show host" prompt:
   digest.md → ~300–330 spoken words (2 min @ ~160 wpm). Clawd's voice,
   one line per story + "what it actually means" in plain English. This is
   a *spoken-register* rewrite, not the paper's prose — no URLs, no
   parentheticals, contractions on.

2. **Voice** — OpenAI TTS (`gpt-4o-mini-tts`, steerable delivery via
   instructions — see clawd-research/gpt-voice/ for the API landscape).
   Deterministic, pennies per run, no mic, no realtime session to babysit.
   Run whisper (or any STT with word timestamps) over our *own* output to get
   word-level timings for captions — cheaper and more reliable than picking a
   TTS vendor for its timestamp feature.

3. **Visuals — the "slop computer" answer.** A single self-contained HTML
   renderer page: terminal/CRT aesthetic, clawd identity, animated waveform
   driven by the audio, headline lower-thirds that advance on the caption
   timing track, burned-in captions (most X viewing is muted — captions are
   not optional). Drive it with headless Chromium (Playwright, same toolbox
   as the harness probes) and capture frames → ffmpeg. Optional b-roll layer:
   an asciinema-style cast of the actual crawl session behind the cards, so
   it literally *is* the agent at his computer.

4. **Mux** — ffmpeg: frames + audio, loudnorm, 720p, H.264/AAC. Keep ≤2:20
   (the non-premium X video ceiling, and the right length anyway).

5. **Post** — clawd-twitter already has the client + guardrails;
   `tweet-with-image.js` is a 5-line fork away from video (`twitter-api-v2`'s
   `uploadMedia` does chunked video upload natively). Tweet = the morning
   one-liner + the clip + gmsers.com link.

6. **Schedule** — extend `report.sh` (or a sibling launchd job ~8:35am, after
   the paper publishes). Same degradation rule as the narrative pass: any
   failure → the normal gm tweet still goes out, video just doesn't attach.

## Ship order

- **v0 (hours):** static branded frame + waveform + captions over TTS audio,
  pure ffmpeg, no browser capture. Ugly-simple but tweetable tomorrow morning.
- **v1 (a day):** the renderer page + headless-Chromium capture — lower-thirds,
  story cards, terminal aesthetic.
- **v2:** real session b-roll layer (asciinema cast of the crawl).

## Guests (Chris's second point)

That's the **live** lane, and it's a different rig: clawd-video-chat /
gpt-realtime over WebRTC already does live voice with a human. The daily clip
should stay headless; a weekly "guest episode" can reuse the existing
OBS + video-chat setup, recorded and clipped. Don't couple them — the daily's
whole value is that nothing can fail at 8:35am.

## Open questions

- Whose TTS voice is clawd? (Pick once, keep forever — the voice *is* the brand.
  OpenAI's steerable voices vs ElevenLabs cloned voice.)
- Does clawdbotatg's X tier allow >2:20 video? Irrelevant for now — 2:00 target.
- Where it runs: the morning-report machine (not this research box) — the
  video step needs ffmpeg + Playwright there.
