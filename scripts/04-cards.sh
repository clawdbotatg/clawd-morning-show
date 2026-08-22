#!/usr/bin/env bash
# stage 4: one stage card per story (theme title + its top tweets), screenshot
# via the cached Playwright Chromium -> $WORK/cards/story-<n>.png
# usage: 04-cards.sh <workdir>
. "$(dirname "$0")/lib.sh"
WORK="${1:?usage: 04-cards.sh <workdir>}"
[ -s "$WORK/stories.json" ] && [ -s "$WORK/script.json" ] || die "need stories.json + script.json (stage 1)"
command -v node >/dev/null || die "node not installed"
[ -d "$ROOT/node_modules/playwright-core" ] || die "playwright-core missing — run: npm i (in $ROOT)"
N="$(python3 -c "import json,sys; print(sum(1 for s in json.load(open(sys.argv[1]))['segments'] if s['kind']=='story'))" "$WORK/script.json")"
LAST="$WORK/cards/story-$((N-1)).png"
if [ "${FORCE:-0}" != "1" ] && [ -s "$LAST" ] && [ "$LAST" -nt "$WORK/script.json" ]; then log "fresh: $WORK/cards ($N cards)"; exit 0; fi
rm -rf "$WORK/cards"
node "$ROOT/scripts/render_cards.mjs" "$WORK/stories.json" "$WORK/script.json" "$WORK/cards"
[ -s "$LAST" ] || die "card render produced no $LAST"
log "wrote $N cards -> $WORK/cards"
