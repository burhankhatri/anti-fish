#!/usr/bin/env python3
"""Checks one image for AI generation or a swapped face.

deepfake-check's own `classify` decides the verdict, so the rule is theirs. The HTTP call is
rewritten on urllib because `requests` is not part of the standard library and a demo machine
should not need a pip install to run the app.

    imagebridge.py /path/to/photo.jpg   → one JSON object on stdout

The image is uploaded to SightEngine. That is the only part of AntiFish that leaves the Mac.
"""

from __future__ import annotations

import json
import mimetypes
import os
import sys
import urllib.request
import uuid
from pathlib import Path

VENDOR = Path(__file__).resolve().parent.parent / "Vendor" / "deepfake"
sys.path.insert(0, str(VENDOR))

from detect import classify, API_URL  # noqa: E402  — their rule, their endpoint

MODELS = "genai,deepfake"


def _multipart(fields: dict[str, str], file_path: Path) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    line = f"--{boundary}".encode()
    parts: list[bytes] = []
    for key, value in fields.items():
        parts += [line, f'Content-Disposition: form-data; name="{key}"'.encode(), b"", value.encode()]
    mime = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    parts += [
        line,
        f'Content-Disposition: form-data; name="media"; filename="{file_path.name}"'.encode(),
        f"Content-Type: {mime}".encode(),
        b"",
        file_path.read_bytes(),
        f"--{boundary}--".encode(),
        b"",
    ]
    return b"\r\n".join(parts), f"multipart/form-data; boundary={boundary}"


def check(path: Path, user: str, secret: str, threshold: float = 0.5, timeout: int = 30) -> dict:
    body, content_type = _multipart(
        {"models": MODELS, "api_user": user, "api_secret": secret}, path)
    request = urllib.request.Request(API_URL, data=body,
                                     headers={"Content-Type": content_type})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))

    if payload.get("status") != "success":
        return {"path": str(path), "verdict": "error",
                "error": payload.get("error", {}).get("message", "unknown error")}

    ai = float(payload.get("type", {}).get("ai_generated", 0.0))
    deepfake = float(payload.get("type", {}).get("deepfake", 0.0))
    verdict, confidence = classify(ai, deepfake, threshold)
    return {
        "path": str(path),
        "verdict": verdict,
        "confidence": round(confidence, 4),
        "ai_generated": round(ai, 4),
        "deepfake": round(deepfake, 4),
    }


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: imagebridge.py <image>", file=sys.stderr)
        return 2
    user = os.environ.get("SIGHTENGINE_USER", "")
    secret = os.environ.get("SIGHTENGINE_SECRET", "")
    if not user or not secret:
        print(json.dumps({"verdict": "error", "error": "no SightEngine credentials"}))
        return 3
    path = Path(sys.argv[1])
    if not path.exists():
        print(json.dumps({"verdict": "error", "error": f"no such file: {path}"}))
        return 4
    try:
        print(json.dumps(check(path, user, secret)))
    except Exception as exc:
        print(json.dumps({"verdict": "error", "error": f"{type(exc).__name__}: {exc}"}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
