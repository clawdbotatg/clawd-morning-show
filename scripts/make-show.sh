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

HEADLINE="$(grep -m1 '^# ' "$DIGEST" | sed 's/^# //' || true)"
[ -n "$HEADLINE" ] || HEADLINE="the morning news, read to you"
export HEADLINE

log "show for $SHOW_DATE — digest: $DIGEST"
"$ROOT/scripts/01-script.sh" "$DIGEST" "$WORK"
"$ROOT/scripts/02-tts.sh" "$WORK"
"$ROOT/scripts/03-captions.sh" "$WORK"
"$ROOT/scripts/04-render.sh" "$WORK" "$OUT"

# ---- suggested tweet (posting NOT wired yet — on purpose) ----
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
