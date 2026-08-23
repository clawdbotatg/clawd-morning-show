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
# script.json + script.txt land in the same second, so never `-nt` one against the other
KIND="${SHOW_KIND:-morning}"
case "$KIND" in explainer) PROMPT="$ROOT/prompts/explainer.md";; topic) PROMPT="$ROOT/prompts/explainer-topic.md";; *) PROMPT="$ROOT/prompts/host.md";; esac
[ -s "$TXT" ] && skip_if_fresh "$OUT" "$DIGEST" && skip_if_fresh "$OUT" "$PROMPT" && exit 0

scrub_claude_env

# which subscription: under launchd there is no CLAUDE_CONFIG_DIR, so claude -p
# used the plain ~/.claude login — which was at its weekly wall on 2026-08-23
# and answered "You've hit your weekly limit" instead of a script. The harness
# already polls every login's usage; pick_account.py ranks them off that file
# and we walk the list, moving on when an account answers with a limit line.
# Last entry "" = the default login (no CLAUDE_CONFIG_DIR), as before.
ACCOUNTS=()
while IFS= read -r d; do ACCOUNTS+=("$d"); done < <(python3 "$ROOT/scripts/pick_account.py" 2>/dev/null || true)
ACCOUNTS+=("")
[ -n "${SHOW_CLAUDE_DIR:-}" ] && ACCOUNTS=("$SHOW_CLAUDE_DIR")   # hand-pin override

run_pass() { # $1 = extra instruction (may be empty) -> raw model output
  local d out
  for d in "${ACCOUNTS[@]}"; do
    if [ -n "$d" ]; then export CLAUDE_CONFIG_DIR="$d"; else unset CLAUDE_CONFIG_DIR; fi
    out="$({ cat "$PROMPT"
      [ -n "$1" ] && printf '\nEXTRA INSTRUCTION: %s\n' "$1"
      printf '\n--- TODAY'\''S DIGEST ---\n'
      cat "$DIGEST"
    } | claude -p --model sonnet || true)"
    if printf '%s' "$out" | head -c 400 | grep -qiE "hit your .*limit|usage limit|rate limit"; then
      log "account ${d:-default} is at its limit — trying next"
      continue
    fi
    [ -n "$d" ] && log "account: $(basename "$d")"
    printf '%s\n' "$out"; return 0
  done
  printf '%s\n' "$out"   # every account walled: hand the last reply to the validator, which dies loudly
}

# validate + normalize the model's JSON against the digest; prints a one-line
# problem description on failure, the word count on success
validate() { # reads $WORK/script.raw -> writes $OUT + $TXT
  python3 - "$STORIES" "$OUT" "$TXT" "$WORK/script.raw" "$HEADLINE_BREAK_S" "$KIND" <<'PY'
import json, re, sys
KIND = sys.argv[6]
raw = open(sys.argv[4]).read().strip()
raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw)          # tolerate fences
m = re.search(r"\{[\s\S]*\}", raw)
if not m: sys.exit("no JSON object in output")
try: d = json.loads(m.group(0))
except Exception as e: sys.exit(f"bad JSON: {e}")
segs = d.get("segments")
if not isinstance(segs, list) or len(segs) < 3: sys.exit("need >=3 segments")
stories = json.load(open(sys.argv[1]))["themes"]
themes = {t["title"].strip().lower(): t["title"] for t in stories}
handles = {t["title"]: {x["handle"].lower(): x["handle"] for x in t["tweets"]} for t in stories}
kinds = [s.get("kind") for s in segs]
# shape: intro, story×3, headline×10–12, outro (stories strictly before headlines)
mid = kinds[1:-1]
if kinds[0] != "intro" or kinds[-1] != "outro" or any(k not in ("story", "headline") for k in mid):
    sys.exit(f"segment kinds must be intro, story…, headline…, outro — got {kinds}")
