#!/usr/bin/env python3
"""Checks a video by checking the frames inside it.

Momina's antiFish-mp4 scores faces with a PyTorch model, which is the stronger method but needs a
2.5 GB download. This takes the cheap road that is already paid for: pull a handful of evenly
spaced frames with ffmpeg and run each one through the same image check the rest of the app uses.
A generated video is generated in every frame, so a few samples are enough to tell.

    videobridge.py clip.mp4 [--frames 6]   → one JSON object on stdout

Frames are uploaded to SightEngine. Nothing is written outside a temp directory.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from imagebridge import check as check_image  # noqa: E402


def duration_seconds(path: Path) -> float:
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", str(path)],
            capture_output=True, text=True, timeout=30)
        return float(out.stdout.strip() or 0)
    except Exception:
        return 0.0


def sample_frames(path: Path, into: Path, count: int, head_only: bool = False) -> list[Path]:
    """Stills to check.

    `head_only` takes them from the opening seconds, which is much faster because ffmpeg never
    seeks far into the file. Spreading them over the whole clip is slower but safer: a clip whose
    opening is a plain title card gives the opening frames nothing to judge.
    """
    seconds = duration_seconds(path)
    frames: list[Path] = []
    for i in range(count):
        if head_only:
            position = 0.4 * i
        else:
            position = (seconds * (i + 1) / (count + 1)) if seconds > 0 else i
        out = into / f"frame_{i:02d}.jpg"
        result = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-ss", f"{position:.2f}", "-i", str(path),
             "-frames:v", "1", "-q:v", "3", str(out)],
            capture_output=True, timeout=60)
        if result.returncode == 0 and out.exists() and out.stat().st_size > 1000:
            frames.append(out)
    return frames


def scan(path: Path, user: str, secret: str, count: int, head_only: bool = False) -> dict:
    if not shutil.which("ffmpeg"):
        return {"verdict": "error", "error": "ffmpeg is not installed"}

    with tempfile.TemporaryDirectory(prefix="antifish-video-") as tmp:
        frames = sample_frames(path, Path(tmp), count, head_only)
        if not frames:
            return {"verdict": "error", "error": "could not read any frames"}

        scores: list[dict] = []
        for frame in frames:
            try:
                scores.append(check_image(frame, user, secret))
            except Exception as exc:
                scores.append({"verdict": "error", "error": str(exc)})

    usable = [s for s in scores if s.get("verdict") not in (None, "error")]
    if not usable:
        return {"verdict": "error", "error": "every frame failed to check",
                "framesChecked": 0}

    ai = [float(s.get("ai_generated", 0)) for s in usable]
    deep = [float(s.get("deepfake", 0)) for s in usable]
    # The strongest frame decides: a clip only has to be generated somewhere to be generated.
    peak_ai, peak_deep = max(ai), max(deep)
    mean_ai = sum(ai) / len(ai)
    flagged = sum(1 for s in usable if s.get("verdict") in ("AI-GENERATED", "FACE-SWAPPED"))

    if peak_ai >= 0.5 or peak_deep >= 0.5:
        verdict = "AI-GENERATED" if peak_ai >= peak_deep else "FACE-SWAPPED"
        confidence = max(peak_ai, peak_deep)
    else:
        verdict = "AUTHENTIC"
        confidence = 1 - max(peak_ai, peak_deep)

    return {
        "path": str(path),
        "verdict": verdict,
        "confidence": round(confidence, 4),
        "ai_generated": round(peak_ai, 4),
        "deepfake": round(peak_deep, 4),
        "meanAI": round(mean_ai, 4),
        "framesChecked": len(usable),
        "framesFlagged": flagged,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("video")
    ap.add_argument("--frames", type=int, default=5)
    ap.add_argument("--head", action="store_true",
                    help="sample only the opening seconds; faster to seek but measurably worse "
                         "(it called a real selfie AI-generated at 0.99 on the labelled clips)")
    args = ap.parse_args()

    user = os.environ.get("SIGHTENGINE_USER", "")
    secret = os.environ.get("SIGHTENGINE_SECRET", "")
    if not user or not secret:
        print(json.dumps({"verdict": "error", "error": "no SightEngine credentials"}))
        return 3
    path = Path(args.video)
    if not path.exists():
        print(json.dumps({"verdict": "error", "error": f"no such file: {path}"}))
        return 4
    print(json.dumps(scan(path, user, secret, args.frames, args.head)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
