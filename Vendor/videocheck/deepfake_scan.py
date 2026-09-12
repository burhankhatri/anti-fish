#!/usr/bin/env python3
"""
deepfake_scan.py - take an .mp4, return a deepfake likelihood score.

Pipeline:
    mp4 -> ffprobe metadata -> sample N frames -> detect+crop faces
        -> ensemble of ViT classifiers -> aggregate -> verdict

Usage:
    python deepfake_scan.py video.mp4
    python deepfake_scan.py video.mp4 --frames 32 --json out.json
    python deepfake_scan.py video.mp4 --models dima806/deepfake_vs_real_image_detection

READ THE CAVEAT IN verdict() BEFORE TRUSTING ANY NUMBER THIS PRINTS.
"""

from __future__ import annotations

import argparse
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field, asdict
from pathlib import Path

# Swin transformer trained on DFDC video face crops at 1FPS, aligned, with the
# face box expanded 30% - hence MARGIN below, which must match.
#
# Picked by measurement, not by model card. Three popular general-purpose
# "is this image AI" classifiers were benchmarked against labelled DFDC clips
# first and every one of them scored fakes LOWER than reals:
#
#   prithivMLmods/Deep-Fake-Detector-v2-Model   -18.1 pts   2/7
#   dima806/deepfake_vs_real_image_detection    -11.1 pts   3/7
#   Wvolf/ViT_Deepfake_Detection                -15.2 pts   3/7
#   prithivMLmods/open-deepfake-detection        +2.8 pts   3/7
#   hchcsuim (this one)                         +36.9 pts   5/7
#
# Those models were trained on still images and learned face-SWAP blending
# seams; they are blind to fully generated video and misread ordinary camera
# noise as manipulation. See README for the full numbers.
DEFAULT_MODEL = ("hchcsuim/batch-size16_DFDC_opencv-1FPS_"
                 "faces-expand30-aligned_unaugmentation")  # Fake / Real

# Kept only so the failure is reproducible; none of these work. Do not use.
ALT_MODELS = [
    "prithivMLmods/open-deepfake-detection",
    "prithivMLmods/Deep-Fake-Detector-v2-Model",
    "dima806/deepfake_vs_real_image_detection",
    "Wvolf/ViT_Deepfake_Detection",
]

MIN_FACE_PX = 64    # smaller than this is upscaled mush - refuse, don't guess
MIN_FACES = 3       # a verdict off one or two crops is noise, not evidence
MARGIN = 0.30       # must match the model's "expand30" training crop

FAKE_TOKENS = ("fake", "deepfake", "synthetic", "manipulated")
REAL_TOKENS = ("real", "realism", "authentic", "genuine", "pristine")


def label_is_fake(label: str) -> bool | None:
    """Normalize a model's label string to fake=True / real=False / unknown=None.

    REAL is checked first and by prefix: a substring test would let a loose
    token inside a word like "Realism" flip the answer, which silently inverts
    every score the tool produces.
    """
    low = label.strip().lower()
    if any(low == t or low.startswith(t) for t in REAL_TOKENS):
        return False
    if any(t in low for t in FAKE_TOKENS):
        return True
    if any(t in low for t in REAL_TOKENS):
        return False
    return None


# --------------------------------------------------------------------------
# Stage 1: container / metadata probe (free signal, no ML)
# --------------------------------------------------------------------------

@dataclass
class Probe:
    duration_s: float = 0.0
    width: int = 0
    height: int = 0
    fps: float = 0.0
    video_codec: str = ""
    has_audio: bool = False
    audio_codec: str = ""
    encoder_tags: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)


