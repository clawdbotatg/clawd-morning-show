# shared helpers for the morning-show pipeline. source, don't execute.
# every stage: set -euo pipefail, loud failures, idempotent via skip_if_fresh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# show timeline: idle cold-open, narration, idle outro. 03 (caption offset)
# and 04 (comp timing) must agree, so the numbers live here.
INTRO_S=2
OUTRO_S=3

log()  { printf '\033[36m[%s]\033[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; }
die()  { printf '\033[31m[%s] FATAL:\033[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; exit 1; }

# load .env (gitignored) — OPENAI_API_KEY lives here, never in git
load_env() {
  if [ -f "$ROOT/.env" ]; then
    set -a; . "$ROOT/.env"; set +a
  fi
}

# skip a stage when its output already exists and is newer than the input.
# usage: skip_if_fresh <out> <in> && exit 0 (FORCE=1 always re-runs)
skip_if_fresh() {
  local out="$1" in="$2"
  [ "${FORCE:-0}" = "1" ] && return 1
  [ -s "$out" ] && [ "$out" -nt "$in" ] && { log "fresh: $out (FORCE=1 to redo)"; return 0; }
  return 1
}

# a nested `claude` inherits harness/session env and silently flips into
# embedded mode (no transcript, metered API billing) — scrub before claude -p.
scrub_claude_env() {
  local v
  for v in $(env | grep -oE '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|ANTHROPIC_API_KEY|ANTHROPIC_[A-Z_]+)' || true); do
    unset "$v"
  done
}

# monospace font for the branded frame (drawtext needs a file path)
find_font() {
  local f
  for f in /System/Library/Fonts/Monaco.ttf \
           /System/Library/Fonts/Menlo.ttc \
           /System/Library/Fonts/Supplemental/Courier\ New.ttf \
           /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  die "no monospace font found for drawtext"
}

# resolve an ffmpeg with the filters v0 needs (brew's plain `ffmpeg` bottle
# dropped libass/freetype — `ffmpeg-full` is keg-only, so probe for it).
# sets FFMPEG + FFPROBE; $FFMPEG in the environment wins.
check_ffmpeg() {
  local cand have
  for cand in "${FFMPEG:-}" /opt/homebrew/opt/ffmpeg-full/bin/ffmpeg \
              /usr/local/opt/ffmpeg-full/bin/ffmpeg "$(command -v ffmpeg || true)"; do
    [ -n "$cand" ] && [ -x "$cand" ] || continue
    have="$("$cand" -hide_banner -filters 2>/dev/null)" || continue
    if grep -q ' subtitles ' <<<"$have" && grep -q ' drawtext ' <<<"$have" \
       && grep -q ' showwaves ' <<<"$have" && grep -q ' loudnorm ' <<<"$have"; then
      FFMPEG="$cand"
      FFPROBE="$(dirname "$cand")/ffprobe"
      [ -x "$FFPROBE" ] || FFPROBE="$(command -v ffprobe)" || die "no ffprobe next to $FFMPEG"
      export FFMPEG FFPROBE
      return 0
    fi
  done
  die "no ffmpeg with subtitles+drawtext+showwaves+loudnorm found (brew install ffmpeg-full)"
}

media_duration() { # seconds (float) of an audio/video file
  "${FFPROBE:-ffprobe}" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1"
}
