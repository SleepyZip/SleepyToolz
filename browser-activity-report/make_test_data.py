#!/usr/bin/env python3
"""Build fake Chrome History DBs matching the real filename pattern, for testing."""
import os
import random
import sqlite3
from datetime import datetime, timedelta, timezone

CHROME_EPOCH = datetime(1601, 1, 1, tzinfo=timezone.utc)


def to_chrome(dt):
    return int((dt - CHROME_EPOCH).total_seconds() * 1_000_000)


SITES = [
    ("https://mail.example.com/inbox", "Inbox - Work Mail", 0),
    ("https://intranet.example.com/home", "Company Intranet", 0),
    ("https://portal.example.com/dashboard", "Vendor Portal", 0),
    ("https://outlook.office.com/mail/", "Mail - Outlook", 0),
    ("https://www.facebook.com/", "Facebook", 0),
    ("https://www.facebook.com/marketplace/", "Marketplace", 0),
    ("https://www.indeed.com/jobs?q=medical+receptionist", "receptionist jobs", 1),
    ("https://www.linkedin.com/jobs/search/", "Jobs | LinkedIn", 0),
    ("https://www.linkedin.com/feed/", "Feed | LinkedIn", 0),
    ("https://www.amazon.com/dp/B08N5W", "Amazon.com", 0),
    ("https://www.youtube.com/watch?v=abc", "Some Video", 0),
    ("https://mail.google.com/mail/u/0/", "Inbox - Gmail", 0),
    ("https://chatgpt.com/c/1234", "ChatGPT", 0),
    ("https://www.weather.gov/", "Local Forecast", 0),
    ("https://securepubads.g.doubleclick.net/x", "", 3),
    ("https://www.google.com/search?q=how+to+write+a+cover+letter", "cover letter", 5),
    ("https://www.chase.com/login", "Online Banking", 0),
    ("https://www.some-unmapped-site.example/page", "Unmapped Site", 0),
]

FILES = [
    "ChromeHistory_alex.taylorPC01",
    "ChromeHistory_alex.taylorPC02",
    "ChromeHistory_Alex.taylorPC02b",
    "ChromeHistory_sam.riveraPC02",
    "ChromeHistory_sam.riveraPC03",
]

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample")
os.makedirs(out, exist_ok=True)
random.seed(7)

for fname in FILES:
    path = os.path.join(out, fname)
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    cur = con.cursor()
    cur.executescript("""
        CREATE TABLE urls(id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
            visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0,
            last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0);
        CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0,
            segment_id INTEGER, visit_duration INTEGER DEFAULT 0);
        CREATE TABLE keyword_search_terms(keyword_id INTEGER NOT NULL,
            url_id INTEGER NOT NULL, term LONGVARCHAR NOT NULL);
        CREATE TABLE downloads(id INTEGER PRIMARY KEY, current_path LONGVARCHAR,
            target_path LONGVARCHAR, start_time INTEGER, received_bytes INTEGER,
            total_bytes INTEGER, tab_url LONGVARCHAR, mime_type VARCHAR(255));
    """)

    base = datetime(2026, 8, 18, 7, 45, tzinfo=timezone.utc)
    vid = 1
    for uid, (url, title, trans) in enumerate(SITES, start=1):
        cur.execute("INSERT INTO urls VALUES (?,?,?,?,?,?,0)",
                    (uid, url, title, 3, 1, to_chrome(base)))
        for _ in range(random.randint(1, 6)):
            t = base + timedelta(days=random.randint(0, 5),
                                 hours=random.randint(0, 11),
                                 minutes=random.randint(0, 59))
            cur.execute("INSERT INTO visits VALUES (?,?,?,NULL,?,NULL,?)",
                        (vid, uid, to_chrome(t), trans,
                         random.randint(2, 400) * 1_000_000))
            vid += 1
        if "search?q=" in url or "indeed" in url:
            cur.execute("INSERT INTO keyword_search_terms VALUES (1,?,?)", (uid, title))

    cur.execute("INSERT INTO downloads VALUES (1,?,?,?,?,?,?,?)",
                (r"C:\Users\x\Downloads\schedule.pdf", r"C:\Users\x\Downloads\schedule.pdf",
                 to_chrome(base + timedelta(days=1)), 248000, 248000,
                 "https://portal.example.com/reports", "application/pdf"))
    con.commit()
    con.close()
    print("wrote", fname)
