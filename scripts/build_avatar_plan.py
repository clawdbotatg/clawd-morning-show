#!/usr/bin/env python3
"""Precompute the clawd-video-chat avatar state machine for the whole show.

Mirrors `clawdVid` in clawd-video-chat/index.html, driven by the same events
the live rig gets, just known in advance:
  - each TTS chunk's audio.onplay -> chatting(): play chatting_1 ONCE from the
    top; ignored while a chatting clip is still playing (`if (_chatting) return`)
  - any clip ending naturally -> nextIdle(): a random idle clip from the top
  - speech end + 250ms -> idle(true): cut to a random idle immediately
  - every switch is a hard cut (the rig's overlay "fade" is between two copies
    of the SAME new clip — visually a snap)
Output: a filter_complex fragment that concats the trimmed segments into
[avatar], plus segments.json for the record.

usage: build_avatar_plan.py words.json intro_s outro_s idle1_dur idle2_dur chat_dur seed out.filter out.json
       (inputs in the ffmpeg graph: [2:v]=idle_1  [3:v]=idle_2  [4:v]=chatting_1)
"""
import json
import random
import sys
from build_captions import chunks

IDLE_AFTER_SPEECH_S = 0.25


def plan(words, intro, outro, durs, seed):
    rng = random.Random(seed)
    IDLES = ["idle_1", "idle_2"]
    next_idle = lambda: rng.choice(IDLES)

    chunk_starts = [c[0]["start"] + intro for c in chunks(words)]
    speech_end = words[-1]["end"] + intro + IDLE_AFTER_SPEECH_S
    total = intro + (words[-1]["end"]) + outro
    events = [(t, "chunk") for t in chunk_starts] + [(speech_end, "idle"), (total, "end")]
    events.sort()

    segs = []
    t = 0.0
    cur = next_idle(); cur_end = durs[cur]
    chatting = False
    for e, kind in events:
        # clips ending naturally before this event -> random idle each time
        while cur_end < e:
            segs.append((cur, cur_end - t))
            t = cur_end; chatting = False
            cur = next_idle(); cur_end = t + durs[cur]
        if kind == "end":
            segs.append((cur, e - t))
            break
        if kind == "chunk":
            if chatting:
                continue  # chatting clip still playing — rig ignores the re-fire
            segs.append((cur, e - t))
            t = e; cur = "chatting_1"; cur_end = t + durs[cur]; chatting = True
        elif kind == "idle":
            segs.append((cur, e - t))
            t = e; chatting = False
            cur = next_idle(); cur_end = t + durs[cur]
    return [s for s in segs if s[1] > 1e-3], total


def filtergraph(segs):
    idx = {"idle_1": 2, "idle_2": 3, "chatting_1": 4}
    uses = {k: [i for i, s in enumerate(segs) if s[0] == k] for k in idx}
    lines = []
    for clip, i in idx.items():
        n = len(uses[clip])
        if n == 0:
            continue
        outs = "".join(f"[{clip}_{j}]" for j in range(n))
        lines.append(f"[{i}:v]split={n}{outs}" if n > 1 else f"[{i}:v]null[{clip}_0]")
    for k, (clip, dur) in enumerate(segs):
        j = uses[clip].index(k)
        lines.append(f"[{clip}_{j}]trim=duration={dur:.4f},setpts=PTS-STARTPTS[seg{k}]")
    lines.append("".join(f"[seg{k}]" for k in range(len(segs))) + f"concat=n={len(segs)}:v=1:a=0[avatar]")
    return ";\n".join(lines)


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) != 9:
        sys.exit(__doc__)
    words = json.load(open(a[0]))["words"]
    intro, outro = float(a[1]), float(a[2])
    durs = {"idle_1": float(a[3]), "idle_2": float(a[4]), "chatting_1": float(a[5])}
    segs, total = plan(words, intro, outro, durs, a[6])
    open(a[7], "w").write(filtergraph(segs))
    json.dump({"total": total, "segments": [{"clip": c, "dur": round(d, 4)} for c, d in segs]},
              open(a[8], "w"), indent=1)
    chat = sum(d for c, d in segs if c == "chatting_1")
    print(f"avatar plan: {len(segs)} segments, chatting {chat:.0f}s of {total:.0f}s", file=sys.stderr)
