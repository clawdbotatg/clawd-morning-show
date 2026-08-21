#!/usr/bin/env bash
# stage 1: digest.md -> spoken script (~320 words) via claude -p
# usage: 01-script.sh <digest.md> <workdir>
. "$(dirname "$0")/lib.sh"

DIGEST="${1:?usage: 01-script.sh <digest.md> <workdir>}"
WORK="${2:?usage: 01-script.sh <digest.md> <workdir>}"
OUT="$WORK/script.txt"

[ -s "$DIGEST" ] || die "digest not found or empty: $DIGEST"
command -v claude >/dev/null || die "claude CLI not on PATH"
mkdir -p "$WORK"
skip_if_fresh "$OUT" "$DIGEST" && exit 0

scrub_claude_env

run_pass() { # $1 = extra instruction (may be empty)
  { cat "$ROOT/prompts/host.md"
    [ -n "$1" ] && printf '\nEXTRA INSTRUCTION: %s\n' "$1"
    printf '\n--- TODAY'\''S DIGEST ---\n'
    cat "$DIGEST"
  } | claude -p --model sonnet
}

log "script pass (claude -p)…"
SCRIPT="$(run_pass "")"
WORDS=$(wc -w <<<"$SCRIPT" | tr -d ' ')
log "draft: $WORDS words"

if [ "$WORDS" -gt 320 ] || [ "$WORDS" -lt 200 ]; then
  log "out of range ($WORDS words) — one corrective pass"
  SCRIPT="$(run_pass "Your previous draft was $WORDS words. The script MUST be 270-300 words. Rewrite tighter.")"
  WORDS=$(wc -w <<<"$SCRIPT" | tr -d ' ')
  log "retry: $WORDS words"
fi

[ "$WORDS" -ge 150 ] || die "script pass returned $WORDS words — claude -p likely failed"
[ "$WORDS" -le 340 ] || die "script is $WORDS words even after retry — at ~140 wpm that blows the 2:20 video cap"

printf '%s\n' "$SCRIPT" > "$OUT"
log "wrote $OUT ($WORDS words)"
