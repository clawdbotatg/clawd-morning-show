#!/usr/bin/env bash
# stage 1: digest.md -> spoken script via claude -p, as JSON segments
# (intro / story×N / outro, each story tagged with its digest ## heading so
# the render can put that story's tweets on screen). Writes script.json and
# script.txt (the joined text TTS reads).
# usage: 01-script.sh <digest.md> <workdir>
. "$(dirname "$0")/lib.sh"

DIGEST="${1:?usage: 01-script.sh <digest.md> <workdir>}"
WORK="${2:?usage: 01-script.sh <digest.md> <workdir>}"
OUT="$WORK/script.json"
TXT="$WORK/script.txt"
STORIES="$WORK/stories.json"

[ -s "$DIGEST" ] || die "digest not found or empty: $DIGEST"
command -v claude >/dev/null || die "claude CLI not on PATH"
mkdir -p "$WORK"
python3 "$ROOT/scripts/digest_parse.py" "$DIGEST" "$STORIES"
skip_if_fresh "$OUT" "$DIGEST" && skip_if_fresh "$TXT" "$OUT" && exit 0

scrub_claude_env

run_pass() { # $1 = extra instruction (may be empty) -> raw model output
  { cat "$ROOT/prompts/host.md"
    [ -n "$1" ] && printf '\nEXTRA INSTRUCTION: %s\n' "$1"
    printf '\n--- TODAY'\''S DIGEST ---\n'
    cat "$DIGEST"
  } | claude -p --model sonnet
}

# validate + normalize the model's JSON against the digest; prints a one-line
# problem description on failure, the word count on success
validate() { # reads $WORK/script.raw -> writes $OUT + $TXT
  python3 - "$STORIES" "$OUT" "$TXT" "$WORK/script.raw" <<'PY'
import json, re, sys
raw = open(sys.argv[4]).read().strip()
raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)          # tolerate fences
m = re.search(r"\{[\s\S]*\}", raw)
if not m: sys.exit("no JSON object in output")
try: d = json.loads(m.group(0))
except Exception as e: sys.exit(f"bad JSON: {e}")
segs = d.get("segments")
if not isinstance(segs, list) or len(segs) < 3: sys.exit("need >=3 segments")
themes = {t["title"].strip().lower(): t["title"] for t in json.load(open(sys.argv[1]))["themes"]}
kinds = [s.get("kind") for s in segs]
if kinds[0] != "intro" or kinds[-1] != "outro" or any(k != "story" for k in kinds[1:-1]):
    sys.exit(f"segment kinds must be intro, story…, outro — got {kinds}")
for s in segs:
    if not str(s.get("text", "")).strip(): sys.exit("empty segment text")
    if s["kind"] == "story":
        key = str(s.get("theme", "")).strip().lower()
        if key not in themes: sys.exit(f"story theme not a digest heading: {s.get('theme')!r}")
        s["theme"] = themes[key]
words = sum(len(s["text"].split()) for s in segs)
json.dump({"segments": segs, "words": words}, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
open(sys.argv[3], "w").write("\n\n".join(s["text"].strip() for s in segs) + "\n")
print(words)
PY
}

log "script pass (claude -p)…"
run_pass "" > "$WORK/script.raw"
if WORDS="$(validate 2>&1)"; then :; else
  log "invalid ($WORDS) — one corrective pass"
  run_pass "Your previous output was rejected: $WORDS. Output ONLY the JSON described, with exact digest headings." > "$WORK/script.raw"
  WORDS="$(validate 2>&1)" || die "script pass invalid after retry: $WORDS"
fi
log "draft: $WORDS words"

if [ "$WORDS" -gt 320 ] || [ "$WORDS" -lt 200 ]; then
  log "out of range ($WORDS words) — one corrective pass"
  run_pass "Your previous draft was $WORDS words. The script MUST be 270-300 words total. Rewrite tighter, same JSON format." > "$WORK/script.raw"
  WORDS="$(validate 2>&1)" || die "script pass invalid after length retry: $WORDS"
  log "retry: $WORDS words"
fi
[ "$WORDS" -ge 150 ] || die "script pass returned $WORDS words — claude -p likely failed"
[ "$WORDS" -le 340 ] || die "script is $WORDS words even after retry — at ~150 wpm that blows the 2:20 video cap"
log "wrote $OUT + $TXT ($WORDS words, $(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['segments'])-2)" "$OUT") stories)"
