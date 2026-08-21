#!/usr/bin/env bash
# stage 4: branded frame + waveform + burned captions + audio -> mp4
# usage: 04-render.sh <workdir> <out.mp4>
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 04-render.sh <workdir> <out.mp4>}"
OUT="${2:?usage: 04-render.sh <workdir> <out.mp4>}"
AUDIO="$WORK/voice.mp3"
ASS="$WORK/captions.ass"
FRAME="$WORK/frame.png"

[ -s "$AUDIO" ] || die "no audio at $AUDIO"
[ -s "$ASS" ] || die "no captions at $ASS"
check_ffmpeg
FONT="$(find_font)"
SHOW_DATE="${SHOW_DATE:-$(date +%F)}"
NICE_DATE="$(date -j -f %Y-%m-%d "$SHOW_DATE" '+%A, %B %-d, %Y' 2>/dev/null || date '+%A, %B %-d, %Y')"

# ---- branded frame (static 1280x720, terminal aesthetic) ----
if [ ! -s "$FRAME" ] || [ "${FORCE:-0}" = "1" ]; then
  log "frame: $NICE_DATE"
  printf '%s' "$NICE_DATE" > "$WORK/date.txt"
  printf '%s' "> reading the timeline so you don't have to_" > "$WORK/tagline.txt"
  "$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i "color=c=0x0A0F0A:s=1280x720" \
    -vf "\
drawtext=fontfile='$FONT':text='clawd morning show':fontcolor=0x66FF66:fontsize=58:x=(w-text_w)/2:y=96,\
drawtext=fontfile='$FONT':textfile='$WORK/date.txt':fontcolor=0x33AA44:fontsize=28:x=(w-text_w)/2:y=180,\
drawtext=fontfile='$FONT':textfile='$WORK/tagline.txt':fontcolor=0x2A7A38:fontsize=22:x=(w-text_w)/2:y=232,\
drawbox=x=0:y=409:w=1280:h=2:color=0x1E4527:t=fill,\
drawtext=fontfile='$FONT':text='gmsers.com':fontcolor=0x2A7A38:fontsize=22:x=(w-text_w)/2:y=686" \
    -frames:v 1 "$FRAME"
fi

if skip_if_fresh "$OUT" "$ASS" && skip_if_fresh "$OUT" "$AUDIO"; then exit 0; fi

# ---- mux: loop the frame, waveform mid-screen, captions bottom ----
log "render: $OUT"
mkdir -p "$(dirname "$OUT")"
case "$OUT" in /*) ABS_OUT="$OUT";; *) ABS_OUT="$PWD/$OUT";; esac
( cd "$WORK" && "$FFMPEG" -hide_banner -loglevel error -y \
  -loop 1 -i frame.png -i voice.mp3 \
  -filter_complex "\
[1:a]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,asplit[a1][a2];\
[a1]showwaves=s=1280x220:mode=cline:rate=25:colors=0x33FF66@0.85[wav];\
[0:v][wav]overlay=0:300:format=auto,subtitles=captions.ass,format=yuv420p[v]" \
  -map "[v]" -map "[a2]" -r 25 -c:v libx264 -preset medium -crf 21 \
  -c:a aac -b:a 128k -shortest -movflags +faststart "$ABS_OUT" )

DUR="$(media_duration "$OUT")"
SIZE=$(du -h "$OUT" | cut -f1 | tr -d ' ')
log "done: $OUT (${DUR%.*}s, $SIZE)"
awk -v d="$DUR" 'BEGIN{exit !(d>140)}' && die "video is ${DUR%.*}s — over the 2:20 X cap"
exit 0
