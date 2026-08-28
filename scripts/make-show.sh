#!/usr/bin/env bash
# clawd morning show v0 — one entry point.
# usage: make-show.sh <digest.md>  ->  out/show-YYYY-MM-DD.mp4 + suggested tweet
# env: SHOW_DATE=YYYY-MM-DD  FORCE=1 (re-run all stages)  VOICE=<tts voice>
#      SHOW_KIND=morning|explainer|topic — explainer = a 45-80s tl;dr of one
#      thread; topic = a 50-90s what-is-X from a researched brief (clawd-twitter
#      explainer.sh writes it)
#      (brief.md from fetch-thread.mjs; see make-explainer.sh), same stages,
#      its own prompt/validator/frame text.
. "$(dirname "$0")/lib.sh"

DIGEST="${1:?usage: make-show.sh <digest.md>}"
[ -s "$DIGEST" ] || die "digest not found or empty: $DIGEST"

SHOW_DATE="${SHOW_DATE:-$(date +%F)}"
SHOW_KIND="${SHOW_KIND:-morning}"
case "$SHOW_KIND" in morning|explainer|topic) ;; *) die "SHOW_KIND must be morning, explainer or topic, got $SHOW_KIND";; esac
export SHOW_DATE SHOW_KIND
WORK="$ROOT/out/work-$SHOW_DATE"
OUT="$ROOT/out/show-$SHOW_DATE.mp4"
mkdir -p "$WORK"

log "$SHOW_KIND show for $SHOW_DATE — digest: $DIGEST"
"$ROOT/scripts/01-script.sh" "$DIGEST" "$WORK"
HEADLINE="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['headline'])" "$WORK/stories.json")"
[ -n "$HEADLINE" ] || HEADLINE="the morning news, read to you"
if [ "$SHOW_KIND" != morning ]; then
  # frame: "clawd explains" / headline; ticker: the link in the brief intro
  # (explainer: the thread; topic: the primary source)
  export FRAME_TITLE="clawd explains" FRAME_SUB="$HEADLINE" MIN_AUDIO_S=20
  LINK="$(python3 -c "import json,re,sys; m=re.search(r'https?://\S+', json.load(open(sys.argv[1]))['intro']); print(m.group(0).replace('https://','') if m else '')" "$WORK/stories.json")"
  [ -n "$LINK" ] && HEADLINE="$LINK"
fi
export HEADLINE
"$ROOT/scripts/02-tts.sh" "$WORK"
"$ROOT/scripts/03-captions.sh" "$WORK"
"$ROOT/scripts/04-cards.sh" "$WORK"
"$ROOT/scripts/04b-bg.sh" "$WORK"   # optional animated bg — never fails the run
"$ROOT/scripts/05-render.sh" "$WORK" "$OUT"

# ---- suggested tweet (posting is clawd-twitter's job) ----
check_ffmpeg   # the summary probe must use the same ffprobe the stages did, not whatever is on PATH
DUR="$(media_duration "$OUT")"

echo
echo "================ show ready ================"
echo "video:  $OUT (${DUR%.*}s)"
echo
if [ "$SHOW_KIND" != morning ]; then
  echo "suggested reply:"
  echo "tl;dr of this thread 🦞"
else
  echo "suggested tweet:"
  echo "gm — today's morning show: $HEADLINE"
  echo
  echo "full paper: gmsers.com"
fi
echo "============================================"
