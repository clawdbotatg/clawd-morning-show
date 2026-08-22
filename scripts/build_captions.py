#!/usr/bin/env python3
"""word timings (ElevenLabs alignment) -> .ass captions, clawd-video-chat style.

The rig speaks in TTS chunks — sentences (`[.!?\\n]` boundary; the FIRST chunk
splits on any pause for fast first-audio; 240-char hard cap) — and shows each
chunk as the on-screen caption (#speechCaption: white, bold sans, black
stroke, bottom 64px, cleared when the queue drains). Same here. Stdlib only.
"""
import json
import re
import sys

FIRST_BREAK = re.compile(r"[.,!?;:]$")
SENT_BREAK = re.compile(r"[.!?]$")
MAX_CHUNK = 240  # _TTS_MAX_CHUNK


def ts(t: float) -> str:
    t = max(t, 0.0)
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"


def chunks(words):
    """Group words exactly the way the rig chunks TTS."""
    out, cur, first = [], [], True
    for w in words:
        cur.append(w)
        text_len = sum(len(x["word"]) + 1 for x in cur)
        brk = FIRST_BREAK if first else SENT_BREAK
        if brk.search(w["word"].strip()) or text_len >= MAX_CHUNK:
            out.append(cur); cur = []; first = False
    if cur:
        out.append(cur)
    return out


HEADER = """[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Helvetica,30,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2.5,1,2,52,52,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def main(words_json, out_ass, offset=0.0):
    words = json.load(open(words_json)).get("words") or []
    if not words:
        sys.exit("build_captions: no words[] in " + words_json)
    words = [{**w, "start": w["start"] + offset, "end": w["end"] + offset} for w in words]
    cs = chunks(words)
    lines = [HEADER]
    for i, c in enumerate(cs):
        start = c[0]["start"]
        # a caption stays up until the next chunk starts speaking; the last
        # clears when speech ends (the rig's setCaption("") on queue drain)
        end = cs[i + 1][0]["start"] if i + 1 < len(cs) else c[-1]["end"]
        text = " ".join(w["word"].strip() for w in c).replace("{", "(").replace("}", ")")
        lines.append(f"Dialogue: 0,{ts(start)},{ts(end)},Cap,,0,0,0,,{text}\n")
    open(out_ass, "w").writelines(lines)
    print(f"build_captions: {len(cs)} sentence captions, ends {ts(cs[-1][-1]['end'])}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: build_captions.py words.json out.ass [offset_seconds]")
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) == 4 else 0.0)
