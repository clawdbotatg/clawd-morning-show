#!/usr/bin/env bash
# stage 4b (OPTIONAL): animated background via vgpu (headless WebGPU on the
# machine's own GPU) -> work/bg.mp4. 05-render uses bg.mp4 as the base layer
# when it exists and falls back to the black branded frame when it doesn't.
#
# THIS STAGE MUST NEVER FAIL THE PIPELINE. Missing node, missing node_modules,
# no GPU, a vgpu crash, a hang — all degrade to "no bg.mp4" and the show
# renders exactly as before this stage existed. Exit code is always 0.
# VGPU_BG=0 opts out (and clears any stale bg.mp4).
. "$(dirname "$0")/lib.sh"

WORK="${1:?usage: 04b-bg.sh <workdir>}"

if [ "${VGPU_BG:-1}" != "1" ]; then
  rm -f "$WORK/bg.mp4"
  log "vgpu bg disabled (VGPU_BG=0)"
  exit 0
fi

# inputs: plan.json (timeline) + the voice (levels). No plan -> no bg, no fuss.
if [ ! -s "$WORK/plan.json" ] || { [ ! -s "$WORK/voice.mp3" ] && [ ! -s "$WORK/voice.norm.wav" ]; }; then
  log "vgpu bg: missing plan/voice — skipping (show falls back to black)"
  rm -f "$WORK/bg.mp4"
  exit 0
fi
skip_if_fresh "$WORK/bg.mp4" "$WORK/plan.json" && exit 0

check_ffmpeg
rm -f "$WORK/bg.mp4"

# price sparklines (btc/eth/$CLAWD) — optional input to the render; a fetch
# failure just means fewer (or no) sparklines. Never blocks the show.
node "$ROOT/scripts/fetch_prices.mjs" "$WORK" >> "$WORK/bg-prices.log" 2>&1 || \
  log "price fetch failed — rendering without sparklines"

# watchdog: a hung GPU render at 7:40am must not stall the show into the gm
# window. 180s is ~15x the measured render time for a full 2:20 show.
node "$ROOT/scripts/render_bg.mjs" "$WORK" > "$WORK/bg.log" 2>&1 &
BG_PID=$!
BG_OK=0
for i in $(seq 1 180); do
  if ! kill -0 "$BG_PID" 2>/dev/null; then
    if wait "$BG_PID"; then BG_OK=1; fi
    break
  fi
  sleep 1
done
if [ "$BG_OK" != "1" ]; then
  kill -9 "$BG_PID" 2>/dev/null || true
  wait "$BG_PID" 2>/dev/null || true
fi

if [ "$BG_OK" = "1" ] && [ -s "$WORK/bg.mp4" ]; then
  log "vgpu bg ready: $WORK/bg.mp4 ($(tail -1 "$WORK/bg.log" 2>/dev/null))"
else
  log "vgpu bg FAILED — show falls back to black (see $WORK/bg.log)"
  rm -f "$WORK/bg.mp4"
  exit 0
fi

# label pass: burn the sparkline price labels into bg.mp4 (Monaco, colors
# matching the shader's lines). Optional like everything here — on failure
# the unlabeled bg is kept. Coordinates pair with SPARK_RECTS in render_bg.mjs.
FONT="$(find_font)"
LABELS=""
[ -s "$WORK/tick-btc.txt" ]   && LABELS="${LABELS}drawtext=fontfile='$FONT':textfile=tick-btc.txt:fontcolor=0xD98F33:fontsize=15:x=36:y=62:shadowcolor=black:shadowx=1:shadowy=1:expansion=none,"
[ -s "$WORK/tick-eth.txt" ]   && LABELS="${LABELS}drawtext=fontfile='$FONT':textfile=tick-eth.txt:fontcolor=0x8093DD:fontsize=15:x=36:y=118:shadowcolor=black:shadowx=1:shadowy=1:expansion=none,"
[ -s "$WORK/tick-clawd.txt" ] && LABELS="${LABELS}drawtext=fontfile='$FONT':textfile=tick-clawd.txt:fontcolor=0x66E699:fontsize=15:x=980:y=94:shadowcolor=black:shadowx=1:shadowy=1:expansion=none,"
if [ -n "$LABELS" ]; then
  if ( cd "$WORK" && "$FFMPEG" -hide_banner -loglevel error -y -i bg.mp4 \
        -vf "${LABELS%,}" -c:v libx264 -pix_fmt yuv420p -crf 18 bg.labeled.mp4 ); then
    mv "$WORK/bg.labeled.mp4" "$WORK/bg.mp4"
    log "sparkline labels: $(cat "$WORK"/tick-*.txt 2>/dev/null | tr '\n' ' ')"
  else
    rm -f "$WORK/bg.labeled.mp4"
    log "label pass failed — keeping unlabeled bg"
  fi
fi
exit 0
