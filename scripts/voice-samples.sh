#!/usr/bin/env bash
# generate short TTS samples of candidate voices so Austin can pick the brand
# voice ONCE. usage: voice-samples.sh [voice ...]  (default: ash verse ballad)
. "$(dirname "$0")/lib.sh"

need_openai_key
if [ $# -gt 0 ]; then VOICES=("$@"); else VOICES=(ash verse ballad); fi
OUTDIR="$ROOT/out/voice-samples"
mkdir -p "$OUTDIR"

SAMPLE_TEXT="gm. it's Friday, August twenty-first. here's the morning show. \
bitcoin punched through seventy-nine thousand dollars overnight, up thirty \
percent in four days. what that actually means: the market added four hundred \
fifty billion dollars while you were asleep, and the options desks flipped \
from fear to greed. that's the show. full paper at g m sers dot com."

INSTRUCTIONS="Morning news host: warm, dry, unhurried, lightly amused. \
Conversational pace around 155 words per minute. Small pauses between \
stories. Never salesy or hypey."

for v in "${VOICES[@]}"; do
  OUT="$OUTDIR/$v.mp3"
  log "sample: $v"
  BODY="$(python3 - "$v" "$SAMPLE_TEXT" "$INSTRUCTIONS" <<'EOF'
import json, sys
print(json.dumps({"model": "gpt-4o-mini-tts", "voice": sys.argv[1],
                  "input": sys.argv[2], "instructions": sys.argv[3],
                  "response_format": "mp3"}))
EOF
)"
  HTTP=$(curl -sS -o "$OUT.tmp" -w '%{http_code}' https://api.openai.com/v1/audio/speech \
    -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
    -d "$BODY")
  [ "$HTTP" = "200" ] || { log "API error: $(head -c 300 "$OUT.tmp")"; rm -f "$OUT.tmp"; die "TTS HTTP $HTTP for voice $v"; }
  mv "$OUT.tmp" "$OUT"
done

echo
echo "samples ready — listen and pick one:"
for v in "${VOICES[@]}"; do echo "  afplay $OUTDIR/$v.mp3"; done
