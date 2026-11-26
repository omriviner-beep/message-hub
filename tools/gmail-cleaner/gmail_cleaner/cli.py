"""Command-line interface.

    python -m gmail_cleaner scan                # fetch + classify (read only)
    python -m gmail_cleaner report              # summary per category
    python -m gmail_cleaner senders             # biggest senders
    python -m gmail_cleaner label --apply       # add Gmail labels per category
    python -m gmail_cleaner clean --category promotions --older-than 30 --apply
"""
from __future__ import annotations

import argparse
import csv
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from .classifier import CATEGORIES, Classifier, Config
from .store import Message, Store

LABEL_PREFIX = "ניקוי"
DAY_MS = 86_400_000


def _progress(done: int, total: int) -> None:
    sys.stdout.write(f"\r  {done}/{total}")
    sys.stdout.flush()
    if done >= total:
        sys.stdout.write("\n")


def _service(args):
    from .auth import get_service
    return get_service(Path(args.credentials), Path(args.token))


def _classify_all(store: Store, cfg: Config) -> list[Message]:
    clf = Classifier(cfg, store.contacted())
    msgs = store.all()
    pairs = []
    for m in msgs:
        m.category = clf.classify(m)
        pairs.append((m.id, m.category))
    store.set_categories(pairs)
    return msgs


def _fmt_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


# ---------------------------------------------------------------- commands

def cmd_scan(args, store: Store, cfg: Config) -> None:
    from . import gmail
    svc = _service(args)
    if cfg.friends_from_sent:
        print("אוסף כתובות שכתבת אליהן (תיקיית 'נשלח')...")
        store.add_contacted(gmail.fetch_contacted(svc, args.sent_max))
    print(f"מחפש הודעות: '{args.query}'...")
    ids = gmail.list_ids(svc, args.query, args.max)
    new = [i for i in ids if args.refresh or i not in store.known_ids()]
    print(f"נמצאו {len(ids)} הודעות, {len(new)} חדשות להורדה (כותרות בלבד, בלי תוכן).")
    for i in range(0, len(new), 500):
        store.upsert(gmail.fetch_metadata(svc, new[i:i + 500]))
        _progress(min(i + 500, len(new)), len(new))
    msgs = _classify_all(store, cfg)
    print(f"סווגו {len(msgs)} הודעות.\n")
    cmd_report(args, store, cfg, msgs)


def cmd_classify(args, store: Store, cfg: Config) -> None:
    """Re-run classification on the local cache (e.g. after editing config.toml)."""
    cmd_report(args, store, cfg, _classify_all(store, cfg))


def cmd_report(args, store: Store, cfg: Config, msgs: list[Message] | None = None) -> None:
    msgs = msgs if msgs is not None else store.all()
    if not msgs:
        print("אין נתונים. הרץ קודם: python -m gmail_cleaner scan")
        return
    counts = Counter(m.category for m in msgs)
    sizes = defaultdict(int)
    unread = Counter()
    for m in msgs:
        sizes[m.category] += m.size
        if "UNREAD" in m.labels:
            unread[m.category] += 1
    print(f"{'קטגוריה':<16}{'הודעות':>8}{'לא נקראו':>10}{'נפח':>9}")
    print("-" * 43)
    for key, he in CATEGORIES.items():
        if counts[key]:
            print(f"{he:<16}{counts[key]:>8}{unread[key]:>10}{_fmt_size(sizes[key]):>9}")
    print("-" * 43)
    total_label = 'סה"כ'
    print(f"{total_label:<16}{len(msgs):>8}{sum(unread.values()):>10}{_fmt_size(sum(sizes.values())):>9}")

    if getattr(args, "examples", 0):
        by_cat = defaultdict(list)
        for m in sorted(msgs, key=lambda m: -m.date_ms):
            by_cat[m.category].append(m)
        for key, he in CATEGORIES.items():
            if by_cat[key]:
                print(f"\n== {he} ==")
                for m in by_cat[key][: args.examples]:
                    print(f"  {m.sender:<35.35} {m.subject:.60}")

    if getattr(args, "csv", None):
        with open(args.csv, "w", newline="", encoding="utf-8-sig") as f:  # BOM so Excel shows Hebrew
            w = csv.writer(f)
            w.writerow(["id", "date", "category", "sender", "sender_name", "subject", "unread",
                        "has_unsubscribe", "size"])
            for m in msgs:
                w.writerow([m.id, time.strftime("%Y-%m-%d", time.localtime(m.date_ms / 1000)),
                            CATEGORIES.get(m.category, m.category), m.sender, m.sender_name,
                            m.subject, "UNREAD" in m.labels, bool(m.list_unsubscribe), m.size])
        print(f"\nנשמר קובץ {args.csv}")


