#!/usr/bin/env bash
# stage 4: clawd avatar comp — background card + keyed-in avatar + lower-third
# + burned captions + audio -> mp4
#
# timeline: INTRO_S idle cold-open · narration · OUTRO_S idle outro, with the
# clip sequence decided by clawd-video-chat's OWN clawdVid code (stage 3,
# plan_avatar.mjs). Inputs are -stream_loop'd because the rig sets <video
# loop> on chatting_1 / idle_2 (aliased into LOOPING_SRCS). The avatar clips
# (assets/, from clawd-video-chat's clawdassets/) ship on PURE BLACK — not green — so there is no chroma key:
# the show background is pure black and the square clip overlays seamlessly.
# Keying black would eat clawd's tux; don't "fix" this back to colorkey.
#
# usage: 04-render.sh <workdir> <out.mp4>   (HEADLINE env -> lower-third)
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 04-render.sh <workdir> <out.mp4>}"
OUT="${2:?usage: 04-render.sh <workdir> <out.mp4>}"
AUDIO="$WORK/voice.mp3"
ASS="$WORK/captions.ass"
FRAME="$WORK/frame.png"
CHAT="$ROOT/assets/chatting_1.mp4"
IDLE1="$ROOT/assets/idle_1.mp4"
IDLE2="$ROOT/assets/idle_2.mp4"

[ -s "$AUDIO" ] || die "no audio at $AUDIO"
[ -s "$ASS" ] || die "no captions at $ASS"
for f in "$CHAT" "$IDLE1" "$IDLE2"; do [ -s "$f" ] || die "missing avatar asset $f"; done
check_ffmpeg
FONT="$(find_font)"
SHOW_DATE="${SHOW_DATE:-$(date +%F)}"
NICE_DATE="$(date -j -f %Y-%m-%d "$SHOW_DATE" '+%A, %B %-d, %Y' 2>/dev/null || date '+%A, %B %-d, %Y')"

# ---- background card (pure black so the avatar clip merges edgeless) ----
if [ ! -s "$FRAME" ] || [ "${FORCE:-0}" = "1" ]; then
  log "frame: $NICE_DATE"
  printf '%s' "$NICE_DATE" > "$WORK/date.txt"
  "$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "color=c=0x000000:s=1280x720" \
    -vf "\
drawtext=fontfile='$FONT':text='clawd morning show':fontcolor=0x66FF66:fontsize=46:x=(w-text_w)/2:y=34,\
drawtext=fontfile='$FONT':textfile='$WORK/date.txt':fontcolor=0x33AA44:fontsize=24:x=(w-text_w)/2:y=96" \
    -frames:v 1 "$FRAME"
fi

if skip_if_fresh "$OUT" "$ASS" && skip_if_fresh "$OUT" "$AUDIO"; then exit 0; fi

# ---- avatar plan: produced by stage 3 running the rig's own clawdVid code ----
[ -s "$WORK/plan.json" ] && [ -s "$WORK/avatar.filter" ] || die "no avatar plan — run 03-captions.sh first"
TOTAL="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['total'])" "$WORK/plan.json")"
# audio starts MOUTH_LAG_S after the cut to chatting (see lib.sh)
DELAY_MS="$(awk -v i="$INTRO_S" -v l="$MOUTH_LAG_S" 'BEGIN{printf "%d", (i+l)*1000}')"

# bottom ticker: headline + site (from make-show; falls back to the tagline).
# lives at the very bottom edge so it never crosses the avatar's face.
TAGLINE="reading the timeline so you don't have to"
printf '%s · gmsers.com' "${HEADLINE:-$TAGLINE}" > "$WORK/lower3.txt"

# full graph: avatar chain from the plan, then comp + ticker + captions + audio
{ cat "$WORK/avatar.filter"; printf ';\n'
  printf '%s\n' "[avatar]scale=560:560[av];\
[0:v][av]overlay=(W-w)/2:H-h[comp];\
[comp]drawtext=fontfile='$FONT':textfile=lower3.txt:fontcolor=0x99DDAA:fontsize=20:x=(w-text_w)/2:y=684:box=1:boxcolor=0x081008@0.85:boxborderw=12,subtitles=captions.ass,format=yuv420p[v];\
[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,adelay=${DELAY_MS}:all=1,apad[aud]"
} > "$WORK/show.filter"

log "render: $OUT (${TOTAL%.*}s total)"
mkdir -p "$(dirname "$OUT")"
case "$OUT" in /*) ABS_OUT="$OUT";; *) ABS_OUT="$PWD/$OUT";; esac

( cd "$WORK" && "$FFMPEG" -hide_banner -loglevel error -y \
  -framerate 24 -loop 1 -i frame.png \
  -i voice.mp3 \
  -stream_loop -1 -i "$IDLE1" -stream_loop -1 -i "$IDLE2" -stream_loop -1 -i "$CHAT" \
  -filter_complex_script show.filter \
  -map "[v]" -map "[aud]" -t "$TOTAL" -r 24 \
  -c:v libx264 -preset medium -crf 21 -c:a aac -b:a 128k \
  -movflags +faststart "$ABS_OUT" )

DUR="$(media_duration "$OUT")"
SIZE=$(du -h "$OUT" | cut -f1 | tr -d ' ')
log "done: $OUT (${DUR%.*}s, $SIZE)"
awk -v d="$DUR" 'BEGIN{exit !(d>140)}' && die "video is ${DUR%.*}s — over the 2:20 X cap"
exit 0
