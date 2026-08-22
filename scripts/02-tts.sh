#!/usr/bin/env bash
# stage 2: script.txt -> voice.mp3 + words.json via ElevenLabs with-timestamps.
# The voice is clawd's existing clawd-video-chat voice (same rig, same clawd)
# — ELEVENLABS_VOICE_ID in .env. The with-timestamps endpoint returns
# character-level alignment with the audio, so captions need no whisper pass.
# usage: 02-tts.sh <workdir>   (reads $WORK/script.txt)
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 02-tts.sh <workdir>}"
IN="$WORK/script.txt"
OUT="$WORK/voice.mp3"
WORDS="$WORK/words.json"

[ -s "$IN" ] || die "no script at $IN — run 01-script.sh first"
skip_if_fresh "$OUT" "$IN" && exit 0

load_env
if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
  # keyless fallback: macOS `say`. Loud on purpose — the real voice is
  # ElevenLabs; this exists so the pipeline stays testable without the key.
  command -v say >/dev/null || die "no ELEVENLABS_API_KEY and no \`say\` — cannot TTS"
  log "WARNING: no ELEVENLABS_API_KEY — falling back to macOS say (Samantha)"
  say -v "${SAY_VOICE:-Samantha}" -o "$WORK/voice.aiff" -f "$IN"
  check_ffmpeg
  "$FFMPEG" -hide_banner -loglevel error -y -i "$WORK/voice.aiff" -c:a libmp3lame -q:a 3 "$OUT"
  rm -f "$WORK/voice.aiff"
  log "wrote $OUT ($(media_duration "$OUT" | cut -d. -f1)s, say fallback — no word timings)"
  exit 0
fi

# Brian = clawd, the clawd-video-chat default. The harness env leaks a
# different ELEVENLABS_VOICE_ID (Samantha) into agent shells — .env wins.
VOICE_ID="${ELEVENLABS_VOICE_ID:-nPczCjzI2devNBz1zQrb}"
MODEL="${ELEVEN_MODEL:-eleven_flash_v2_5}"   # same model as clawd-video-chat

log "tts: elevenlabs voice=$VOICE_ID model=$MODEL"
BODY="$(python3 - "$IN" "$MODEL" <<'EOF'
import json, sys
print(json.dumps({"text": open(sys.argv[1]).read().strip(),
                  "model_id": sys.argv[2]}))
EOF
)"

HTTP=$(curl -sS -o "$WORK/tts.json" -w '%{http_code}' \
  "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID/with-timestamps?output_format=mp3_44100_128" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" -H "Content-Type: application/json" \
  -d "$BODY")
[ "$HTTP" = "200" ] || { log "API error: $(head -c 500 "$WORK/tts.json")"; die "elevenlabs HTTP $HTTP"; }

# unpack audio + fold character alignment into word timings
python3 - "$WORK/tts.json" "$OUT" "$WORDS" <<'EOF'
import base64, json, sys
d = json.load(open(sys.argv[1]))
open(sys.argv[2], "wb").write(base64.b64decode(d["audio_base64"]))
al = d["alignment"]
chars, starts, ends = al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]
words, cur = [], None
for c, s, e in zip(chars, starts, ends):
    if c.isspace():
        if cur: words.append(cur); cur = None
        continue
    if cur is None:
        cur = {"word": c, "start": s, "end": e}
    else:
        cur["word"] += c; cur["end"] = e
if cur: words.append(cur)
assert words, "empty alignment"
json.dump({"words": words}, open(sys.argv[3], "w"))
print(f"alignment: {len(words)} words", file=sys.stderr)
EOF
rm -f "$WORK/tts.json"

check_ffmpeg
DUR="$(media_duration "$OUT")"
log "wrote $OUT (${DUR%.*}s) + $WORDS"
awk -v d="$DUR" 'BEGIN{exit !(d>140)}' && die "audio is ${DUR%.*}s — over the 2:20 X cap; tighten the script (FORCE=1 to re-run stage 1)"
awk -v d="$DUR" 'BEGIN{exit !(d<45)}' && die "audio is only ${DUR%.*}s — TTS likely truncated"
exit 0
