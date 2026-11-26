import time
from pathlib import Path

import pytest

from gmail_cleaner import cli, gmail
from gmail_cleaner.classifier import Classifier, Config
from gmail_cleaner.store import Message, Store

DAY = 86_400_000


def msg(sender, subject="", name="", labels=(), unsub="", snippet="", age_days=0, id=None):
    return Message(
        id=id or f"{sender}-{subject}", sender=sender, sender_name=name, subject=subject,
        snippet=snippet, labels=list(labels), list_unsubscribe=unsub,
        date_ms=int(time.time() * 1000) - age_days * DAY, size=1000,
    )


@pytest.fixture
def clf(tmp_path):
    cfgp = tmp_path / "config.toml"
    cfgp.write_text(
        '[me]\naddresses=["me@gmail.com"]\n'
        '[family]\naddresses=["mom@gmail.com"]\nnames=["כהן"]\n'
        '[friends]\naddresses=["buddy@yahoo.com"]\n'
        '[rules.promotions]\ndomains=["myshop.co.il"]\n',
        encoding="utf-8",
    )
    return Classifier(Config.load(cfgp), contacted={"dana@gmail.com", "me@gmail.com"})


@pytest.mark.parametrize("m,expected", [
    (msg("mom@gmail.com", "מה שלומך"), "family"),
    (msg("yossi@walla.co.il", "ארוחת שישי", name="יוסי כהן"), "family"),
    (msg("buddy@yahoo.com", "hey"), "friends"),
    (msg("dana@gmail.com", "נפגשים?"), "friends"),
    (msg("stranger@gmail.com", "שאלה"), "personal"),
    (msg("orders@shop.com", "Your receipt from Shop", unsub="<mailto:x>"), "receipts"),
    (msg("noreply@wolt.com", "קבלה עבור הזמנתך"), "receipts"),
    (msg("service@isracard.co.il", "פירוט חיובים לחודש"), "finance"),
    (msg("alerts@bank.example", "דף חשבון חודשי"), "finance"),
    (msg("noreply@booking.com", "Booking confirmation"), "travel"),
    (msg("notification@facebookmail.com", "You have a new friend"), "social"),
    (msg("deals@store.com", "50% off today only", unsub="<https://x>"), "promotions"),
    (msg("news@store.com", "Our story", labels=["CATEGORY_PROMOTIONS"]), "promotions"),
    (msg("hi@myshop.co.il", "חדש בחנות"), "promotions"),
    (msg("digest@substack.com", "Weekly thoughts", unsub="<https://x>"), "newsletters"),
    (msg("no-reply@github.com", "[repo] new issue"), "notifications"),
])
def test_classify(clf, m, expected):
    assert clf.classify(m) == expected


def test_newsletter_from_family_name_not_family(clf):
    # a mailing list that happens to contain the family name should not be "family"
    assert clf.classify(msg("news@cohen-shop.com", "מבצע", name="חנות כהן", unsub="<x>")) != "family"


# ------------------------------------------------------- fake Gmail service

class FakeReq:
    def __init__(self, fn):
        self.fn = fn

    def execute(self):
        return self.fn()


class FakeBatch:
    def __init__(self, cb):
        self.cb, self.items = cb, []

    def add(self, req, request_id):
        self.items.append((request_id, req))

    def execute(self):
        for rid, req in self.items:
            self.cb(rid, req.execute(), None)


class FakeGmail:
    def __init__(self, raws):
        self.raws = {r["id"]: r for r in raws}
        self.label_list = [{"name": "INBOX", "id": "INBOX"}]
        self.trashed = []

    # service.users().messages()/labels() chain
    def users(self): return self
    def labels(self): return FakeLabels(self)
    def messages(self): return self
    def new_batch_http_request(self, callback): return FakeBatch(callback)

    def list(self, userId, q="", maxResults=500, pageToken=None, labelIds=None):
        ids = [i for i, r in self.raws.items() if set(labelIds or []) <= set(r["labelIds"])]
        return FakeReq(lambda: {"messages": [{"id": i} for i in ids]})

    def get(self, userId, id, format, metadataHeaders):
        return FakeReq(lambda: self.raws[id])

    def trash(self, userId, id):
        def f():
            self.trashed.append(id)
            self.raws[id]["labelIds"].append("TRASH")
            return {}
        return FakeReq(f)

    def batchModify(self, userId, body):
        def f():
            for i in body["ids"]:
                l = self.raws[i]["labelIds"]
                l.extend(body["addLabelIds"])
                for r in body["removeLabelIds"]:
                    if r in l:
                        l.remove(r)
        return FakeReq(f)


