#!/usr/bin/env python3
"""Runs Shahmeer Irfan's PhishGuard engine over mail already on this Mac.

PhishGuard ingests from Gmail over OAuth. AntiFish does not: Mail.app has
already downloaded the messages, so this reads those .emlx files directly and
feeds the raw RFC822 bytes into the same store and the same detection layers.
Nothing about the detection is reimplemented here.

    phishbridge.py scan  --limit 800 --pick 30   → JSON verdicts on stdout
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import sys
import tempfile
from pathlib import Path

VENDOR = Path(__file__).resolve().parent.parent / "Vendor"
sys.path.insert(0, str(VENDOR))

from phishguard.db.store import Store                      # noqa: E402
from phishguard.parse.message import parse_rfc822           # noqa: E402
from phishguard.detect.context import build_context         # noqa: E402
from phishguard.detect.engine import analyse                # noqa: E402
from phishguard.detect.view import MessageView              # noqa: E402

MAIL_ROOT = Path.home() / "Library" / "Mail"


def emlx_files(root: Path = MAIL_ROOT, limit: int | None = None,
               mailbox: str | None = None) -> list[Path]:
    """Newest first, so a small sample is still recent mail."""
    files = [p for p in root.rglob("*.emlx") if not p.name.startswith("._")]
    if mailbox:
        needle = mailbox.lower()
        files = [p for p in files if needle in mailbox_of(p).lower()]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[:limit] if limit else files


def read_emlx(path: Path) -> tuple[bytes, dict]:
    """An .emlx is a byte count, the RFC822 message, then a plist of Mail's own flags."""
    data = path.read_bytes()
    newline = data.find(b"\n")
    if newline < 0:
        return data, {}
    try:
        length = int(data[:newline].strip())
    except ValueError:
        return data, {}
    raw = data[newline + 1: newline + 1 + length]
    trailer = data[newline + 1 + length:]
    meta: dict = {}
    start = trailer.find(b"<?xml")
    if start >= 0:
        try:
            meta = plistlib.loads(trailer[start:])
        except Exception:
            meta = {}
    return raw, meta


def mailbox_of(path: Path) -> str:
    parts = [p for p in path.parts if p.endswith(".mbox")]
    return parts[-1][:-5] if parts else "Mail"


SENT_MAILBOXES = {"sent mail", "sent messages", "drafts", "outbox", "sendlater"}


def ingest(store: Store, account_id: int, paths: list[Path]) -> list[tuple[int, Path]]:
    ingested = []
    for path in paths:
        try:
            raw, meta = read_emlx(path)
            if not raw:
                continue
            parsed = parse_rfc822(raw)
            labels = [mailbox_of(path).upper().replace(" ", "_")]
            if meta.get("flags", 0) and isinstance(meta.get("flags"), int):
                pass
            gmail_meta = {
                "id": f"emlx:{path.stem}:{abs(hash(str(path))) % 10**10}",
                "threadId": parsed.header("Message-ID") or path.stem,
                "labelIds": labels,
                "historyId": None,
                "received_at": parsed.date_iso,
            }
            mid = store.upsert_message(account_id, gmail_meta, parsed, raw=raw)
            ingested.append((mid, path))
        except Exception as exc:  # one bad message must not stop the scan
            print(f"skip {path.name}: {type(exc).__name__}: {exc}", file=sys.stderr)
    return ingested


def account_address() -> str:
    """Whichever address Mail.app has most messages for."""
    for path in emlx_files(limit=40):
        raw, _ = read_emlx(path)
        match = re.search(rb"^Delivered-To:\s*([^\r\n]+)", raw, re.MULTILINE)
        if match:
            return match.group(1).decode("utf-8", "replace").strip()
    return "me@localhost"


