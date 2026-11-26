"""Rule-based email classifier (Hebrew + English).

Rules are checked in priority order; the first match wins. Every rule can be
extended from config.toml without touching code.
"""
from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from .store import Message

# category key -> Hebrew display name (also used as Gmail label "ניקוי/<name>")
CATEGORIES: dict[str, str] = {
    "family": "משפחה",
    "friends": "חברים",
    "receipts": "קבלות",
    "finance": "כספים",
    "travel": "נסיעות",
    "social": "רשתות חברתיות",
    "promotions": "פרסומות",
    "newsletters": "ניוזלטרים",
    "notifications": "התראות",
    "personal": "אנשים אחרים",
    "other": "אחר",
}

PERSONAL_DOMAINS = {
    "gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com", "live.com",
    "icloud.com", "me.com", "walla.co.il", "walla.com", "bezeqint.net", "012.net.il",
    "netvision.net.il", "zahav.net.il", "protonmail.com", "proton.me", "aol.com", "msn.com",
}

AUTOMATED_LOCALPART = re.compile(
    r"(no-?reply|do-?not-?reply|notifications?|alerts?|mailer|news(letter)?|info|"
    r"support|updates?|marketing|hello|team|service|billing|accounts?|bounce)", re.I
)

DEFAULT_RULES: dict[str, dict[str, list[str]]] = {
    "receipts": {
        "keywords": [
            "receipt", "invoice", "order confirmation", "your order", "order #", "payment received",
            "payment confirmation", "purchase", "תודה על הזמנתך", "קבלה", "חשבונית", "אישור הזמנה",
            "אישור תשלום", "הזמנתך", "ההזמנה שלך", "תשלום התקבל", "אישור רכישה", "חשבון עסקה",
        ],
        "domains": ["paypal.com", "aliexpress.com", "amazon.com", "ebay.com", "apple.com",
                    "wolt.com", "10bis.co.il", "greeninvoice.co.il", "icount.co.il"],
    },
    "finance": {
        "keywords": [
            "bank", "statement", "credit card", "transaction", "transfer", "investment", "dividend",
            "tax", "pension", "insurance", "loan", "mortgage", "בנק", "דף חשבון", "כרטיס אשראי",
            "חיוב", "העברה", "השקעות", "מס הכנסה", "פנסיה", "ביטוח", "הלוואה", "משכנתא",
            "קרן השתלמות", "ביטוח לאומי", "תיק השקעות", "יתרה",
        ],
        "domains": ["bankhapoalim.co.il", "leumi.co.il", "discountbank.co.il", "mizrahi-tefahot.co.il",
                    "fibi.co.il", "isracard.co.il", "max.co.il", "cal-online.co.il", "americanexpress.com",
                    "btl.gov.il", "taxes.gov.il", "gov.il", "harel-group.co.il", "migdal.co.il",
                    "clalbit.co.il", "menoramivt.co.il", "phoenix.co.il", "altshul.co.il",
                    "meitav.co.il", "interactivebrokers.com", "revolut.com", "wise.com", "payboxapp.com"],
    },
    "travel": {
        "keywords": [
            "flight", "boarding pass", "booking confirmation", "itinerary", "reservation", "check-in",
            "טיסה", "כרטיס עלייה למטוס", "הזמנת מלון", "צ'ק אין",
        ],
        "domains": ["booking.com", "airbnb.com", "expedia.com", "elal.com", "elal.co.il",
                    "ryanair.com", "wizzair.com", "easyjet.com", "israir.co.il", "arkia.co.il",
                    "agoda.com", "hotels.com", "trip.com", "skyscanner.net"],
    },
    "social": {
        "keywords": [],
        "domains": ["facebook.com", "facebookmail.com", "linkedin.com", "instagram.com",
                    "twitter.com", "x.com", "tiktok.com", "pinterest.com", "reddit.com",
                    "redditmail.com", "youtube.com", "whatsapp.com", "meetup.com", "quora.com"],
    },
    "promotions": {
        "keywords": [
            "sale", "% off", "discount", "coupon", "deal", "limited time", "free shipping",
            "black friday", "cyber monday", "offer", "מבצע", "הנחה", "קופון", "מבצעים",
            "סייל", "משלוח חינם", "לזמן מוגבל", "בלעדי", "הטבה", "הטבות",
        ],
        "domains": [],
    },
}


