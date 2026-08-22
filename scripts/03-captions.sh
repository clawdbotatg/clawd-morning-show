#!/usr/bin/env bash
# stage 3: run clawd-video-chat's own avatar code + TTS chunking against the
# show's timings (plan_avatar.mjs) -> plan.json + avatar.filter, then the
# chunk captions -> captions.ass. Timings come with the audio (ElevenLabs
# alignment); the `say` dev fallback has none, so synthesize uniform ones —
# loudly, they drift.
# usage: 03-captions.sh <workdir>
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 03-captions.sh <workdir>}"
AUDIO="$WORK/voice.mp3"
WORDS="$WORK/words.json"
PLAN="$WORK/plan.json"
ASS="$WORK/captions.ass"
RIG="$ROOT/assets/rig/index.html"

[ -s "$AUDIO" ] || die "no audio at $AUDIO — run 02-tts.sh first"
[ -s "$RIG" ] || die "no vendored rig at $RIG — run scripts/fetch-rig.sh"
command -v node >/dev/null || die "node not installed (needed to run the rig's avatar code)"
check_ffmpeg

if [ ! -s "$WORDS" ] || { [ "$AUDIO" -nt "$WORDS" ] && [ "${FORCE:-0}" = "1" ]; }; then
  log "WARNING: no word timings from TTS — synthetic uniform timings, captions will drift"
  DUR="$(media_duration "$AUDIO")"
  python3 - "$WORK/script.txt" "$DUR" > "$WORDS" <<'PY'
import json, sys
words = open(sys.argv[1]).read().split()
dur = float(sys.argv[2])
step = dur / len(words)
json.dump({"words": [{"word": w, "start": round(i*step, 3),
                      "end": round((i+1)*step, 3)}
                     for i, w in enumerate(words)]}, sys.stdout)
PY
fi

if skip_if_fresh "$PLAN" "$WORDS" && skip_if_fresh "$PLAN" "$RIG" && skip_if_fresh "$ASS" "$PLAN"; then exit 0; fi

A="$ROOT/assets"
node "$ROOT/scripts/plan_avatar.mjs" "$RIG" "$WORDS" "$WORK/script.txt" "$INTRO_S" "$OUTRO_S" \
  "$(media_duration "$AUDIO")" \
  "$(media_duration "$A/idle_1.mp4")" "$(media_duration "$A/idle_2.mp4")" "$(media_duration "$A/chatting_1.mp4")" \
  "${PLAN_SEED:-${SHOW_DATE:-$(date +%F)}}" "$PLAN" "$WORK/avatar.filter"
python3 "$ROOT/scripts/build_captions.py" "$PLAN" "$ASS"
log "wrote $PLAN + $ASS"
