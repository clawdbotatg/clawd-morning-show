#!/usr/bin/env bash
# stage 3: word timings -> captions.ass. The timings normally arrive WITH the
# audio (ElevenLabs with-timestamps in stage 2); if they're missing (the `say`
# dev fallback), synthesize uniform ones — loudly, they drift.
# usage: 03-captions.sh <workdir>
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 03-captions.sh <workdir>}"
AUDIO="$WORK/voice.mp3"
WORDS="$WORK/words.json"
ASS="$WORK/captions.ass"

[ -s "$AUDIO" ] || die "no audio at $AUDIO — run 02-tts.sh first"

if [ ! -s "$WORDS" ] || { [ "$AUDIO" -nt "$WORDS" ] && [ "${FORCE:-0}" = "1" ]; }; then
  log "WARNING: no word timings from TTS — synthetic uniform timings, captions will drift"
  check_ffmpeg
  DUR="$(media_duration "$AUDIO")"
  python3 - "$WORK/script.txt" "$DUR" > "$WORDS" <<'EOF'
import json, sys
words = open(sys.argv[1]).read().split()
dur = float(sys.argv[2])
step = dur / len(words)
json.dump({"words": [{"word": w, "start": round(i*step, 3),
                      "end": round((i+1)*step, 3)}
                     for i, w in enumerate(words)]}, sys.stdout)
EOF
fi

skip_if_fresh "$ASS" "$WORDS" && exit 0
# narration starts after the idle cold-open — shift captions with it
python3 "$ROOT/scripts/build_captions.py" "$WORDS" "$ASS" "$INTRO_S"
log "wrote $ASS (offset +${INTRO_S}s)"
