"""Local SQLite cache of message metadata (never message bodies)."""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    thread_id TEXT,
    sender TEXT,
    sender_name TEXT,
    subject TEXT,
    snippet TEXT,
    date_ms INTEGER,
    labels TEXT,
    list_unsubscribe TEXT,
    size INTEGER,
    category TEXT
);
CREATE TABLE IF NOT EXISTS contacted (
    address TEXT PRIMARY KEY
);
"""


@dataclass
class Message:
    id: str
    thread_id: str = ""
    sender: str = ""
    sender_name: str = ""
    subject: str = ""
    snippet: str = ""
    date_ms: int = 0
    labels: list[str] = field(default_factory=list)
    list_unsubscribe: str = ""
    size: int = 0
    category: str | None = None


class Store:
    def __init__(self, path: Path):
        self.conn = sqlite3.connect(path)
        self.conn.executescript(SCHEMA)

    def upsert(self, msgs: list[Message]) -> None:
        self.conn.executemany(
            "INSERT OR REPLACE INTO messages VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            [
                (m.id, m.thread_id, m.sender, m.sender_name, m.subject, m.snippet,
                 m.date_ms, ",".join(m.labels), m.list_unsubscribe, m.size, m.category)
                for m in msgs
            ],
        )
        self.conn.commit()

    def known_ids(self) -> set[str]:
        return {r[0] for r in self.conn.execute("SELECT id FROM messages")}

    def all(self) -> list[Message]:
        rows = self.conn.execute(
            "SELECT id, thread_id, sender, sender_name, subject, snippet, date_ms, labels,"
            " list_unsubscribe, size, category FROM messages"
        )
        return [
            Message(r[0], r[1], r[2], r[3], r[4], r[5], r[6],
                    [l for l in r[7].split(",") if l], r[8], r[9], r[10])
            for r in rows
        ]

    def set_categories(self, pairs: list[tuple[str, str]]) -> None:
        self.conn.executemany("UPDATE messages SET category=? WHERE id=?",
                              [(c, i) for i, c in pairs])
        self.conn.commit()

    def remove(self, ids: list[str]) -> None:
        self.conn.executemany("DELETE FROM messages WHERE id=?", [(i,) for i in ids])
        self.conn.commit()

    def add_contacted(self, addresses: set[str]) -> None:
        self.conn.executemany("INSERT OR IGNORE INTO contacted VALUES (?)",
                              [(a,) for a in addresses])
        self.conn.commit()

    def contacted(self) -> set[str]:
        return {r[0] for r in self.conn.execute("SELECT address FROM contacted")}
