#!/usr/bin/env python3
"""
deepfake-check — tell whether an image is AI-generated or has a swapped face.

    python detect.py photo.jpg
    python detect.py images/ --csv results.csv --html report.html

Backends:
    sightengine  (default)  hosted API, free tier covers ~1,000 images/month
    local                   open-source models on your own machine, no key, unlimited
    mock                    deterministic fake scores, for testing the plumbing offline

See README.md for setup.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import os
import sys
import time
from dataclasses import dataclass, asdict, field
from datetime import date
from pathlib import Path
from typing import Iterable

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"}
API_URL = "https://api.sightengine.com/1.0/check.json"

STATE_DIR = Path.home() / ".deepfake-check"
CACHE_FILE = STATE_DIR / "cache.json"
BUDGET_FILE = STATE_DIR / "budget.json"


# ────────────────────────────────────────────────────────────── result model


@dataclass
class Result:
    path: str
    verdict: str = "error"
    confidence: float = 0.0
    ai_generated: float = 0.0
    deepfake: float = 0.0
    likely_generator: str = ""
    error: str = ""
    cached: bool = field(default=False, compare=False)

    @property
    def suspicious(self) -> bool:
        return self.verdict in {"AI-GENERATED", "FACE-SWAPPED"}


def classify(ai: float, deepfake: float, threshold: float) -> tuple[str, float]:
    """Turn two raw scores into a verdict.

    Deliberately has an UNCERTAIN band: on real-world images (re-compressed,
    screenshotted, from a generator the model has never seen) these detectors
    land mid-range far more often than the marketing numbers suggest, and
    'not sure' is a more useful answer than a confident wrong one.
    """
    if ai >= threshold and ai >= deepfake:
        return "AI-GENERATED", ai
    if deepfake >= threshold:
        return "FACE-SWAPPED", deepfake
    if max(ai, deepfake) > threshold * 0.6:
        return "UNCERTAIN", max(ai, deepfake)
    return "AUTHENTIC", 1.0 - max(ai, deepfake)


# ────────────────────────────────────────────────────────────── daily budget


def _load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def _save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1))


class DailyBudget:
    """Stops a stray `detect.py my_whole_photo_library/` from eating the month's quota.

    Sightengine bills per model, so asking for genai+deepfake costs 2 operations
    per image. The free tier is 2,000 ops/month => ~1,000 images.
    """

    def __init__(self, limit: int):
        self.limit = limit
        self.today = date.today().isoformat()
        # Keyed by date, so yesterday's count never leaks into today's budget.
        self.used = _load_json(BUDGET_FILE, {}).get(self.today, 0)

    @property
    def remaining(self) -> int:
        return max(0, self.limit - self.used)

    def spend(self, n: int = 1) -> None:
        self.used += n
        _save_json(BUDGET_FILE, {self.today: self.used})


# ───────────────────────────────────────────────────────────────── backends


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


class SightengineBackend:
    """Hosted API. One request returns both detections."""

    name = "sightengine"
    cost_per_image = 2  # genai + deepfake

    def __init__(self, user: str, secret: str):
        import requests  # imported here so `--backend mock/local` works without it

        self.requests = requests
        self.user = user
        self.secret = secret

    def analyze(self, path: Path) -> tuple[float, float, str]:
        with path.open("rb") as fh:
            response = self.requests.post(
                API_URL,
                files={"media": (path.name, fh)},
                data={
                    "models": "genai,deepfake",
                    "api_user": self.user,
                    "api_secret": self.secret,
                },
                timeout=60,
            )
        payload = response.json()

        if payload.get("status") == "failure":
            err = payload.get("error", {})
            raise RuntimeError(f"{err.get('code', '?')}: {err.get('message', 'unknown error')}")

        t = payload.get("type", {})
        ai = float(t.get("ai_generated", 0.0))
        deepfake = float(t.get("deepfake", 0.0))
        generators = t.get("ai_generators", {}) or {}
        top = max(generators, key=generators.get) if generators else ""
        return ai, deepfake, (top if ai >= 0.5 else "")


class LocalBackend:
    """Open-source models on your own machine. No key, no quota, works offline.

    First run downloads ~200 MB. CPU inference is roughly 1-2 s per image, which
    is fine for 20 images a day.
    """

    name = "local"
    cost_per_image = 0

    TRIAGE = "prithivMLmods/AI-vs-Deepfake-vs-Real-Siglip2"

    def __init__(self):
        from PIL import Image
        from transformers import pipeline

        self.Image = Image
        print(f"loading {self.TRIAGE} (first run downloads ~200 MB)...", file=sys.stderr)
        self.pipe = pipeline("image-classification", model=self.TRIAGE)

    def analyze(self, path: Path) -> tuple[float, float, str]:
        image = self.Image.open(path).convert("RGB")
        scores = {p["label"].lower(): float(p["score"]) for p in self.pipe(image)}
        return scores.get("ai", 0.0), scores.get("deepfake", 0.0), ""


class MockBackend:
    """Deterministic pseudo-scores derived from the file hash.

    Exists so the whole pipeline - budget, cache, CSV, HTML - can be exercised
    without a key or a network. Never reports anything meaningful about an image.
    """

    name = "mock"
    cost_per_image = 0

    def analyze(self, path: Path) -> tuple[float, float, str]:
        digest = sha256(path)
        ai = int(digest[:4], 16) / 0xFFFF
        deepfake = int(digest[4:8], 16) / 0xFFFF
        return ai, deepfake, ("mock-generator" if ai >= 0.5 else "")


# ─────────────────────────────────────────────────────────────────── runner


def collect_images(inputs: Iterable[str]) -> list[Path]:
    found: list[Path] = []
    for raw in inputs:
        p = Path(raw)
        if p.is_dir():
            found += sorted(q for q in p.rglob("*") if q.suffix.lower() in IMAGE_SUFFIXES)
        elif p.is_file():
            found.append(p)
        else:
            print(f"skipping (not found): {raw}", file=sys.stderr)
    return found


def run(images: list[Path], backend, threshold: float, budget: DailyBudget | None,
        use_cache: bool) -> list[Result]:
    cache = _load_json(CACHE_FILE, {}) if use_cache else {}
    results: list[Result] = []

    for path in images:
        key = f"{backend.name}:{sha256(path)}" if use_cache else None

        if key and key in cache:
            ai, deepfake, generator = cache[key]
            verdict, confidence = classify(ai, deepfake, threshold)
            results.append(Result(str(path), verdict, confidence, ai, deepfake,
                                  generator, cached=True))
            continue

        if budget is not None and budget.remaining < 1:
            results.append(Result(str(path), error=f"daily limit of {budget.limit} images reached"))
            continue

        try:
            ai, deepfake, generator = backend.analyze(path)
        except Exception as exc:  # network, quota, unreadable file
            results.append(Result(str(path), error=str(exc)))
            continue

        if budget is not None:
            budget.spend(1)
        if key is not None:
            cache[key] = [ai, deepfake, generator]

        verdict, confidence = classify(ai, deepfake, threshold)
        results.append(Result(str(path), verdict, confidence, ai, deepfake, generator))

    if use_cache:
        _save_json(CACHE_FILE, cache)
    return results


# ─────────────────────────────────────────────────────────────────── output


MARK = {
    "AI-GENERATED": "[AI]",
    "FACE-SWAPPED": "[SWAP]",
    "UNCERTAIN":    "[?]",
    "AUTHENTIC":    "[ok]",
    "error":        "[!]",
}


def print_table(results: list[Result]) -> None:
    if not results:
        print("no images found")
        return

    width = min(44, max(len(Path(r.path).name) for r in results))
    print()
    print(f"{'':6} {'FILE':<{width}}  {'VERDICT':<13} {'CONF':>5}  DETAIL")
    print("-" * (width + 42))

    for r in results:
        name = Path(r.path).name
        name = name if len(name) <= width else name[: width - 1] + "…"
        if r.error:
            print(f"{MARK['error']:6} {name:<{width}}  {'ERROR':<13} {'':>5}  {r.error}")
            continue
        detail = []
        if r.likely_generator:
            detail.append(r.likely_generator)
        detail.append(f"ai={r.ai_generated:.2f} swap={r.deepfake:.2f}")
        if r.cached:
            detail.append("(cached)")
        print(f"{MARK[r.verdict]:6} {name:<{width}}  {r.verdict:<13} "
              f"{r.confidence:>5.0%}  {' '.join(detail)}")

    counts: dict[str, int] = {}
    for r in results:
        counts[r.verdict if not r.error else "error"] = counts.get(
            r.verdict if not r.error else "error", 0) + 1
    print("-" * (width + 42))
    print("  " + "   ".join(f"{k}: {v}" for k, v in sorted(counts.items())))


def write_csv(results: list[Result], path: Path) -> None:
    fields = ["path", "verdict", "confidence", "ai_generated", "deepfake",
              "likely_generator", "error"]
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for r in results:
            writer.writerow({k: v for k, v in asdict(r).items() if k in fields})
    print(f"\nwrote {path}")


def write_html(results: list[Result], path: Path) -> None:
    colors = {"AI-GENERATED": "#c2410c", "FACE-SWAPPED": "#b91c1c",
              "UNCERTAIN": "#a16207", "AUTHENTIC": "#15803d", "error": "#6b7280"}
    rows = []
    for r in results:
        verdict = "error" if r.error else r.verdict
        detail = html.escape(r.error) if r.error else (
            f"ai={r.ai_generated:.3f} &nbsp; swap={r.deepfake:.3f}"
            + (f" &nbsp; <em>{html.escape(r.likely_generator)}</em>" if r.likely_generator else "")
        )
        rows.append(
            f"<tr><td class=f>{html.escape(Path(r.path).name)}</td>"
            f"<td><span class=v style='background:{colors[verdict]}'>{verdict}</span></td>"
            f"<td class=n>{'' if r.error else format(r.confidence, '.0%')}</td>"
            f"<td class=d>{detail}</td></tr>"
        )
    path.write_text(f"""<!doctype html><meta charset=utf-8>