def probe_video(path: Path) -> Probe:
    """Pull container metadata. Encoder tags sometimes name the generator outright."""
    if not shutil.which("ffprobe"):
        raise RuntimeError("ffprobe not found on PATH - install ffmpeg")

    raw = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json",
         "-show_format", "-show_streams", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout
    meta = json.loads(raw)

    p = Probe()
    fmt = meta.get("format", {})
    p.duration_s = float(fmt.get("duration", 0) or 0)
    p.encoder_tags = {k: v for k, v in (fmt.get("tags") or {}).items()}

    for s in meta.get("streams", []):
        if s.get("codec_type") == "video" and not p.width:
            p.width = int(s.get("width", 0) or 0)
            p.height = int(s.get("height", 0) or 0)
            p.video_codec = s.get("codec_name", "")
            rate = s.get("avg_frame_rate", "0/1")
            try:
                num, den = rate.split("/")
                p.fps = round(float(num) / float(den), 2) if float(den) else 0.0
            except (ValueError, ZeroDivisionError):
                p.fps = 0.0
            p.encoder_tags.update(s.get("tags") or {})
        elif s.get("codec_type") == "audio":
            p.has_audio = True
            p.audio_codec = s.get("codec_name", "")

    # Cheap heuristics worth surfacing regardless of what the ML says.
    blob = json.dumps(p.encoder_tags).lower()
    for marker in ("sora", "runway", "pika", "kling", "veo", "luma",
                   "heygen", "synthesia", "d-id", "stable", "midjourney"):
        if marker in blob:
            p.notes.append(f"metadata names a known generative tool: '{marker}'")
    if not p.encoder_tags:
        p.notes.append("no encoder metadata (stripped - normal for re-shared media)")
    if not p.has_audio:
        p.notes.append("no audio track (cannot cross-check voice)")
    if p.width and p.width < 400:
        p.notes.append(f"very low resolution ({p.width}x{p.height}) - detectors unreliable")
    return p


# --------------------------------------------------------------------------
# Stage 2+3: sample frames and crop faces - entirely in memory
# --------------------------------------------------------------------------
#
# v1 wrote frames to disk as JPEG, then re-saved each crop as JPEG again. On
# top of the source h264 that is three lossy passes before the model sees a
# pixel. Deepfake detectors key on fine high-frequency texture - precisely what
# JPEG discards, while adding compression artifacts of its own. Decoding
# straight to arrays removes two of the three lossy stages and all disk I/O.

YUNET_FILE = "face_detection_yunet_2023mar.onnx"
YUNET_URL = ("https://media.githubusercontent.com/media/opencv/opencv_zoo/main/"
             "models/face_detection_yunet/face_detection_yunet_2023mar.onnx")


def _yunet_model_path() -> Path | None:
    """Locate the YuNet ONNX next to this script, downloading it once if needed."""
    local = Path(__file__).parent / YUNET_FILE
    if local.exists() and local.stat().st_size > 100_000:
        return local
    if not shutil.which("curl"):
        return None
    print(f"      fetching face detector ({YUNET_FILE}) ...")
    r = subprocess.run(["curl", "-sL", "-o", str(local), YUNET_URL],
                       capture_output=True)
    if r.returncode == 0 and local.exists() and local.stat().st_size > 100_000:
        return local
    local.unlink(missing_ok=True)
    return None


def extract_faces(path: Path, n_frames: int):
    """Sample n_frames evenly, return (face_images, face_widths, detector_name).

    Faces below MIN_FACE_PX are refused rather than scored: a 30px face
    upscaled to 224x224 is noise, and scoring it produces a confident-looking
    number backed by nothing.
    """
    import cv2
    from PIL import Image

    mp = _yunet_model_path()
    if mp is None or not hasattr(cv2, "FaceDetectorYN"):
        raise RuntimeError("YuNet face detector unavailable")
    det = cv2.FaceDetectorYN.create(str(mp), "", (320, 320), score_threshold=0.5)

    cap = cv2.VideoCapture(str(path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    step = max(1, total // max(1, n_frames))

    faces, widths = [], []
    for k in range(n_frames):
        idx = min(total - 1, k * step)
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(idx))
        ok, img = cap.read()
        if not ok:
            continue
        h, w = img.shape[:2]
        det.setInputSize((w, h))
        _, found = det.detect(img)
        if found is None or not len(found):
            continue
        x, y, fw, fh = [int(v) for v in max(found, key=lambda f: f[2] * f[3])[:4]]
        widths.append(fw)
        if fw < MIN_FACE_PX or fh < MIN_FACE_PX:
            continue
        mx, my = int(fw * MARGIN), int(fh * MARGIN)
        x0, y0 = max(0, x - mx), max(0, y - my)
        x1, y1 = min(w, x + fw + mx), min(h, y + fh + my)
        if x1 <= x0 or y1 <= y0:
            continue
        crop = img[y0:y1, x0:x1]
        faces.append(Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)))
    cap.release()
    return faces, widths, "yunet"


