"""Thin wrapper around the Gmail API: listing, batched metadata fetch, labels, modify."""
from __future__ import annotations

import time
from email.utils import getaddresses, parseaddr

from .store import Message

BATCH_SIZE = 50  # Gmail recommends <=50 requests per batch to avoid rate limiting
HEADERS = ["From", "Subject", "List-Unsubscribe", "To", "Cc"]


def list_ids(service, query: str, max_results: int | None, label_ids=None) -> list[str]:
    ids: list[str] = []
    token = None
    while True:
        kwargs = dict(userId="me", q=query, maxResults=500, pageToken=token)
        if label_ids:
            kwargs["labelIds"] = label_ids
        resp = service.users().messages().list(**kwargs).execute()
        ids.extend(m["id"] for m in resp.get("messages", []))
        token = resp.get("nextPageToken")
        if not token or (max_results and len(ids) >= max_results):
            break
    return ids[:max_results] if max_results else ids


def _parse(raw: dict) -> Message:
    headers = {h["name"].lower(): h["value"] for h in raw.get("payload", {}).get("headers", [])}
    name, addr = parseaddr(headers.get("from", ""))
    return Message(
        id=raw["id"],
        thread_id=raw.get("threadId", ""),
        sender=addr.lower(),
        sender_name=name,
        subject=headers.get("subject", ""),
        snippet=raw.get("snippet", ""),
        date_ms=int(raw.get("internalDate", 0)),
        labels=raw.get("labelIds", []),
        list_unsubscribe=headers.get("list-unsubscribe", ""),
        size=int(raw.get("sizeEstimate", 0)),
    )


def _recipients(raw: dict) -> set[str]:
    hs = [h["value"] for h in raw.get("payload", {}).get("headers", [])
          if h["name"].lower() in ("to", "cc")]
    return {a.lower() for _, a in getaddresses(hs) if a}


def fetch_metadata(service, ids: list[str], on_progress=None, raw_out: bool = False):
    """Fetch metadata for ids in batches. Returns list of Message (or raw dicts)."""
    results: list = []
    pending = list(ids)
    retries = 0
    while pending:
        chunk, pending = pending[:BATCH_SIZE], pending[BATCH_SIZE:]
        failed: list[str] = []

        def cb(req_id, resp, exc):
            if exc is not None:
                failed.append(req_id)
            else:
                results.append(resp if raw_out else _parse(resp))

        batch = service.new_batch_http_request(callback=cb)
        for mid in chunk:
            batch.add(
                service.users().messages().get(
                    userId="me", id=mid, format="metadata", metadataHeaders=HEADERS
                ),
                request_id=mid,
            )
        batch.execute()
        if failed:
            # Usually 429 rate limit - back off and retry those ids
            retries += 1
            if retries > 8:
                raise RuntimeError(f"נכשלה הבאת {len(failed)} הודעות לאחר ניסיונות חוזרים")
            time.sleep(min(2 ** retries, 30))
            pending = failed + pending
        else:
            retries = 0
        if on_progress:
            on_progress(len(results), len(ids))
    return results


def fetch_contacted(service, max_results: int = 2000) -> set[str]:
    """Addresses you have written to (from Sent mail) - a strong signal for real people."""
    ids = list_ids(service, "", max_results, label_ids=["SENT"])
    raws = fetch_metadata(service, ids, raw_out=True)
    out: set[str] = set()
    for r in raws:
        out |= _recipients(r)
    return out


def ensure_labels(service, names: list[str]) -> dict[str, str]:
    existing = service.users().labels().list(userId="me").execute().get("labels", [])
    by_name = {l["name"]: l["id"] for l in existing}
    for n in names:
        if n not in by_name:
            created = service.users().labels().create(
                userId="me",
                body={"name": n, "labelListVisibility": "labelShow",
                      "messageListVisibility": "show"},
            ).execute()
            by_name[n] = created["id"]
    return by_name


def batch_modify(service, ids: list[str], add=None, remove=None) -> None:
    for i in range(0, len(ids), 1000):  # API max 1000 ids per call
        service.users().messages().batchModify(
            userId="me",
            body={"ids": ids[i:i + 1000], "addLabelIds": add or [], "removeLabelIds": remove or []},
        ).execute()


def trash(service, ids: list[str]) -> None:
    """Move to Trash (recoverable; Gmail purges Trash after 30 days)."""
    pending = list(ids)
    retries = 0
    while pending:
        chunk, pending = pending[:BATCH_SIZE], pending[BATCH_SIZE:]
        failed: list[str] = []
        batch = service.new_batch_http_request(
            callback=lambda rid, resp, exc: failed.append(rid) if exc else None
        )
        for mid in chunk:
            batch.add(service.users().messages().trash(userId="me", id=mid), request_id=mid)
        batch.execute()
        if failed:
            retries += 1
            if retries > 8:
                raise RuntimeError(f"נכשלה העברה לאשפה של {len(failed)} הודעות")
            time.sleep(min(2 ** retries, 30))
            pending = failed + pending
        else:
            retries = 0


def archive(service, ids: list[str]) -> None:
    batch_modify(service, ids, remove=["INBOX"])
