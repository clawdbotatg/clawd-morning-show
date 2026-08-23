# 2026-08-23 — the show didn't build: `claude -p` hit a weekly wall

Session log, written for Austin and for whoever debugs this next. TLDR first.

## TLDR

- **Why it failed:** the 7:40 build's `claude -p` (stage 1, the script pass)
  ran on the plain `~/.claude` login, which was at its weekly limit. It
  answered `You've hit your weekly limit · resets Aug 25 at 3pm` instead of
  a script. The validator rejected the 13-word "script", the build died,
  clawd-twitter sent the "video build failed" Telegram note. Nothing else
  was broken (digest fine, TTS/render never ran).
- **Why it could happen:** `claude -p` has **no built-in subscription
  routing**. The harness routes its sessions; claude-p-agent routes via the
  `claude-p-router` module; a bare shell script calling `claude -p` gets
  whatever `CLAUDE_CONFIG_DIR` is in its env — under launchd, nothing, so
  the default login.
- **Fix (pushed, `ea478fb` + `3ccdd96`):** `scripts/pick_account.py` ranks
  every signed-in login by weekly headroom and `01-script.sh` walks the
  list, moving on when an account answers with a limit line. Holds as long
  as one signed-in subscription has room.
- **Today's show** was rebuilt by hand at 07:53 on `ef` (34% used) through
  clawd-twitter's wrapper, so `state/morning-show.json` existed before the
  8:02 post. Clip: `out/show-2026-08-23.mp4` (108s).

## 1. Diagnosis — where to look next time

1. `clawd-twitter/state/show.log` — the build log. Today's tail was just
   `[01-script] script pass (claude -p)…` then `make-show failed`. The
   stage dies before logging anything useful because the model output goes
   to disk first.
2. `out/work-<date>/script.raw` — the raw `claude -p` output. **Read this
   first.** Today it was one line: the limit message. If it's a wall, it
   says so in plain English.
3. `out/work-<date>/` only holding `stories.json` + `script.raw` = stage 1
   died. `voice.mp3` present = TTS ran, look later in the chain.
4. Which login a launchd job uses: none of the plists set
   `CLAUDE_CONFIG_DIR`, so it's `~/.claude`. From a harness session you
   inherit the session's account (this session ran as `sub3`), which is
   why "it works when I run it by hand" can lie.

## 2. The four subscriptions (as of today)

Read from the harness's `.clawd-harness.sessions.json` `accounts` list (the
harness polls usage for every login every few minutes and persists it —
**read that file; don't hit the usage endpoint yourself, it returns 429
within a few calls**, `tools/usage_probe.py` showed that today).

| dir under `~/.clawd-accounts/` | org (= the usage pool) | plan | today |
|---|---|---|---|
| `ef` | austingriffith | max 20x | 34% — picked |
| `austinmax`, `sub2` | austingriffith (same pool as `ef`) | max 20x | signed out (no access token) |
| `sub3` | clawd@buidlguidl.com | max 20x | 93% |
| `clawd` | Ethereum Foundation | max 5x | 100%, resets Tue 25 |
| `slop`, `clawdteam` | slop@buidlguidl.com | max 5x / claude.ai | 100%, resets Tue 25 |
| `~/.claude` (default) | — | — | walled, resets Tue 25 3pm Denver |

Several dirs share one org → one pool. The picker keeps one per org.

## 3. The fix, in detail

**`scripts/pick_account.py`** — prints config dirs, best first, to stdout
(names + % to stderr). Source: `<repo>/../../.clawd-harness.sessions.json`
(override: first arg = harness dir). Per org keep the freshest reading;
sort by (≥97% last, stale >12h after fresh, least-used first). Full
accounts are **listed last, not dropped** — the reading may be stale (an
account that reset overnight) and a walled `claude -p` answers instantly,
so trying it is free. No file / no accounts → prints nothing.

**`scripts/01-script.sh`** — builds `ACCOUNTS=(<picker lines>… "")`, the
trailing `""` = default login (unset `CLAUDE_CONFIG_DIR`), i.e. the old
behaviour as the last fallback. `run_pass` loops over it: export the dir,
run `claude -p --model sonnet`, and if the first 400 chars match
`hit your .*limit|usage limit|rate limit` log "at its limit — trying next"
and continue. First clean answer wins and is logged as `account: <name>`.
All walled → the last reply goes to the validator, which dies loudly as
before. `SHOW_CLAUDE_DIR=<dir>` pins one by hand (skips the picker).
`scrub_claude_env` only unsets `CLAUDECODE`/`CLAUDE_CODE_*`/`ANTHROPIC_*`,
so `CLAUDE_CONFIG_DIR` survives it — that's relied on.

Check the ranking any time: `python3 scripts/pick_account.py`.

## 4. What can still fail

- **All pools full.** Nothing to do but wait for a reset (Tue 3pm Denver
  for two of them this week).
- **A login signed out** (`austinmax`/`sub2` today — harness says "no
  accessToken"). They're not in the picker's list at all (not `ready`).
  Re-sign via the harness 🧠 accounts panel; both share `ef`'s pool anyway.
- **Anthropic rewords the limit message.** The regex won't match, the
  walled account's reply goes to the validator, the build dies like today.
  Symptom in `script.raw`; fix = extend the regex in `run_pass`.
- **Harness not running / file missing.** Picker prints nothing → default
  login only, exactly the pre-fix behaviour.
- **5h session wall** on the chosen account: same message shape ("hit your
  limit"), same regex, moves on.

## 5. Where routing actually lives (so nobody rebuilds it again)

- **Harness sessions** (`clawd-harness/server.py`): full router — picks the
  pool per spawn, hands idle sessions off, rescues walled prompts. The
  readings it persists are what the picker reads.
- **claude-p-agent projects**: the **`router` module**
  (`github.com/clawdbotatg/claude-p-router`, installed with
  `tools/module add router`). An `env` hook the engine runs before every
  spawn; prints `CLAUDE_CONFIG_DIR=<best>`. Has its own on-disk usage cache
  and a `./env --status` JSON surface. An operator-set `CLAUDE_CONFIG_DIR`
  always wins. Nothing to build — install the module.
- **Bare `claude -p` in a shell script** (this repo, any cron/launchd job):
  nothing, by default. Options: this repo's `pick_account.py` pattern, or
  `eval "$(<claude-p-agent>/modules/router/env)"` before the call (not done
  here — the picker reads the harness file and makes zero network calls;
  swapping to the router module is a one-line change if wanted).

## 6. Hand-rebuild recipe (what I ran today)

```
cd ~/clawd-harness/projects/clawd-twitter
rm -f state/.ran-show-$(date +%F-%H)     # the wrapper's once-per-hour lock
scripts/morning-show.sh                  # builds via this repo, writes state/morning-show.json
```
Do it before 8:02 and the gm thread picks the clip up on its own; after
8:02 the thread has already shipped without it. To pin a login:
`SHOW_CLAUDE_DIR=~/.clawd-accounts/ef scripts/morning-show.sh`. Watch it:
`osascript -e 'tell application "QuickTime Player" to close every document'; open out/show-<date>.mp4`.
