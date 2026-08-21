#!/usr/bin/env bash
# stage 3: voice.mp3 -> word timestamps (whisper) -> captions.ass
# usage: 03-captions.sh <workdir>
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 03-captions.sh <workdir>}"
AUDIO="$WORK/voice.mp3"
WORDS="$WORK/words.json"
ASS="$WORK/captions.ass"

[ -s "$AUDIO" ] || die "no audio at $AUDIO — run 02-tts.sh first"
need_openai_key

if ! skip_if_fresh "$WORDS" "$AUDIO"; then
  log "whisper word timestamps…"
  HTTP=$(curl -sS -o "$WORDS.tmp" -w '%{http_code}' \
    https://api.openai.com/v1/audio/transcriptions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -F "file=@$AUDIO" -F model=whisper-1 \
    -F response_format=verbose_json -F 'timestamp_granularities[]=word')
  [ "$HTTP" = "200" ] || { log "API error body: $(head -c 500 "$WORDS.tmp")"; rm -f "$WORDS.tmp"; die "whisper HTTP $HTTP"; }
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d.get('words'), 'no words[] in whisper reply'" "$WORDS.tmp" \
    || { rm -f "$WORDS.tmp"; die "whisper reply has no word timestamps"; }
  mv "$WORDS.tmp" "$WORDS"
fi

skip_if_fresh "$ASS" "$WORDS" && exit 0
python3 "$ROOT/scripts/build_captions.py" "$WORDS" "$ASS"
log "wrote $ASS"
