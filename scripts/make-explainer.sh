#!/usr/bin/env bash
# clawd explains a thread: fetch it (fetch-thread.mjs, via clawd-twitter's
# bearer token) -> digest-shaped brief.md -> the normal five stages with
# SHOW_KIND=explainer -> out/show-x-<rootid>.mp4 (45–80s) + a suggested
# reply on stdout. Nothing is posted from here; clawd-twitter's reply-video.js
# takes the mp4. Idempotent: a re-run whose fetch changed nothing but the
# timestamp rebuilds nothing.
# usage: make-explainer.sh <tweet url | id> ["what was asked"]
# env: FORCE=1  THREAD_REPLIES=30  SHOW_CLAUDE_DIR=<claude config dir>
. "$(dirname "$0")/lib.sh"

TWEET="${1:?usage: make-explainer.sh <tweet url|id> [ask]}"
ASK="${2:-}"
command -v node >/dev/null || die "node not installed"
[ -d "$ROOT/../clawd-twitter/lib" ] || die "needs ../clawd-twitter (its lib/clients.js + .env hold the X bearer token)"

TMP="$ROOT/out/fetch-$$"
ROOT_ID="$(node "$ROOT/scripts/fetch-thread.mjs" "$TWEET" "$TMP" "$ASK")" || { rm -rf "$TMP"; die "fetch-thread failed for $TWEET"; }
[ -n "$ROOT_ID" ] || { rm -rf "$TMP"; die "fetch-thread returned no root id"; }
WORK="$ROOT/out/work-x-$ROOT_ID"
mkdir -p "$WORK"
# keep the old brief (and so every downstream mtime) when only the fetched-at line moved
if [ -s "$WORK/brief.md" ] && diff -q <(grep -v '^_.*fetched' "$WORK/brief.md") <(grep -v '^_.*fetched' "$TMP/brief.md") >/dev/null; then
  log "thread unchanged — keeping $WORK/brief.md"
else
  mv "$TMP/brief.md" "$WORK/brief.md"
fi
mv -f "$TMP/thread.json" "$WORK/thread.json"; rm -rf "$TMP"

SHOW_KIND=explainer SHOW_DATE="x-$ROOT_ID" exec "$ROOT/scripts/make-show.sh" "$WORK/brief.md"
