#!/usr/bin/env bash
# clawd morning show v0 — one entry point.
# usage: make-show.sh <digest.md>  ->  out/show-YYYY-MM-DD.mp4 + suggested tweet
# env: SHOW_DATE=YYYY-MM-DD  FORCE=1 (re-run all stages)  VOICE=<tts voice>
. "$(dirname "$0")/lib.sh"

DIGEST="${1:?usage: make-show.sh <digest.md>}"
[ -s "$DIGEST" ] || die "digest not found or empty: $DIGEST"

SHOW_DATE="${SHOW_DATE:-$(date +%F)}"
export SHOW_DATE
WORK="$ROOT/out/work-$SHOW_DATE"
OUT="$ROOT/out/show-$SHOW_DATE.mp4"
mkdir -p "$WORK"

log "show for $SHOW_DATE — digest: $DIGEST"
"$ROOT/scripts/01-script.sh" "$DIGEST" "$WORK"
HEADLINE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['headline'])" "$WORK/stories.json")"
[ -n "$HEADLINE" ] || HEADLINE="the morning news, read to you"
export HEADLINE
"$ROOT/scripts/02-tts.sh" "$WORK"
"$ROOT/scripts/03-captions.sh" "$WORK"
"$ROOT/scripts/04-cards.sh" "$WORK"
"$ROOT/scripts/05-render.sh" "$WORK" "$OUT"

# ---- suggested tweet (posting NOT wired yet — on purpose) ----
check_ffmpeg   # the summary probe must use the same ffprobe the stages did, not whatever is on PATH
DUR="$(media_duration "$OUT")"

echo
echo "================ show ready ================"
echo "video:  $OUT (${DUR%.*}s)"
echo
echo "suggested tweet:"
echo "gm — today's morning show: $HEADLINE"
echo
echo "full paper: gmsers.com"
echo "============================================"
