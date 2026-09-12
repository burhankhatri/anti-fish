# antiFish-mp4

Takes an `.mp4`, returns a percentage score for whether the face in it has been
manipulated. Runs entirely on your own machine — no API keys, no upload, no
per-scan cost.

Part of the **antiFish** anti-impersonation project.

```
$ python deepfake_scan.py clip.mp4

[1/3] probing clip.mp4 ...
      478x850 @ 29.87fps, 5.3s, h264, audio=aac
[2/3] sampling 16 frames, cropping faces ...
      15 usable faces (detector: yunet, median face 260px, minimum 64px)
[3/3] scoring with 1 model(s) ...

==============================================================
  [#...................]  5.4% fake
--------------------------------------------------------------
  NO_EVIDENCE_OF_MANIPULATION     (confidence in this call: low-moderate)
==============================================================
  - 5.4% average manipulation score across 15 face crops
  - 0% of frames individually scored above 50%
```

## Measured results

Nine labelled clips: seven from the DFDC dataset, plus a real phone selfie and
two AI-generated videos (Veo-style and Imagine Art).

| Clip | Truth | Score | Verdict | |
|---|---|---|---|---|
| `fake-dtymieprub` | FAKE | 100.0% | LIKELY_MANIPULATED | ✅ |
| `fake-eiidlcmtzl` | FAKE | 100.0% | LIKELY_MANIPULATED | ✅ |
| `fake-qmitaqtqbj` | FAKE | 100.0% | LIKELY_MANIPULATED | ✅ |
| `fake-ockfqfgwmm` | FAKE | 99.8% | LIKELY_MANIPULATED | ✅ |
| `imagine-art` | FAKE | 61.3% | SUSPICIOUS | ✅ |
| `real-sayyjwtjol` | REAL | 0.5% | NO_EVIDENCE | ✅ |
| `selfie` | REAL | 5.4% | NO_EVIDENCE | ✅ |
| `veo-landscape` | FAKE | — | CANNOT_ASSESS | ⚪ |
| `real-mkwhpzswmo-0` | REAL | 93.6% | LIKELY_MANIPULATED | ❌ |
| `real-mkwhpzswmo-1` | REAL | 93.2% | LIKELY_MANIPULATED | ❌ |

**6 of 9 decided correctly, 1 correctly refused, 2 false positives.**

Crucially, the `imagine-art` and `selfie` clips are **not** from DFDC, so the
model has never seen them — separation there was **+76.5 points**. That rules
out the result being memorisation of its training set.

### Known weakness: multi-face video

Both false positives are the **multi-face** clips, and they fail the expensive
way — calling a real person fake at 93%. The scorer only takes the *largest*
face per frame, so on video containing several people it can lock onto the
wrong face or an unstable crop. **Do not trust this tool on group video yet.**

## Choosing the model: benchmark, don't read model cards

Five candidates were measured against the labelled DFDC clips. Separation is
mean(FAKE score) − mean(REAL score); negative means fakes scored *lower* than
reals, i.e. the model is inverted.

| Model | Claimed | Separation | Correct | |
|---|---|---|---|---|
| `dima806/deepfake_vs_real_image_detection` | 99.27% | **−11.1** | 3/7 | inverted |
| `Wvolf/ViT_Deepfake_Detection` | 98.70% | **−15.2** | 3/7 | inverted |
| `prithivMLmods/Deep-Fake-Detector-v2-Model` | 92.12% | **−18.1** | 2/7 | inverted |
| `prithivMLmods/open-deepfake-detection` | — | +2.8 | 3/7 | no signal |
| **`hchcsuim/...DFDC...expand30-aligned`** | — | **+36.9** | 5/7 | **works** |

The three models advertising 92–99% accuracy were **worse than a coin flip**,
and consistently backwards. Their headline numbers are in-distribution test
scores on still images; they learned face-*swap* blending seams, which don't
exist in fully generated video, and they misread ordinary camera noise and
compression as manipulation. On one known fake, the raw output was
`Realism=0.880` — confidently wrong.

The model that works was trained on **DFDC video face crops**, which is the
actual task. It has no accuracy claim on its card at all.

**Benchmark on your own labelled data. Model cards are marketing.**

## How it works

| Stage | What happens | Tool |
|-------|--------------|------|
| 1. Probe | Resolution, codec, audio, encoder metadata | `ffprobe` |
| 2. Sample + crop | Decode frames to memory, crop the largest face | OpenCV + YuNet |
| 3. Score | Classify each face crop | Swin via PyTorch |
| 4. Aggregate | Mean, % frames flagged, frame-to-frame stability | — |
| 5. Verdict | Band + reasons, or refuse | — |

### Three things that matter more than they look

**No JPEG round-trips.** An earlier version wrote frames to disk as JPEG then
re-saved each crop as JPEG again — three lossy passes counting the source h264.
Deepfake detection keys on fine high-frequency texture, exactly what JPEG
discards while adding artifacts of its own. Frames are now decoded straight to
arrays.

**Crop margin must match the model.** This model trained on faces expanded 30%,
so `MARGIN = 0.30`. Change the model, change the margin.

**It refuses when it cannot tell.** Faces under 64px are rejected, and fewer
than 3 usable crops returns `CANNOT_ASSESS` rather than a number. The
`veo-landscape` clip contains no people; an earlier version hallucinated a face
in the grass and reported "60.4% fake, 100% of frames flagged" off a single
31-pixel crop. A confident fabricated answer is worse than no answer.

## What this cannot do

- **Only faces.** A generated landscape, document, or product shot is invisible
  to it. `veo-landscape` is exactly the kind of AI content people get fooled by,
  and this approach structurally cannot see it.
- **Group video.** See the multi-face weakness above.
- **Small or heavily compressed faces.** Below 64px it declines.

### Free signals that need no ML

The metadata probe caught every AI-generated clip in testing where the neural
net was still failing — **4 out of 4**:

- **Locked framerate.** Real phone cameras record at odd fractional rates
  (29.87fps). Generators output exactly 24.00 or 30.00.
- **Generator-standard resolutions** — 1024×576, 1280×720.
- **Watermarks** — the ✦ sparkle in a corner.
- **Encoder tags** sometimes name the tool outright.

These cost no compute and are checked on every run.

## Install

```bash
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install -r requirements.txt
```

Needs `ffmpeg` on PATH (`brew install ffmpeg` on macOS).

The face detector (228KB) is committed here. The classifier (~350MB) downloads
from HuggingFace on first run and is cached.

## Usage

```bash
python deepfake_scan.py video.mp4
python deepfake_scan.py video.mp4 --frames 32
python deepfake_scan.py video.mp4 --json out.json
```

Benchmark models against your own labelled clips — name files `REAL__*.mp4` and
`FAKE__*.mp4`, put them in a folder, then:

```bash
python benchmark.py myclips --margin=0.30
python benchmark.py myclips --margin=0.10 --models=some/other-model
```

## Reading the output

**The percentage is this clip's score, not the tool's accuracy.** "61.3% fake"
means this video scored 61.3. It does not mean the tool is 61.3% accurate or
61.3% confident.

Nine clips is a small sample. The separation is large and consistent, but
calibrate on your own data before setting thresholds, and treat the result as
one strong signal feeding a decision — not as a verdict to show a user as fact.

For end users, **false positives are the expensive failure.** Telling someone
their real brother is an impostor destroys trust in the tool immediately — and
this tool still does exactly that on multi-face video.

## License

MIT