def cmd_senders(args, store: Store, cfg: Config) -> None:
    msgs = store.all()
    if args.category:
        msgs = [m for m in msgs if m.category == args.category]
    by_sender: dict[str, list[Message]] = defaultdict(list)
    for m in msgs:
        by_sender[m.sender].append(m)
    top = sorted(by_sender.items(), key=lambda kv: -len(kv[1]))[: args.top]
    print(f"{'#':>5} {'לא נקראו':>8}  {'קטגוריה':<14} {'ביטול מנוי':<10} שולח")
    for sender, ms in top:
        unread = sum("UNREAD" in m.labels for m in ms)
        cat = CATEGORIES.get(Counter(m.category for m in ms).most_common(1)[0][0], "")
        unsub = "כן" if any(m.list_unsubscribe for m in ms) else ""
        print(f"{len(ms):>5} {unread:>8}  {cat:<14} {unsub:<10} {sender}")
        if args.unsubscribe_links and unsub:
            link = next(m.list_unsubscribe for m in ms if m.list_unsubscribe)
            print(f"{'':>30}↳ {link[:150]}")


def _select(store: Store, args) -> list[Message]:
    msgs = store.all()
    now = time.time() * 1000
    out = []
    for m in msgs:
        if args.category and m.category not in args.category:
            continue
        if args.sender and m.sender not in {s.lower() for s in args.sender}:
            continue
        if args.older_than and now - m.date_ms < args.older_than * DAY_MS:
            continue
        if args.unread_only and "UNREAD" not in m.labels:
            continue
        if "STARRED" in m.labels or ("IMPORTANT" in m.labels and not args.include_important):
            continue  # never touch starred; skip Gmail-"important" unless asked
        if args.action == "archive" and "INBOX" not in m.labels:
            continue
        out.append(m)
    return out


def cmd_clean(args, store: Store, cfg: Config) -> None:
    if not (args.category or args.sender):
        sys.exit("חובה לציין --category או --sender (הגנה מפני מחיקה גורפת).")
    protected = {"family", "friends", "personal"} & set(args.category or [])
    if protected and not args.force:
        sys.exit(f"הקטגוריות {', '.join(CATEGORIES[p] for p in protected)} מוגנות. הוסף --force אם אתה בטוח.")
    targets = _select(store, args)
    verb = {"trash": "להעביר לאשפה", "archive": "לארכב (להוציא מתיבת הדואר הנכנס)"}[args.action]
    print(f"{len(targets)} הודעות מתאימות {verb}. (הודעות מסומנות בכוכב לא ייגעו אף פעם)")
    for m in sorted(targets, key=lambda m: -m.date_ms)[:15]:
        print(f"  {m.sender:<35.35} {m.subject:.60}")
    if len(targets) > 15:
        print(f"  ... ועוד {len(targets) - 15}")
    if not targets:
        return
    if not args.apply:
        print("\nמצב ניסיון בלבד - שום דבר לא שונה. הוסף --apply כדי לבצע.")
        return
    if not args.yes and input(f"\nלבצע על {len(targets)} הודעות? הקלד yes: ").strip().lower() != "yes":
        print("בוטל.")
        return
    from . import gmail
    svc = _service(args)
    ids = [m.id for m in targets]
    if args.action == "trash":
        gmail.trash(svc, ids)
        store.remove(ids)
    else:
        gmail.archive(svc, ids)
        for m in targets:
            m.labels = [l for l in m.labels if l != "INBOX"]
        store.upsert(targets)
    print(f"בוצע. {'ניתן לשחזר מהאשפה במשך 30 יום.' if args.action == 'trash' else ''}")


