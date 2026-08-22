#!/usr/bin/env python3
"""plan.json (from plan_avatar.mjs — the rig's own TTS chunks, timed) -> .ass
captions in clawd-video-chat's #speechCaption style: white, bold sans, black
stroke, bottom 64px, each chunk held until the next starts, cleared when the
speech queue drains. Stdlib only.
"""
import json
import sys


def ts(t: float) -> str:
    t = max(t, 0.0)
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"


HEADER = """[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Helvetica,30,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2.5,1,2,52,52,64,1
Style: CapPip,Helvetica,27,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2.5,1,2,40,400,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def main(plan_json, out_ass):
    caps = json.load(open(plan_json)).get("captions") or []
    if not caps:
        sys.exit("build_captions: no captions in " + plan_json)
    lines = [HEADER]
    for c in caps:
        if c.get("mode") == "headline":   # the headline card on stage is the caption
            continue
        text = c["text"].replace("{", "(").replace("}", ")").replace("\n", " ")
        style = "CapPip" if c.get("mode") == "pip" else "Cap"   # PIP mode: clawd is bottom-right, captions keep left
        lines.append(f"Dialogue: 0,{ts(c['start'])},{ts(c['end'])},{style},,0,0,0,,{text}\n")
    open(out_ass, "w").writelines(lines)
    print(f"build_captions: {len(lines) - 1} of {len(caps)} captions painted, ends {ts(caps[-1]['end'])}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: build_captions.py plan.json out.ass")
    main(sys.argv[1], sys.argv[2])
