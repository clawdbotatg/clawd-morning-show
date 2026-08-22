#!/usr/bin/env bash
# stage 5: the comp. clawd full-frame for the intro/outro; during the stories
# he shrinks to a bottom-right PIP and each story's tweet card (stage 4)
# takes the stage on the left, swapped on the story's start time
# (plan.layout from stage 3). Hard cuts throughout, like the rig.
#
# timeline: INTRO_S idle cold-open · narration · OUTRO_S idle outro, with the
# clip sequence decided by clawd-video-chat's OWN clawdVid code (stage 3,
# plan_avatar.mjs). Inputs are -stream_loop'd because the rig sets <video
# loop> on chatting_1 / idle_2 (aliased into LOOPING_SRCS). The avatar clips
# (assets/, from clawd-video-chat's clawdassets/) ship on PURE BLACK — not green — so there is no chroma key:
# the show background is pure black and the square clip overlays seamlessly.
# Keying black would eat clawd's tux; don't "fix" this back to colorkey.
#
# usage: 05-render.sh <workdir> <out.mp4>   (HEADLINE env -> bottom ticker)
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 05-render.sh <workdir> <out.mp4>}"
OUT="${2:?usage: 05-render.sh <workdir> <out.mp4>}"
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

# ---- loudness-normalize as a PRE-PASS to wav. loudnorm emits NOPTS frames;
# chained straight into adelay it left the first chunk of audio at t=0 while
# delaying the rest — "gm" played over the idle clip. Keep it out of the
# main graph. ----
NORM="$WORK/voice.norm.wav"
if [ ! -s "$NORM" ] || [ "$AUDIO" -nt "$NORM" ] || [ "${FORCE:-0}" = "1" ]; then
  "$FFMPEG" -hide_banner -loglevel error -y -i "$AUDIO" -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 48000 "$NORM"
fi

# ---- avatar plan: produced by stage 3 running the rig's own clawdVid code ----
[ -s "$WORK/plan.json" ] && [ -s "$WORK/avatar.filter" ] || die "no avatar plan — run 03-captions.sh first"
TOTAL="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['total'])" "$WORK/plan.json")"
# audio starts MOUTH_LAG_S after the cut to chatting (see lib.sh)
DELAY_MS="$(awk -v i="$INTRO_S" -v l="$MOUTH_LAG_S" 'BEGIN{printf "%d", (i+l)*1000}')"

# bottom ticker: headline + site (from make-show; falls back to the tagline).
# lives at the very bottom edge so it never crosses the avatar's face.
TAGLINE="reading the timeline so you don't have to"
printf '%s · gmsers.com' "${HEADLINE:-$TAGLINE}" > "$WORK/lower3.txt"

# ---- layout: PIP window + story cards (from plan.json) ----
# stage card 860x420 at (40,140); PIP avatar 300px at (940,360); full avatar 560px centered.
read -r PIP_S PIP_E NCARDS <<<"$(python3 -c "
import json,sys; L=json.load(open(sys.argv[1]))['layout']; p=L['pip']
print(p['start'] if p else -1, p['end'] if p else -1, len(L['stories']))" "$WORK/plan.json")"
CARD_INPUTS=(); CARD_CHAIN=""
if [ "$NCARDS" -gt 0 ]; then
  for i in $(seq 0 $((NCARDS-1))); do
    [ -s "$WORK/cards/story-$i.png" ] || die "missing card $WORK/cards/story-$i.png — run 04-cards.sh"
    CARD_INPUTS+=(-framerate 24 -loop 1 -i "cards/story-$i.png")
  done
  CARD_CHAIN="$(python3 -c "
import json,sys; L=json.load(open(sys.argv[1]))['layout']
prev='c1'; out=[]
for i,s in enumerate(L['stories']):
    nxt=f'k{i}'; out.append(f\"[{prev}][{5+i}:v]overlay=40:140:enable='between(t,{s['start']},{s['end']})'[{nxt}]\"); prev=nxt
print(';'.join(out)+';' if out else '', end='')" "$WORK/plan.json")"
  LAST_LABEL="k$((NCARDS-1))"
else
  LAST_LABEL="c1"
fi
PIP_ON="between(t,$PIP_S,$PIP_E)"

# full graph: avatar chain from the plan, then full/PIP avatar, cards, ticker, captions, audio
{ cat "$WORK/avatar.filter"; printf ';\n'
  printf '%s\n' "[avatar]split[avA][avB];[avA]scale=560:560[full];[avB]scale=300:300[pip];\
[0:v][full]overlay=360:160:enable='not($PIP_ON)'[c0];\
[c0][pip]overlay=940:360:enable='$PIP_ON'[c1];\
${CARD_CHAIN}\
[$LAST_LABEL]drawtext=fontfile='$FONT':textfile=lower3.txt:fontcolor=0x99DDAA:fontsize=20:x=(w-text_w)/2:y=684:box=1:boxcolor=0x081008@0.85:boxborderw=12,subtitles=captions.ass,format=yuv420p[v];\
[1:a]adelay=${DELAY_MS}:all=1,apad[aud]"
} > "$WORK/show.filter"

log "render: $OUT (${TOTAL%.*}s total)"
mkdir -p "$(dirname "$OUT")"
case "$OUT" in /*) ABS_OUT="$OUT";; *) ABS_OUT="$PWD/$OUT";; esac

( cd "$WORK" && "$FFMPEG" -hide_banner -loglevel error -y \
  -framerate 24 -loop 1 -i frame.png \
  -i voice.norm.wav \
  -stream_loop -1 -i "$IDLE1" -stream_loop -1 -i "$IDLE2" -stream_loop -1 -i "$CHAT" \
  "${CARD_INPUTS[@]}" \
  -filter_complex_script show.filter \
  -map "[v]" -map "[aud]" -t "$TOTAL" -r 24 \
  -c:v libx264 -preset medium -crf 21 -c:a aac -b:a 128k \
  -movflags +faststart "$ABS_OUT" )

# ---- sync self-check: voice onset in the FILE vs the first chatting cut ----
# (measured off the rendered mp4, not the plan — this is what a player sees)
ONSET="$("$FFMPEG" -hide_banner -i "$OUT" -t 15 -af silencedetect=n=-35dB:d=0.2 -f null - 2>&1 \
  | sed -nE 's/.*silence_end: ([0-9.]+).*/\1/p' | head -1)"
FIRST_CHAT="$(python3 -c "
import json,sys; d=json.load(open(sys.argv[1])); t=0
for s in d['segments']:
    if s['clip']=='chatting_1': print(round(t,3)); break
    t+=s['dur']" "$WORK/plan.json")"
[ -n "$ONSET" ] && [ -n "$FIRST_CHAT" ] || die "sync check: could not measure voice onset ($ONSET) / first chatting cut ($FIRST_CHAT)"
awk -v o="$ONSET" -v c="$FIRST_CHAT" -v l="$MOUTH_LAG_S" 'BEGIN{ d=o-(c+l); if (d<0) d=-d; exit !(d<=0.15) }' \
  || die "sync check FAILED: voice starts at ${ONSET}s, chatting cut at ${FIRST_CHAT}s (+lag $MOUTH_LAG_S) — mouth and voice disagree"
log "sync ok: voice onset ${ONSET}s, chatting cut ${FIRST_CHAT}s"

DUR="$(media_duration "$OUT")"
SIZE=$(du -h "$OUT" | cut -f1 | tr -d ' ')
log "done: $OUT (${DUR%.*}s, $SIZE)"
awk -v d="$DUR" 'BEGIN{exit !(d>140)}' && die "video is ${DUR%.*}s — over the 2:20 X cap"
exit 0