def cmd_label(args, store: Store, cfg: Config) -> None:
    msgs = store.all()
    cats = args.category or [c for c in CATEGORIES if c != "other"]
    groups: dict[str, list[str]] = defaultdict(list)
    for m in msgs:
        if m.category in cats:
            groups[m.category].append(m.id)
    for c in cats:
        if groups[c]:
            print(f"  {LABEL_PREFIX}/{CATEGORIES[c]}: {len(groups[c])} הודעות")
    if not args.apply:
        print("\nמצב ניסיון בלבד. הוסף --apply כדי ליצור תוויות ב-Gmail ולסמן את ההודעות.")
        return
    from . import gmail
    svc = _service(args)
    names = {c: f"{LABEL_PREFIX}/{CATEGORIES[c]}" for c in cats if groups[c]}
    label_ids = gmail.ensure_labels(svc, [LABEL_PREFIX] + list(names.values()))
    for c, name in names.items():
        gmail.batch_modify(svc, groups[c], add=[label_ids[name]])
    print("התוויות נוספו. הן מופיעות בצד שמאל ב-Gmail תחת 'ניקוי'.")


# ---------------------------------------------------------------- main

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="gmail_cleaner", description="ניקוי וסיווג Gmail")
    p.add_argument("--config", default="config.toml")
    p.add_argument("--db", default="gmail_cache.db")
    p.add_argument("--credentials", default="credentials.json")
    p.add_argument("--token", default="token.json")
    sub = p.add_subparsers(dest="cmd", required=True)
    cat_choices = list(CATEGORIES)

    s = sub.add_parser("scan", help="הורדת כותרות וסיווג (קריאה בלבד)")
    s.add_argument("--query", default="newer_than:2y -in:chats",
                   help="שאילתת חיפוש של Gmail, למשל 'in:inbox' או 'older_than:1y'")
    s.add_argument("--max", type=int, default=10000, help="מספר הודעות מקסימלי")
    s.add_argument("--sent-max", type=int, default=2000)
    s.add_argument("--refresh", action="store_true", help="הורד מחדש גם הודעות שכבר במטמון")
    s.add_argument("--examples", type=int, default=0)
    s.add_argument("--csv")

    c = sub.add_parser("classify", help="סיווג מחדש מהמטמון (אחרי עריכת config.toml)")
    c.add_argument("--examples", type=int, default=5)
    c.add_argument("--csv")

    r = sub.add_parser("report", help="סיכום לפי קטגוריה")
    r.add_argument("--examples", type=int, default=0, help="הצג N דוגמאות לכל קטגוריה")
    r.add_argument("--csv", help="ייצוא לקובץ CSV")

    se = sub.add_parser("senders", help="השולחים הגדולים")
    se.add_argument("--top", type=int, default=30)
    se.add_argument("--category", choices=cat_choices)
    se.add_argument("--unsubscribe-links", action="store_true", help="הצג קישורי ביטול מנוי")

    cl = sub.add_parser("clean", help="העברה לאשפה / ארכוב")
    cl.add_argument("--category", nargs="+", choices=cat_choices)
    cl.add_argument("--sender", nargs="+", help="כתובת שולח אחת או יותר")
    cl.add_argument("--older-than", type=int, metavar="DAYS")
    cl.add_argument("--unread-only", action="store_true")
    cl.add_argument("--action", choices=["trash", "archive"], default="trash")
    cl.add_argument("--include-important", action="store_true")
    cl.add_argument("--force", action="store_true", help="אפשר פעולה על משפחה/חברים/אנשים")
    cl.add_argument("--apply", action="store_true", help="בצע בפועל (ברירת מחדל: ניסיון בלבד)")
    cl.add_argument("--yes", action="store_true", help="בלי שאלת אישור")

    lb = sub.add_parser("label", help="הוספת תוויות Gmail לפי קטגוריה")
    lb.add_argument("--category", nargs="+", choices=cat_choices)
    lb.add_argument("--apply", action="store_true")
    return p


def main(argv=None) -> None:
    args = build_parser().parse_args(argv)
    cfg = Config.load(Path(args.config))
    store = Store(Path(args.db))
    {
        "scan": cmd_scan, "classify": cmd_classify, "report": cmd_report,
        "senders": cmd_senders, "clean": cmd_clean, "label": cmd_label,
    }[args.cmd](args, store, cfg)
