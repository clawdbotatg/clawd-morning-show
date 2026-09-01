#!/usr/bin/env bash
# stage 4: one stage card per story (theme title + its top tweets) and per
# headline (the line, big, + the tweet it came from), screenshot via the
# cached Playwright Chromium -> $WORK/cards/card-<n>.png (n over both kinds)
# usage: 04-cards.sh <workdir>
. "$(dirname "$0")/lib.sh"
WORK="${1:?usage: 04-cards.sh <workdir>}"
[ -s "$WORK/stories.json" ] && [ -s "$WORK/script.json" ] || die "need stories.json + script.json (stage 1)"
command -v node >/dev/null || die "node not installed"
[ -d "$ROOT/node_modules/playwright-core" ] || die "playwright-core missing — run: npm i (in $ROOT)"
N="$(python3 -c "import json,sys; print(sum(1 for s in json.load(open(sys.argv[1]))['segments'] if s['kind'] in ('story','headline')))" "$WORK/script.json")"
LAST="$WORK/cards/card-$((N-1)).png"
if [ "${FORCE:-0}" != "1" ] && [ -s "$LAST" ] && [ "$LAST" -nt "$WORK/script.json" ] && [ "$LAST" -nt "$ROOT/scripts/render_cards.mjs" ]; then log "fresh: $WORK/cards ($N cards)"; exit 0; fi
rm -rf "$WORK/cards"
rc=0; node "$ROOT/scripts/render_cards.mjs" "$WORK/stories.json" "$WORK/script.json" "$WORK/cards" || rc=$?
if [ "$rc" -eq 2 ]; then
  # exit 2 = no cached chromium — macOS purges ~/Library/Caches under disk
  # pressure (it ate the whole ms-playwright dir on 2026-09-01). Reinstall
  # once and retry rather than losing the morning build.
  log "playwright chromium missing — reinstalling (macOS purged the cache?)"
  (cd "$ROOT" && npx --yes playwright install chromium) || die "npx playwright install chromium failed"
  rm -rf "$WORK/cards"
  rc=0; node "$ROOT/scripts/render_cards.mjs" "$WORK/stories.json" "$WORK/script.json" "$WORK/cards" || rc=$?
fi
[ "$rc" -eq 0 ] && [ -s "$LAST" ] || die "card render produced no $LAST"
log "wrote $N cards -> $WORK/cards"