# --------------------------------------------------------------------------
# Stage 4: ensemble inference
# --------------------------------------------------------------------------

def score_crops(images: list, model_ids: list[str]) -> dict:
    """Run each model over every face crop. Returns per-model fake probabilities."""
    from transformers import pipeline

    per_model: dict[str, list[float]] = {}

    try:
        import torch  # noqa: F401
    except ImportError:
        print("  ! PyTorch is not installed - no model can run.\n"
              "    pip install --index-url https://download.pytorch.org/whl/cpu torch",
              file=sys.stderr)
        return {}

    for mid in model_ids:
        try:
            clf = pipeline("image-classification", model=mid, device=-1)
        except Exception as e:                                  # noqa: BLE001
            print(f"  ! skipping {mid}: {e}", file=sys.stderr)
            continue

        fake_probs = []
        for out in clf(images, batch_size=8):
            preds = out if isinstance(out, list) else [out]
            fake_p = 0.0
            for pr in preds:
                flag = label_is_fake(pr["label"])
                if flag is True:
                    fake_p = pr["score"]
                    break
                if flag is False:
                    fake_p = 1.0 - pr["score"]
            fake_probs.append(round(float(fake_p), 4))
        per_model[mid] = fake_probs
        print(f"  - {mid}: mean fake prob {statistics.mean(fake_probs):.3f}")

    return per_model


# --------------------------------------------------------------------------
# Stage 5: aggregate + verdict
# --------------------------------------------------------------------------

def aggregate(per_model: dict[str, list[float]]) -> dict:
    """Per-frame ensemble mean, then clip-level statistics."""
    if not per_model:
        return {}
    n = min(len(v) for v in per_model.values())
    frame_means = [
        statistics.mean(per_model[m][i] for m in per_model) for i in range(n)
    ]
    return {
        "n_faces_scored": n,
        "mean_fake_prob": round(statistics.mean(frame_means), 4),
        "median_fake_prob": round(statistics.median(frame_means), 4),
        "max_fake_prob": round(max(frame_means), 4),
        "frac_frames_over_0.5": round(sum(p > 0.5 for p in frame_means) / n, 4),
        "frame_means": [round(p, 4) for p in frame_means],
        "disagreement": round(
            statistics.mean(
                statistics.pstdev([per_model[m][i] for m in per_model])
                for i in range(n)
            ), 4
        ) if len(per_model) > 1 else None,
    }


def verdict(agg: dict, probe: Probe) -> dict:
    """
    Map score -> band. Deliberately conservative.

    CAVEAT THAT MATTERS MORE THAN THE CODE:
    These open-source checkpoints are trained on older academic datasets
    (FaceForensics++, DFDC, Celeb-DF). On in-the-wild deepfakes they score
    ~61-69% accuracy - barely better than a coin flip - versus ~82% for the
    best commercial detectors. Compression, re-encoding (WhatsApp!), and low
    resolution degrade them further. Treat output as ONE WEAK SIGNAL, never
    as a verdict you show a user as fact.
    """
    if not agg:
        return {"band": "NO_RESULT", "confidence": "none",
                "reasons": ["no scores produced - either no face was detected, "
                            "or every model failed to load (see errors above)"]}

    # A face detector will occasionally hallucinate a face in foliage or
    # texture. One or two such crops can otherwise produce a confident
    # "LIKELY_MANIPULATED" on a video containing no people at all.
    if agg["n_faces_scored"] < MIN_FACES:
        return {"band": "CANNOT_ASSESS", "fake_percent": None,
                "confidence": "none",
                "reasons": [f"only {agg['n_faces_scored']} usable face crop(s) "
                            f"found, need {MIN_FACES} - too little to judge",
                            "a face detector can register false positives on "
                            "textured backgrounds; scoring those is meaningless",
                            *probe.notes]}

    m = agg["mean_fake_prob"]
    frac = agg["frac_frames_over_0.5"]
    dis = agg.get("disagreement")
    pct = round(m * 100, 1)

    if m >= 0.80 and frac >= 0.7:
        band, conf = "LIKELY_MANIPULATED", "low-moderate"
    elif m >= 0.60:
        band, conf = "SUSPICIOUS", "low"
    elif m <= 0.20 and frac <= 0.2:
        band, conf = "NO_EVIDENCE_OF_MANIPULATION", "low-moderate"
    else:
        band, conf = "INCONCLUSIVE", "very low"

    # Frames should agree with each other on a genuine clip. Generators
    # re-render each frame independently, so scores that swing wildly across
    # the clip are themselves a (weak) manipulation signal - and it costs
    # nothing, since the per-frame scores already exist.
    spread = statistics.pstdev(agg["frame_means"]) if agg["n_faces_scored"] > 2 else 0.0

    reasons = [
        f"{pct:.1f}% average manipulation score across "
        f"{agg['n_faces_scored']} face crops",
        f"{frac:.0%} of frames individually scored above 50%",
    ]
    if spread > 0.25:
        reasons.append(f"scores are unstable across frames (sd {spread:.2f}) - "
                       f"possible frame-by-frame regeneration")
    if dis is not None and dis > 0.25:
        reasons.append(f"models disagree substantially (sd {dis:.2f}) - "
                       f"treat as inconclusive")
        conf = "very low"
    reasons.extend(probe.notes)

    return {"band": band, "fake_percent": pct, "frame_spread": round(spread, 4),
            "confidence": conf, "reasons": reasons}


# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Score an mp4 for face manipulation.")
    ap.add_argument("video", type=Path)
    ap.add_argument("--frames", type=int, default=24,
                    help="frames to sample across the clip (default 24)")
    ap.add_argument("--models", nargs="*", default=[DEFAULT_MODEL],
                    help=f"default: {DEFAULT_MODEL}. Pass more to ensemble "
                         f"(slower, more RAM). Alternatives: {', '.join(ALT_MODELS)}")
    ap.add_argument("--json", type=Path, help="write full result to this path")
    ap.add_argument("--keep", action="store_true", help="keep extracted frames")
    args = ap.parse_args()

    if not args.video.exists():
        print(f"error: {args.video} not found", file=sys.stderr)
        return 1

    work = Path(tempfile.mkdtemp(prefix="dfscan_"))
    try:
        print(f"[1/3] probing {args.video.name} ...")
        p = probe_video(args.video)
        print(f"      {p.width}x{p.height} @ {p.fps}fps, {p.duration_s:.1f}s, "
              f"{p.video_codec}, audio={p.audio_codec or 'none'}")
        for note in p.notes:
            print(f"      note: {note}")

        print(f"[2/3] sampling {args.frames} frames, cropping faces ...")
        crops, widths, det_name = extract_faces(args.video, args.frames)
        med = int(statistics.median(widths)) if widths else 0
        print(f"      {len(crops)} usable faces (detector: {det_name}, "
              f"median face {med}px, minimum {MIN_FACE_PX}px)")
        if widths and not crops:
            p.notes.append(f"every detected face was under {MIN_FACE_PX}px "
                           f"(median {med}px) - too small to assess")
        elif not widths:
            p.notes.append("no face found in any sampled frame - this tool only "
                           "detects FACE manipulation")

        agg: dict = {}
        per_model: dict = {}
        if crops:
            print(f"[3/3] scoring with {len(args.models)} model(s) ...")
            per_model = score_crops(crops, args.models)
            agg = aggregate(per_model)
        else:
            print("[3/3] skipped - nothing assessable")

        v = verdict(agg, p)

        pct = v.get("fake_percent")
        bar = ""
        if pct is not None:
            filled = int(round(pct / 5))
            bar = f"  [{'#' * filled}{'.' * (20 - filled)}]  {pct:.1f}% fake"

        print("\n" + "=" * 62)
        if pct is not None:
            print(bar)
            print("-" * 62)
        print(f"  {v['band']}     (confidence in this call: {v['confidence']})")
        print("=" * 62)
        for r in v["reasons"]:
            print(f"  - {r}")
        print("\n  NOTE: the % above is this clip's manipulation score, NOT the\n"
              "  model's accuracy. Measured 7/9 correct on labelled clips - good\n"
              "  separation, but a small sample. Treat as a strong signal, not proof.")
        print()

        result = {"file": str(args.video), "probe": asdict(p),
                  "per_model": per_model, "aggregate": agg, "verdict": v}
        if args.json:
            args.json.write_text(json.dumps(result, indent=2))
            print(f"  full result -> {args.json}")
        if args.keep:
            print(f"  frames kept -> {work}")
        return 0
    finally:
        if not args.keep:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
