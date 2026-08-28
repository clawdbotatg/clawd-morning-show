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
fi
exit 0