class FakeLabels:
    def __init__(self, g): self.g = g
    def list(self, userId): return FakeReq(lambda: {"labels": self.g.label_list})

    def create(self, userId, body):
        def f():
            lab = {"name": body["name"], "id": f"L{len(self.g.label_list)}"}
            self.g.label_list.append(lab)
            return lab
        return FakeReq(f)


def raw(id, frm, subject, labels=("INBOX",), unsub=None, age_days=0, to=None):
    headers = [{"name": "From", "value": frm}, {"name": "Subject", "value": subject}]
    if unsub:
        headers.append({"name": "List-Unsubscribe", "value": unsub})
    if to:
        headers.append({"name": "To", "value": to})
    return {"id": id, "threadId": id, "snippet": "", "labelIds": list(labels),
            "internalDate": str(int(time.time() * 1000) - age_days * DAY), "sizeEstimate": 2048,
            "payload": {"headers": headers}}


@pytest.fixture
def env(tmp_path, monkeypatch):
    fake = FakeGmail([
        raw("1", "Mom <mom@gmail.com>", "ארוחת שישי"),
        raw("2", "Shop <deals@store.com>", "70% הנחה!", labels=("INBOX", "CATEGORY_PROMOTIONS"),
            unsub="<https://store.com/u>", age_days=90),
        raw("3", "Shop <deals@store.com>", "מבצע חדש", labels=("INBOX", "CATEGORY_PROMOTIONS", "STARRED"),
            unsub="<https://store.com/u>", age_days=90),
        raw("4", "Shop <deals@store.com>", "מבצע אתמול", labels=("INBOX", "CATEGORY_PROMOTIONS"),
            unsub="<https://store.com/u>", age_days=1),
        raw("5", "Wolt <noreply@wolt.com>", "קבלה עבור הזמנתך"),
        raw("6", "Me <me@gmail.com>", "re: hi", labels=("SENT",), to="Dana <dana@gmail.com>"),
        raw("7", "Dana <dana@gmail.com>", "hi"),
    ])
    monkeypatch.setattr(cli, "_service", lambda args: fake)
    (tmp_path / "config.toml").write_text('[family]\naddresses=["mom@gmail.com"]\n[me]\naddresses=["me@gmail.com"]\n')
    monkeypatch.chdir(tmp_path)
    return fake, tmp_path


def test_end_to_end(env, capsys):
    fake, tmp = env
    cli.main(["scan", "--csv", "out.csv"])
    cats = {m.id: m.category for m in Store(Path("gmail_cache.db")).all()}
    assert cats["1"] == "family"
    assert cats["2"] == "promotions"
    assert cats["5"] == "receipts"
    assert cats["7"] == "friends"  # learned from Sent mail
    assert "קבלות" in (tmp / "out.csv").read_text(encoding="utf-8-sig")

    # dry run changes nothing
    cli.main(["clean", "--category", "promotions", "--older-than", "30"])
    assert fake.trashed == []
    assert "מצב ניסיון" in capsys.readouterr().out

    # apply: only old, non-starred promo gets trashed
    cli.main(["clean", "--category", "promotions", "--older-than", "30", "--apply", "--yes"])
    assert fake.trashed == ["2"]

    # protected categories need --force
    with pytest.raises(SystemExit):
        cli.main(["clean", "--category", "family", "--apply", "--yes"])

    cli.main(["label", "--apply"])
    names = {l["name"] for l in fake.label_list}
    assert "ניקוי/משפחה" in names and "ניקוי/קבלות" in names
    assert any(l.startswith("L") for l in fake.raws["5"]["labelIds"])


def test_clean_requires_filter(env):
    with pytest.raises(SystemExit):
        cli.main(["clean", "--apply", "--yes"])


def test_own_sent_mail_is_other(clf):
    assert clf.classify(msg("me@gmail.com", "re: hi", labels=["SENT"])) == "other"
