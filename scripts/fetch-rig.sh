#!/usr/bin/env bash
# vendor clawd-video-chat's index.html — the avatar state machine + TTS
# chunking rules are executed FROM this file at build time (plan_avatar.mjs),
# so the show can't drift from the rig. Re-run to pick up rig changes.
. "$(dirname "$0")/lib.sh"
REPO="${RIG_REPO:-clawdbotatg/clawd-video-chat}"
DEST="$ROOT/assets/rig"
mkdir -p "$DEST"
SHA="$(curl -sfL "https://api.github.com/repos/$REPO/commits/main" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')" \
  || die "could not resolve $REPO main"
curl -sfL "https://raw.githubusercontent.com/$REPO/$SHA/index.html" -o "$DEST/index.html.tmp" || die "fetch failed"
grep -q 'const clawdVid = (() => {' "$DEST/index.html.tmp" || die "fetched index.html has no clawdVid block"
mv "$DEST/index.html.tmp" "$DEST/index.html"
printf 'https://github.com/%s/blob/%s/index.html\n' "$REPO" "$SHA" > "$DEST/SOURCE"
log "vendored $REPO@${SHA:0:7} -> assets/rig/index.html"
