#!/usr/bin/env python3
"""whisper verbose_json (word timestamps) -> .ass caption track.

Groups words into short caption chunks (few words, ~2s) sized for a phone
screen — X autoplays muted, so these carry the whole show. Stdlib only.
"""
import json
import sys

MAX_WORDS = 5          # words per caption line
MAX_SPAN = 2.6         # seconds a caption may cover
GAP_BREAK = 0.6        # silence that forces a new caption
PAD_TAIL = 0.12        # linger after the last word


def ts(t: float) -> str:
    t = max(t, 0.0)
    h = int(t // 3600)
    m = int(t % 3600 // 60)
    s = t % 60
    return f"{h}:{m:02d}:{s:05.2f}"


HEADER = """[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Menlo,44,&H0066FF66,&H00FFFFFF,&H00081008,&HB0081008,-1,0,0,0,100,100,0,0,1,3,0,2,60,60,96,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def main(words_json: str, out_ass: str) -> None:
    data = json.load(open(words_json))
    words = data.get("words") or []
    if not words:
        sys.exit("build_captions: no words[] in " + words_json)

    chunks, cur = [], []
    for w in words:
        if cur:
            span = w["end"] - cur[0]["start"]
            gap = w["start"] - cur[-1]["end"]
            sentence_end = cur[-1]["word"].strip().endswith((".", "!", "?"))
            if len(cur) >= MAX_WORDS or span > MAX_SPAN or gap > GAP_BREAK \
               or sentence_end:
                chunks.append(cur)
                cur = []
        cur.append(w)
    if cur:
        chunks.append(cur)

    lines = [HEADER]
    for i, c in enumerate(chunks):
        start = c[0]["start"]
        # run each caption to the next one's start (no flicker), pad the last
        end = chunks[i + 1][0]["start"] if i + 1 < len(chunks) else c[-1]["end"] + PAD_TAIL
        end = max(end, c[-1]["end"])
        text = " ".join(w["word"].strip() for w in c)
        text = text.replace("{", "(").replace("}", ")")
        lines.append(f"Dialogue: 0,{ts(start)},{ts(end)},Cap,,0,0,0,,{text}\n")

    with open(out_ass, "w") as f:
        f.writelines(lines)
    print(f"build_captions: {len(chunks)} captions, "
          f"{ts(chunks[-1][-1]['end'])} total", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: build_captions.py words.json out.ass")
    main(sys.argv[1], sys.argv[2])