@dataclass
class Config:
    my_addresses: set[str] = field(default_factory=set)
    family_addresses: set[str] = field(default_factory=set)
    family_names: list[str] = field(default_factory=list)
    friend_addresses: set[str] = field(default_factory=set)
    friends_from_sent: bool = True
    rules: dict[str, dict[str, list[str]]] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path | None) -> "Config":
        cfg = cls(rules={k: {kk: list(vv) for kk, vv in v.items()} for k, v in DEFAULT_RULES.items()})
        if not path or not path.exists():
            return cfg
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        low = lambda xs: {x.strip().lower() for x in xs}
        cfg.my_addresses = low(data.get("me", {}).get("addresses", []))
        fam = data.get("family", {})
        cfg.family_addresses = low(fam.get("addresses", []))
        cfg.family_names = [n.strip().lower() for n in fam.get("names", []) if n.strip()]
        fr = data.get("friends", {})
        cfg.friend_addresses = low(fr.get("addresses", []))
        cfg.friends_from_sent = fr.get("from_sent_mail", True)
        for cat, extra in data.get("rules", {}).items():
            if cat not in CATEGORIES:
                raise SystemExit(f"קטגוריה לא מוכרת בקובץ ההגדרות: {cat}")
            r = cfg.rules.setdefault(cat, {"keywords": [], "domains": []})
            r.setdefault("keywords", []).extend(extra.get("keywords", []))
            r.setdefault("domains", []).extend(extra.get("domains", []))
        return cfg


def _domain(addr: str) -> str:
    return addr.rsplit("@", 1)[-1] if "@" in addr else ""


def _domain_matches(domain: str, domains: list[str]) -> bool:
    return any(domain == d or domain.endswith("." + d) for d in domains)


def _has_keyword(text: str, keywords: list[str]) -> bool:
    return any(k.lower() in text for k in keywords)


class Classifier:
    def __init__(self, config: Config, contacted: set[str] | None = None):
        self.cfg = config
        self.contacted = (contacted or set()) - config.my_addresses

    def is_human_sender(self, m: Message) -> bool:
        local = m.sender.split("@", 1)[0]
        return (
            not m.list_unsubscribe
            and not AUTOMATED_LOCALPART.search(local)
            and "CATEGORY_PROMOTIONS" not in m.labels
        )

    def classify(self, m: Message) -> str:
        addr, dom = m.sender, _domain(m.sender)
        name = (m.sender_name or "").lower()
        subject = (m.subject or "").lower()
        text = f"{subject} {(m.snippet or '').lower()}"
        rules = self.cfg.rules
        labels = set(m.labels)

        # 0. Mail you sent yourself is not something to sort
        if "SENT" in labels or addr in self.cfg.my_addresses:
            return "other"

        # 1. People - explicit lists first
        if addr in self.cfg.family_addresses or (
            self.is_human_sender(m) and any(n in name or n in addr for n in self.cfg.family_names)
        ):
            return "family"
        if addr in self.cfg.friend_addresses:
            return "friends"
        if (self.cfg.friends_from_sent and addr in self.contacted
                and dom in PERSONAL_DOMAINS and self.is_human_sender(m)):
            return "friends"

        # 2. Transactional mail - subject is the strongest signal
        if _has_keyword(subject, rules["receipts"]["keywords"]):
            return "receipts"
        if _domain_matches(dom, rules["finance"]["domains"]):
            return "finance"
        if _domain_matches(dom, rules["travel"]["domains"]) or _has_keyword(subject, rules["travel"]["keywords"]):
            return "travel"
        if _domain_matches(dom, rules["receipts"]["domains"]) and _has_keyword(
            text, rules["receipts"]["keywords"]
        ):
            return "receipts"
        if _has_keyword(subject, rules["finance"]["keywords"]) and not m.list_unsubscribe:
            return "finance"

        # 3. Bulk mail
        if _domain_matches(dom, rules["social"]["domains"]) or "CATEGORY_SOCIAL" in labels:
            return "social"
        if ("CATEGORY_PROMOTIONS" in labels
                or _domain_matches(dom, rules["promotions"]["domains"])
                or (m.list_unsubscribe and _has_keyword(text, rules["promotions"]["keywords"]))):
            return "promotions"
        if m.list_unsubscribe or "CATEGORY_FORUMS" in labels:
            return "newsletters"
        if "CATEGORY_UPDATES" in labels or AUTOMATED_LOCALPART.search(addr.split("@", 1)[0]):
            return "notifications"

        # 4. Anything else that looks like a real person
        if self.is_human_sender(m):
            return "personal"
        return "other"
