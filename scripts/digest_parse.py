#!/usr/bin/env python3
"""clawd-morning-update's state/digest.md -> stories.json (stdlib only).

Format (scripts/render.js + lib/html.js mdTweet in that repo):
  # twitter vibe — DATE / > headline / intro / _N tweets … fetched …_
  ## theme title / blurb / - [@handle](url) (1.2k♥ 116🔁): text   (≤4 per theme)
  ## also big this morning / - … / --- / _source: …_
"""
import json
import re
import sys

TWEET = re.compile(r"^- \[@(?P<handle>[A-Za-z0-9_]+)\]\((?P<url>[^)]+)\)(?: \((?P<stats>[^)]*)\))?: ?(?P<text>.*)$")


def num(s):
    s = s.replace(",", "")
    return int(float(s[:-1]) * 1000) if s.endswith("k") else int(float(s))


def parse(md: str) -> dict:
    lines = md.splitlines()
    out = {"date": "", "headline": "", "intro": "", "stats": "", "themes": []}
    m = re.match(r"^# twitter vibe — (\S+)", lines[0] if lines else "")
    if m:
        out["date"] = m.group(1)
    cur = None
    for ln in lines[1:]:
        s = ln.rstrip()
        if s.startswith("## "):
            cur = {"title": s[3:].strip(), "blurb": "", "tweets": []}
            out["themes"].append(cur)
            continue
        if s == "---":
            cur = None
            continue
        if cur is None:
            if s.startswith("> ") and not out["headline"]:
                out["headline"] = s[2:].strip()
            elif s.startswith("_") and "tweets" in s and not out["stats"]:
                out["stats"] = s.strip("_")
            elif s and not s.startswith("_") and not out["intro"] and out["headline"]:
                out["intro"] = s
            continue
        t = TWEET.match(s)
        if t:
            likes = rts = 0
            for v, k in re.findall(r"([\d.,]+k?)(♥|🔁)", t.group("stats") or ""):
                if k == "♥": likes = num(v)
                else: rts = num(v)
            cur["tweets"].append({"handle": t.group("handle"), "url": t.group("url"),
                                  "id": t.group("url").rstrip("/").split("/")[-1],
                                  "likes": likes, "rts": rts, "text": t.group("text").strip()})
        elif s and not cur["blurb"]:
            cur["blurb"] = s
    if not out["headline"] or not out["themes"]:
        sys.exit("digest_parse: this doesn't look like clawd-morning-update's digest.md "
                 f"(headline={out['headline']!r}, themes={len(out['themes'])})")
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: digest_parse.py digest.md stories.json")
    d = parse(open(sys.argv[1]).read())
    json.dump(d, open(sys.argv[2], "w"), indent=1, ensure_ascii=False)
    print(f"digest_parse: {len(d['themes'])} themes, "
          f"{sum(len(t['tweets']) for t in d['themes'])} tweets — {d['headline']}", file=sys.stderr)