<title>Image authenticity report</title>
<style>
 body{{font:14px/1.5 -apple-system,Segoe UI,sans-serif;margin:2rem auto;max-width:900px;padding:0 1rem;color:#111}}
 h1{{font-size:1.3rem}} table{{border-collapse:collapse;width:100%}}
 th,td{{text-align:left;padding:.5rem .6rem;border-bottom:1px solid #e5e7eb;vertical-align:middle}}
 th{{font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;color:#6b7280}}
 .f{{font-family:ui-monospace,Consolas,monospace;font-size:.85rem}}
 .v{{color:#fff;padding:.15rem .5rem;border-radius:999px;font-size:.7rem;font-weight:600;white-space:nowrap}}
 .n{{text-align:right;font-variant-numeric:tabular-nums}}
 .d{{color:#6b7280;font-size:.8rem;font-family:ui-monospace,Consolas,monospace}}
 p.note{{color:#6b7280;font-size:.8rem;border-top:1px solid #e5e7eb;padding-top:1rem;margin-top:2rem}}
</style>
<h1>Image authenticity report</h1>
<p style="color:#6b7280">{len(results)} images &middot; {time.strftime('%Y-%m-%d %H:%M')}</p>
<table><tr><th>File<th>Verdict<th>Conf<th>Scores</tr>{''.join(rows)}</table>
<p class=note>Scores are probabilistic signals, not proof. Detectors degrade on
generators they were not trained on and on re-compressed or screenshotted images.
Treat UNCERTAIN as "unknown", and do not present any verdict here as a finding of fact.</p>
""", encoding="utf-8")
    print(f"wrote {path}")


# ───────────────────────────────────────────────────────────────────── main


def build_backend(args):
    if args.backend == "mock":
        return MockBackend()
    if args.backend == "local":
        return LocalBackend()

    user = args.api_user or os.environ.get("SIGHTENGINE_USER")
    secret = args.api_secret or os.environ.get("SIGHTENGINE_SECRET")
    if not user or not secret:
        sys.exit(
            "Missing credentials.\n"
            "  Set SIGHTENGINE_USER and SIGHTENGINE_SECRET (see README), or pass\n"
            "  --api-user / --api-secret, or use --backend local for no-key mode."
        )
    return SightengineBackend(user, secret)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect AI-generated images and face swaps.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="examples:\n"
               "  python detect.py photo.jpg\n"
               "  python detect.py images/ --html report.html\n"
               "  python detect.py images/ --backend local\n",
    )
    parser.add_argument("inputs", nargs="+", help="image files and/or folders")
    parser.add_argument("--backend", choices=["sightengine", "local", "mock"],
                        default="sightengine")
    parser.add_argument("--api-user", help="overrides SIGHTENGINE_USER")
    parser.add_argument("--api-secret", help="overrides SIGHTENGINE_SECRET")
    parser.add_argument("--threshold", type=float, default=0.5,
                        help="score at or above which a detection is reported (default 0.5)")
    parser.add_argument("--daily-limit", type=int, default=20,
                        help="max NEW images sent to the API per day (default 20); 0 disables")
    parser.add_argument("--no-cache", action="store_true",
                        help="re-analyze images even if their hash was seen before")
    parser.add_argument("--csv", type=Path, help="write results to a CSV file")
    parser.add_argument("--html", type=Path, help="write a shareable HTML report")
    args = parser.parse_args()

    images = collect_images(args.inputs)
    if not images:
        print("no images found", file=sys.stderr)
        return 1

    backend = build_backend(args)

    budget = None
    if args.daily_limit > 0 and backend.cost_per_image > 0:
        budget = DailyBudget(args.daily_limit)
        print(f"backend: {backend.name}  |  daily budget: "
              f"{budget.remaining}/{budget.limit} images left today")
    else:
        print(f"backend: {backend.name}  |  no quota (unmetered)")

    results = run(images, backend, args.threshold, budget, use_cache=not args.no_cache)
    print_table(results)

    if args.csv:
        write_csv(results, args.csv)
    if args.html:
        write_html(results, args.html)

    return 1 if any(r.error for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
