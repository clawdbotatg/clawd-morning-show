#!/bin/bash
# launchd entry (com.clawd.morning-show): wait for today's digest from
# clawd-morning-update (its report lands ~7:39 Denver), make the show, and
# drop the finished mp4 + suggested tweet into Austin's Telegram via
# clawd-twitter's tg-send.js (sendVideo for .mp4). Posting to X is NOT
# wired — Austin posts it himself. Any failure here is logged and reported
# on Telegram; the normal 8:02 gm tweet (clawd-twitter) is untouched.
# usage: scripts/cron.sh            (log: out/cron.log; lock: out/.ran-show-<date>)
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/opt/ffmpeg-full/bin:/opt/homebrew/bin:/usr/bin:/bin"
cd "$(dirname "$0")/.."
mkdir -p out
exec >> out/cron.log 2>&1

DATE="$(date +%F)"
LOCK="out/.ran-show-$DATE"
[ -f "$LOCK" ] && { echo "already ran $DATE"; exit 0; }
echo "=== show run $(date) ==="

DIGEST="../clawd-morning-update/state/digest.md"
TG="../clawd-twitter/scripts/tg-send.js"
fresh() { head -1 "$DIGEST" 2>/dev/null | grep -q -- "$DATE"; }   # "# twitter vibe — YYYY-MM-DD"

# wait up to 30 min for today's digest — the report may run late or be retried
for _ in $(seq 1 60); do fresh && break; sleep 30; done
if ! fresh; then
  echo "no digest for $DATE after 30 min — skipping (gm tweet unaffected)"
  node "$TG" "morning show: no digest for $DATE, skipped 🦞" || true
  exit 0
fi
touch "$LOCK"

OUT="out/show-$DATE.mp4"
if SHOW_DATE="$DATE" ./scripts/make-show.sh "$DIGEST" > "out/tweet-$DATE.txt"; then
  TWEET="$(sed -n '/^suggested tweet:/,/^=====/p' "out/tweet-$DATE.txt" | sed '1d;$d' | sed '/^$/d')"
  DUR="$(sed -nE 's/^video: .*\(([0-9]+)s\)$/\1/p' "out/tweet-$DATE.txt")"
  echo "show ready: $OUT (${DUR}s)"
  node "$TG" "morning show $DATE (${DUR}s) — suggested tweet:
$TWEET
🦞" "$OUT" || echo "tg-send failed — show built at $OUT, not delivered"
else
  echo "make-show FAILED for $DATE (see above)"
  node "$TG" "morning show FAILED for $DATE — see clawd-morning-show/out/cron.log 🦞" || true
  exit 1
fi
echo "=== show run done $(date) ==="
