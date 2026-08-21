#!/usr/bin/env bash
# stage 2: script.txt -> voice.mp3 via OpenAI gpt-4o-mini-tts
# usage: 02-tts.sh <workdir>   (reads $WORK/script.txt)
# VOICE / TTS_INSTRUCTIONS env-overridable; defaults live here once picked.
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 02-tts.sh <workdir>}"
IN="$WORK/script.txt"
OUT="$WORK/voice.mp3"

# the brand voice — picked by Austin from voice samples, change deliberately
VOICE="${VOICE:-ash}"
TTS_MODEL="${TTS_MODEL:-gpt-4o-mini-tts}"
TTS_INSTRUCTIONS="${TTS_INSTRUCTIONS:-Morning news host: warm, dry, unhurried, \
lightly amused. Conversational pace around 155 words per minute. Small pauses \
between stories. Never salesy or hypey.}"

[ -s "$IN" ] || die "no script at $IN — run 01-script.sh first"
need_openai_key
skip_if_fresh "$OUT" "$IN" && exit 0

log "tts: model=$TTS_MODEL voice=$VOICE"
BODY="$(python3 - "$IN" "$TTS_MODEL" "$VOICE" "$TTS_INSTRUCTIONS" <<'EOF'
import json, sys
text = open(sys.argv[1]).read().strip()
print(json.dumps({"model": sys.argv[2], "input": text, "voice": sys.argv[3],
                  "instructions": sys.argv[4], "response_format": "mp3"}))
EOF
)"

HTTP=$(curl -sS -o "$OUT.tmp" -w '%{http_code}' https://api.openai.com/v1/audio/speech \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d "$BODY")
[ "$HTTP" = "200" ] || { log "API error body: $(head -c 500 "$OUT.tmp")"; rm -f "$OUT.tmp"; die "TTS HTTP $HTTP"; }
mv "$OUT.tmp" "$OUT"

check_ffmpeg
DUR="$(media_duration "$OUT")"
log "wrote $OUT (${DUR%.*}s)"
awk -v d="$DUR" 'BEGIN{exit !(d>140)}' && die "audio is ${DUR%.*}s — over the 2:20 X cap; tighten the script (FORCE=1 to re-run stage 1)"
awk -v d="$DUR" 'BEGIN{exit !(d<45)}' && die "audio is only ${DUR%.*}s — TTS likely truncated"
exit 0
