# deepfake-check

Command-line tool that tells you whether an image is **AI-generated** (Midjourney,
Flux, DALL·E, Stable Diffusion…) or a **face swap** on a real photo.

```
       FILE                          VERDICT        CONF  DETAIL
----------------------------------------------------------------------------
[ok]   family_holiday.jpg            AUTHENTIC       96%  ai=0.01 swap=0.03
[AI]   too_perfect_landscape.png     AI-GENERATED    99%  midjourney ai=0.99 swap=0.01
[SWAP] celebrity_clip_frame.jpg      FACE-SWAPPED    94%  ai=0.02 swap=0.94
[?]    compressed_repost.jpg         UNCERTAIN       41%  ai=0.41 swap=0.08
----------------------------------------------------------------------------
  AI-GENERATED: 1   AUTHENTIC: 1   FACE-SWAPPED: 1   UNCERTAIN: 1
```

Works on Windows, macOS and Linux. Point it at a file or a whole folder; get a
table, a CSV, or a shareable HTML report.

---

## Setup on Windows

### 1. Install Python

Get Python 3.10 or newer from [python.org/downloads](https://www.python.org/downloads/).
**Tick "Add python.exe to PATH"** on the first screen of the installer — if you miss it,
`python` won't be found in the next step.

Verify in a new PowerShell window:

```powershell
python --version
```

### 2. Get the code

```powershell
git clone https://github.com/YOUR_USERNAME/deepfake-check.git
cd deepfake-check
```

No Git? Download the ZIP from the green **Code** button on GitHub, extract it, then
`cd` into the folder.

### 3. Create a virtual environment

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If PowerShell refuses with *"running scripts is disabled on this system"*, run this
once, then retry the activate line:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Using `cmd.exe` instead of PowerShell? Activate with `.venv\Scripts\activate.bat`.

### 4. Get free API keys

Sign up at **[sightengine.com](https://sightengine.com/?signup)** — no credit card.
From the dashboard copy your **API user** and **API secret**.

The free tier is 2,000 operations/month. Each image costs 2 (one for the
AI-generated check, one for the face-swap check), so **20 images a day is about
1,200 a month — comfortably inside the free tier.**

Set them for your current PowerShell window:

```powershell
$env:SIGHTENGINE_USER    = "your_api_user"
$env:SIGHTENGINE_SECRET  = "your_api_secret"
```

To keep them permanently, so you don't retype them every time:

```powershell
setx SIGHTENGINE_USER "your_api_user"
setx SIGHTENGINE_SECRET "your_api_secret"
```

`setx` only affects **new** windows — close and reopen PowerShell afterwards.

### 5. Run it

```powershell
python detect.py C:\Users\You\Pictures\test.jpg
```

A whole folder, with an HTML report you can open in your browser:

```powershell
python detect.py C:\Users\You\Pictures\testset --html report.html
```

---

## Try it with no API key at all

Two options, neither of which touches your quota:

```powershell
python detect.py images\ --backend mock
```

`mock` invents deterministic scores from the file hash. It proves the tool runs
correctly on your machine — it tells you **nothing** about the actual images.

```powershell
pip install -r requirements-local.txt
python detect.py images\ --backend local
```

`local` runs an open-source model
([AI-vs-Deepfake-vs-Real-Siglip2](https://huggingface.co/prithivMLmods/AI-vs-Deepfake-vs-Real-Siglip2),
Apache-2.0) on your own CPU. No key, no quota, works offline, well under a second
per image once it has loaded. Setting it up is the next section.

---

## Making the local backup work

`local` is the fallback for when the API is unreachable, the key is missing, or the
day's quota is gone. It needs three things: the packages, one download, and the disk
to hold them. There is no key and no account.

### 1. Install the packages

```powershell
pip install -r requirements-local.txt
```

That adds `torch`, `transformers` and `pillow` on top of `requests`.

**If you don't have an NVIDIA GPU, do this instead.** A plain `pip install torch` on
Windows fetches the CUDA build — about 2.4 GB of GPU libraries you will never execute:

```powershell
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install transformers pillow
```

The CPU wheel unpacks to roughly 470 MB rather than 2.4 GB. Speed is unaffected: this
backend runs on the CPU either way.

### 2. Let it download the model, once

The first `--backend local` run fetches about **355 MB** of weights and prints:

```
loading prithivMLmods/AI-vs-Deepfake-vs-Real-Siglip2 (first run downloads ~200 MB)...
Device set to use cpu
```

(The "~200 MB" in that message understates it; 355 MB is what actually lands.) That
run is the only one needing network access. Weights are cached under
`C:\Users\You\.cache\huggingface\hub\` and reused from then on.

### 3. Confirm it works

```powershell
python detect.py C:\Users\You\Pictures\test.jpg --backend local
```

A results table means you're set. With no key to misconfigure, the only realistic
failures are a missing package or an interrupted download.

### Running it fully offline

Once the weights are cached, stop it checking for updates so a dead connection can't
stall a run:

```powershell
$env:HF_HUB_OFFLINE = "1"
```

### Disk, and how to reclaim it

| What | Where | Size |
|---|---|---|
| PyTorch + transformers | your venv's `site-packages\` | ~470 MB (CPU build) |
| Model weights | `C:\Users\You\.cache\huggingface\hub\` | ~355 MB |

Delete the `models--prithivMLmods--*` folder in that cache to get the space back; the
next run re-downloads it. To put the cache on another drive, set `$env:HF_HOME`
**before** the first run.

### How much to trust it

Less than the hosted backend, and it is worth knowing the shape of the difference
before you lean on it. Spot-checked against the API on the same files, the model never
once returned `Real`, and disagreed on the verdict:

| Image | `sightengine` | `local` |
|---|---|---|
| An AI-generated PNG | `AI-GENERATED` 99% | `FACE-SWAPPED` 75% |
| An ordinary phone photo | `AUTHENTIC` 99% | `FACE-SWAPPED` 100% |

Three images is not a benchmark and your mileage will differ. But the failure mode to
expect is **a confident `FACE-SWAPPED` on images that are nothing of the sort**, so
read a local `FACE-SWAPPED` as "this scored high" rather than as a finding. Everything
under *Please read this before trusting a verdict* applies here with room to spare.

---

## Usage

```
python detect.py <files-or-folders> [options]

  --backend {sightengine,local,mock}   default: sightengine
  --threshold FLOAT                    detection cutoff, default 0.5
  --daily-limit N                      max new API images per day, default 20 (0 = off)
  --no-cache                           re-analyze images already seen
  --csv PATH                           write results as CSV
  --html PATH                          write a shareable HTML report
  --api-user / --api-secret            override the environment variables
```

**Two things that quietly save you money:**

*Results are cached by file hash.* Running the tool twice on the same folder costs
one folder's worth of quota, not two.

*There's a daily limit of 20 new images*, matching the free tier. Pointing the tool
at a 4,000-photo library stops at 20 instead of burning two months of quota in a
minute. Raise it with `--daily-limit 100`, or disable with `--daily-limit 0`.

Counters live in `~/.deepfake-check/` (`C:\Users\You\.deepfake-check\` on Windows).
Delete that folder to reset.

---

## How to read the results

| Verdict | Meaning |
|---|---|
| `AUTHENTIC` | No generation or face-manipulation signal found |
| `AI-GENERATED` | The whole image looks synthesised by a generative model |
| `FACE-SWAPPED` | Looks like a real photo whose face was swapped or identity-modified |
| `UNCERTAIN` | Scored in the middle. Treat as **unknown**, not as "probably fine" |

### Please read this before trusting a verdict

These detectors are useful signals. They are **not proof**, and the published
accuracy figures are measured under much friendlier conditions than real images.

- Accuracy drops sharply on **generators the model has never seen** — and new ones
  ship constantly.
- It drops again on images that have been **compressed, resized, screenshotted, or
  re-saved by a messaging app**, which describes most images that circulate online.
- Independent in-the-wild benchmarks such as
  [Deepfake-Eval-2024](https://github.com/nuriachandra/Deepfake-Eval-2024) found
  large accuracy drops versus the numbers reported on academic test sets.

So: `UNCERTAIN` exists on purpose, and "I can't tell" is a legitimate result. Never
present an output of this tool as a finding of fact about a real person or a real
photograph. Where an image carries [C2PA](https://c2pa.org/) content credentials,
that signed provenance is far stronger evidence than any detector score — check it
first. (Absence of a manifest proves nothing.)

---

## Tests

No network or API key required:

```powershell
python test_detect.py
```

Covers the verdict thresholds, daily-budget enforcement, cache behaviour, the
Sightengine response contract, and report generation.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `'python' is not recognized` | Python isn't on PATH. Reinstall and tick "Add python.exe to PATH", or use `py` instead. |
| `running scripts is disabled on this system` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, then activate again. |
| `Missing credentials` | Environment variables not set in *this* window. Re-run the `$env:` lines, or reopen PowerShell if you used `setx`. |
| `ERROR ... 14: invalid api_secret` | Wrong key, or a stray space when pasting. |
| `daily limit of 20 images reached` | Expected guard. `--daily-limit 50`, or wait until tomorrow. |
| Everything comes back `UNCERTAIN` | Often heavily compressed images. Try originals rather than screenshots or WhatsApp copies. |
| `--backend local`: `No module named 'torch'` | `pip install -r requirements-local.txt`, in the same venv you run `detect.py` from. |
| `--backend local` hangs on first run | It's pulling 355 MB of weights. Let it finish once; later runs load from cache. |
| `--backend local` fails offline | The weights aren't cached yet. Run it once with a connection, then set `$env:HF_HUB_OFFLINE = "1"`. |
| `pip install torch` is downloading gigabytes | You're getting the CUDA build. Cancel, then `pip install torch --index-url https://download.pytorch.org/whl/cpu`. |

---

## Licence

MIT. The hosted backend is [Sightengine](https://sightengine.com) (commercial, free
tier); the local backend uses
[AI-vs-Deepfake-vs-Real-Siglip2](https://huggingface.co/prithivMLmods/AI-vs-Deepfake-vs-Real-Siglip2)
(Apache-2.0).