def scan(limit: int, pick: int, db_path: str | None, mailbox: str | None = None) -> dict:
    if mailbox:
        paths = emlx_files(limit=limit, mailbox=mailbox)
    else:
        # Spam is where phishing that got past the provider's filter actually lives, so it is
        # always included rather than left to chance in a recency window.
        spam = emlx_files(limit=200, mailbox="Spam")
        recent = emlx_files(limit=limit)
        seen = {p for p in spam}
        paths = spam + [p for p in recent if p not in seen]
    if not paths:
        return {"error": "no mail found in ~/Library/Mail", "messages": []}

    tmp = db_path or str(Path(tempfile.mkdtemp(prefix="antifish-mail-")) / "mail.sqlite")
    store = Store(tmp)
    address = account_address()
    account_id = store.get_or_create_account(address)

    ingested = ingest(store, account_id, paths)
    ctx = build_context(store, account_id)

    results = []
    for message_id, path in ingested:
        if mailbox_of(path).lower() in SENT_MAILBOXES:
            continue
        row = store.conn.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()
        if row is None:
            continue
        auth = store.conn.execute(
            "SELECT * FROM auth_results WHERE message_id = ?", (message_id,)).fetchone()
        hops = store.conn.execute(
            "SELECT * FROM received_hops WHERE message_id = ? ORDER BY hop_index", (message_id,)).fetchall()
        attachments = store.conn.execute(
            "SELECT * FROM attachments WHERE message_id = ?", (message_id,)).fetchall()
        try:
            view = MessageView.from_db(row, auth, hops, attachments)
        except TypeError:
            view = MessageView.from_db(row, auth, hops)
        try:
            verdict = analyse(view, ctx)
        except Exception as exc:
            print(f"analyse failed for {path.name}: {exc}", file=sys.stderr)
            continue

        if view.from_addr.lower() == address.lower():
            continue  # the user talking to themselves is not a phishing risk
        results.append({
            "localID": f"emlx:{path.stem}",
            "path": str(path),
            "mailbox": mailbox_of(path),
            "subject": view.subject or "(no subject)",
            "fromAddress": view.from_addr,
            "fromDisplay": view.from_display,
            "fromDomain": view.from_domain,
            "receivedAt": view.received_at or "",
            "snippet": (view.body_text or "")[:280].replace("\n", " ").strip(),
            "tier": verdict.tier,
            "score": round(float(verdict.score), 4),
            "headline": verdict.headline,
            "findings": [
                {"code": f.code, "title": getattr(f, "title", f.code),
                 "detail": getattr(f, "detail", ""), "weight": float(getattr(f, "weight", 0))}
                for f in verdict.risk_findings
            ][:8],
            "mitigating": [
                {"code": f.code, "detail": getattr(f, "detail", "")}
                for f in verdict.mitigating_findings
            ][:5],
            "isFromMe": view.from_addr.lower() == address.lower(),
            "attachmentNames": [a["filename"] for a in attachments if a["filename"]],
            "hasImages": any(
                (a["content_type"] or "").startswith("image/") for a in attachments),
        })

    store.close()

    # A demo wants variety, not eight copies of the same receipt. One per
    # sender-and-subject, then the strongest verdicts across all three tiers.
    # Hard evidence beats a high score. A newsletter full of tracking links can out-score a real
    # phishing message, so rank by how much of the evidence cannot be explained away.
    HARD = {"DKIM_FAIL", "DKIM_UNALIGNED", "DMARC_FAIL", "DMARC_FAIL_ENFORCED", "SPF_FAIL",
            "URL_FREE_HOSTING", "URL_IP_LITERAL", "URL_PUNYCODE", "LOOKALIKE_DOMAIN",
            "LOOKALIKE_DOMAIN_TLD_SWAP", "URL_LOOKALIKE_DOMAIN", "DISPLAY_NAME_IMPERSONATION",
            "HTML_FORM", "QR_CODE_PRESENT", "ATTACHMENT_EXECUTABLE", "ATTACHMENT_MACRO",
            "ATTACHMENT_DOUBLE_EXTENSION", "CREDENTIAL_REQUEST"}
    for r in results:
        r["hardCount"] = sum(1 for f in r["findings"] if f["code"] in HARD)

    order = {"danger": 0, "caution": 1, "safe": 2}
    results.sort(key=lambda r: (order.get(r["tier"], 3), -r["hardCount"], -r["score"]))

    seen: set[tuple[str, str]] = set()
    unique = []
    for r in results:
        key = (r["fromDomain"], re.sub(r"^(re|fwd?):\s*", "", r["subject"].lower())[:40])
        if key in seen:
            continue
        seen.add(key)
        unique.append(r)

    if pick:
        # Roughly half danger, a quarter caution, a quarter safe, so the list shows
        # the engine clearing mail as well as flagging it.
        want = {"danger": pick // 2, "caution": pick // 4, "safe": pick - pick // 2 - pick // 4}
        chosen, taken = [], {"danger": 0, "caution": 0, "safe": 0}
        for r in unique:
            tier = r["tier"]
            if taken.get(tier, 0) < want.get(tier, 0):
                chosen.append(r)
                taken[tier] = taken.get(tier, 0) + 1
        for r in unique:  # top up if a tier was short
            if len(chosen) >= pick:
                break
            if r not in chosen:
                chosen.append(r)
        chosen.sort(key=lambda r: r["receivedAt"], reverse=True)
    else:
        chosen = unique
    counts: dict[str, int] = {}
    for r in results:
        counts[r["tier"]] = counts.get(r["tier"], 0) + 1

    return {"scanned": len(ingested), "account": address, "tiers": counts, "messages": chosen}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["scan"])
    ap.add_argument("--limit", type=int, default=600, help="messages to ingest")
    ap.add_argument("--pick", type=int, default=30, help="messages to return")
    ap.add_argument("--db", help="reuse a store instead of a temp one")
    ap.add_argument("--mailbox", help="only this mailbox, e.g. Spam")
    args = ap.parse_args()
    json.dump(scan(args.limit, args.pick, args.db, args.mailbox), sys.stdout, indent=None)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