ns, nh = mid.count("story"), mid.count("headline")
if mid != ["story"] * ns + ["headline"] * nh: sys.exit("all stories must come before the headlines")
if KIND in ("explainer", "topic"):   # intro, story×N, outro — no headline run
    hi = 3 if KIND == "explainer" else 4
    if not 1 <= ns <= hi: sys.exit(f"{KIND} needs 1-{hi} stories, got {ns}")
    if nh: sys.exit(f"{KIND} has no headline segments, got {nh}")
else:
    if ns != 3: sys.exit(f"need exactly 3 stories, got {ns}")
    if not 8 <= nh <= 13: sys.exit(f"need 10-12 headlines, got {nh}")
for s in segs:
    text = str(s.get("text", "")).strip()
    if not text: sys.exit("empty segment text")
    if "<" in text or ">" in text: sys.exit("segment text must not contain < or >")
    if s["kind"] in ("story", "headline"):
        key = str(s.get("theme", "")).strip().lower()
        if key not in themes: sys.exit(f"{s['kind']} theme not a digest heading: {s.get('theme')!r}")
        s["theme"] = themes[key]
    if s["kind"] == "headline":
        n = len(text.split())
        if n > 18: sys.exit(f"headline too long ({n} words): {text!r}")
        h = str(s.get("handle") or "").lstrip("@").strip().lower()
        s["handle"] = handles[s["theme"]].get(h, "")      # unknown handle -> card falls back to the top tweet
    if s["kind"] == "story" and "what it means" in text.lower(): sys.exit("story uses the banned phrase 'what it means'")
    slop = re.search(r"(half (of )?the timeline|timeline(’s|'s| is)? (split|divided|arguing|debating)|it's not \w+, it's|the real story|here's the thing|in other words|the takeaway|what this means)", text, re.I)
    if slop: sys.exit(f"slop phrase {slop.group(0)!r} in: {text!r}")
words = sum(len(s["text"].split()) for s in segs)
json.dump({"segments": segs, "words": words}, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
# script.txt is what TTS reads: paragraphs, plus a <break> beat before each
# headline (the "read the headline, pause" rhythm). Tags never enter script.json.
brk = f'<break time="{float(sys.argv[5]):.1f}s" />'
parts = []
for s in segs:
    if s["kind"] == "headline": parts.append(brk)
    parts.append(s["text"].strip())
open(sys.argv[3], "w").write("\n\n".join(parts) + "\n")
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

# word budget per kind: lo/hi trigger one corrective pass; min/max are hard
case "$KIND" in
  explainer) LO=80;  HI=230; MIN=50;  MAX=260; WANT="110-200 words total, 1-3 stories, no headlines";;
  topic)     LO=100; HI=240; MIN=60;  MAX=270; WANT="120-220 words total, 2-4 stories, no headlines";;
  *)         LO=200; HI=310; MIN=150; MAX=340; WANT="250-290 words total, same shape (3 stories, then 10-12 one-sentence headlines)";;
esac
if [ "$WORDS" -gt "$HI" ] || [ "$WORDS" -lt "$LO" ]; then
  log "out of range ($WORDS words) — one corrective pass"
  run_pass "Your previous draft was $WORDS words. The script MUST be $WANT. Rewrite, same JSON format." > "$WORK/script.raw"
  WORDS="$(validate 2>&1)" || die "script pass invalid after length retry: $WORDS"
  log "retry: $WORDS words"
fi
[ "$WORDS" -ge "$MIN" ] || die "script pass returned $WORDS words — claude -p likely failed"
[ "$WORDS" -le "$MAX" ] || die "script is $WORDS words even after retry — over the $KIND budget"
log "wrote $OUT + $TXT ($WORDS words, $(python3 -c "
import json,sys; k=[s['kind'] for s in json.load(open(sys.argv[1]))['segments']]
print(k.count('story'),'stories +',k.count('headline'),'headlines')" "$OUT"))"
