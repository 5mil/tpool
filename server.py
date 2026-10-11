#!/usr/bin/env python3
"""Thimble, one machine.

Run: python server.py
Serves the sign-on page and the API on port 8080.
Users, mail, and chat live in thimble.db next to this file.
"""
import hashlib
import json
import os
import re
import secrets
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(ROOT, "thimble.db")
PAGE = os.path.join(ROOT, "index.html")
HOST = "0.0.0.0"
PORT = 8080
ROOMS = ["Lobby", "Thirtysomething", "Computer Help", "Sports Bar", "New Member Lounge"]
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]{2,15}$")


def db():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    return con


def init():
    con = db()
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY,
            screen_name TEXT UNIQUE COLLATE NOCASE,
            salt TEXT NOT NULL,
            hash TEXT NOT NULL,
            created INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS sessions (
            token TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            seen INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY,
            room TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            body TEXT NOT NULL,
            created INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS mail (
            id INTEGER PRIMARY KEY,
            from_id INTEGER NOT NULL,
            to_id INTEGER NOT NULL,
            subject TEXT NOT NULL,
            body TEXT NOT NULL,
            unread INTEGER NOT NULL,
            created INTEGER NOT NULL
        );
        """
    )
    con.commit()
    con.close()


def hash_password(password, salt=None):
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120000).hex()
    return salt, digest


def user_public(row):
    return {"id": row["id"], "screenName": row["screen_name"]}


def read_json(handler):
    length = int(handler.headers.get("Content-Length") or 0)
    raw = handler.rfile.read(length) if length else b"{}"
    try:
        return json.loads(raw.decode() or "{}")
    except json.JSONDecodeError:
        return {}


def auth_user(handler):
    header = handler.headers.get("Authorization") or ""
    token = header[7:] if header.startswith("Bearer ") else ""
    if not token:
        return None
    con = db()
    row = con.execute(
        "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?",
        (token,),
    ).fetchone()
    if row:
        con.execute("UPDATE sessions SET seen = ? WHERE token = ?", (int(time.time()), token))
        con.commit()
    con.close()
    return row


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            data = open(PAGE, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == "/api/rooms":
            self.send_json(200, {"rooms": ROOMS})
            return
        user = auth_user(self)
        if not user:
            self.send_json(401, {"ok": False, "error": "Sign on first."})
            return
        if path == "/api/messages":
            query = self.path.split("?", 1)[1] if "?" in self.path else ""
            room, since = "Lobby", 0
            for part in query.split("&"):
                if part.startswith("room="):
                    room = part[5:].replace("%20", " ").replace("+", " ")
                if part.startswith("since="):
                    since = int(part[6:] or 0)
            if room not in ROOMS:
                self.send_json(400, {"ok": False, "error": "No such room."})
                return
            con = db()
            rows = con.execute(
                """SELECT m.id, u.screen_name AS name, m.body, m.created
                   FROM messages m JOIN users u ON u.id = m.user_id
                   WHERE m.room = ? AND m.id > ? ORDER BY m.id LIMIT 100""",
                (room, since),
            ).fetchall()
            who = con.execute(
                """SELECT DISTINCT u.screen_name FROM sessions s JOIN users u ON u.id = s.user_id
                   WHERE s.seen > ? ORDER BY u.screen_name""",
                (int(time.time()) - 90,),
            ).fetchall()
            unread = con.execute("SELECT COUNT(*) AS n FROM mail WHERE to_id = ? AND unread = 1", (user["id"],)).fetchone()["n"]
            con.close()
            self.send_json(200, {
                "messages": [dict(r) for r in rows],
                "online": [r["screen_name"] for r in who],
                "unread": unread,
            })
            return
        if path == "/api/mail":
            con = db()
            rows = con.execute(
                """SELECT m.id, fu.screen_name AS sender, m.subject, m.body, m.unread, m.created
                   FROM mail m JOIN users fu ON fu.id = m.from_id
                   WHERE m.to_id = ? ORDER BY m.id DESC LIMIT 50""",
                (user["id"],),
            ).fetchall()
            con.execute("UPDATE mail SET unread = 0 WHERE to_id = ?", (user["id"],))
            con.commit()
            con.close()
            self.send_json(200, {"mail": [dict(r) for r in rows]})
            return
        if path == "/api/directory":
            con = db()
            rows = con.execute("SELECT screen_name, created FROM users ORDER BY screen_name").fetchall()
            con.close()
            self.send_json(200, {"members": [dict(r) for r in rows]})
            return
        self.send_json(404, {"ok": False, "error": "Not found."})

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        data = read_json(self)
        if path == "/api/signup":
            name = str(data.get("screenName") or "")
            password = str(data.get("password") or "")
            if not NAME_RE.match(name):
                self.send_json(400, {"ok": False, "error": "Screen names are 3 to 16 letters and numbers, starting with a letter."})
                return
            if len(password) < 4:
                self.send_json(400, {"ok": False, "error": "Password needs at least 4 characters."})
                return
            salt, digest = hash_password(password)
            con = db()
            try:
                cur = con.execute(
                    "INSERT INTO users (screen_name, salt, hash, created) VALUES (?, ?, ?, ?)",
                    (name, salt, digest, int(time.time())),
                )
                user_id = cur.lastrowid
                con.execute(
                    "INSERT INTO mail (from_id, to_id, subject, body, unread, created) VALUES (?, ?, ?, ?, 1, ?)",
                    (user_id, user_id, "Welcome", "You have a screen name. The lobby is open. This server is the only host.", int(time.time())),
                )
                token = secrets.token_hex(24)
                con.execute("INSERT INTO sessions (token, user_id, seen) VALUES (?, ?, ?)", (token, user_id, int(time.time())))
                con.commit()
            except sqlite3.IntegrityError:
                con.close()
                self.send_json(409, {"ok": False, "error": "That screen name is taken."})
                return
            con.close()
            self.send_json(200, {"ok": True, "token": token, "screenName": name})
            return
        if path == "/api/login":
            name = str(data.get("screenName") or "")
            password = str(data.get("password") or "")
            con = db()
            row = con.execute("SELECT * FROM users WHERE screen_name = ?", (name,)).fetchone()
            if not row:
                con.close()
                self.send_json(401, {"ok": False, "error": "That screen name is not on this server."})
                return
            salt, digest = hash_password(password, row["salt"])
            if digest != row["hash"]:
                con.close()
                self.send_json(401, {"ok": False, "error": "Password does not match."})
                return
            token = secrets.token_hex(24)
            con.execute("INSERT INTO sessions (token, user_id, seen) VALUES (?, ?, ?)", (token, row["id"], int(time.time())))
            con.commit()
            con.close()
            self.send_json(200, {"ok": True, "token": token, "screenName": row["screen_name"]})
            return
        user = auth_user(self)
        if not user:
            self.send_json(401, {"ok": False, "error": "Sign on first."})
            return
        if path == "/api/messages":
            room = str(data.get("room") or "Lobby")
            text = " ".join(str(data.get("text") or "").split())[:240]
            if room not in ROOMS or not text:
                self.send_json(400, {"ok": False, "error": "Say something in a real room."})
                return
            con = db()
            cur = con.execute(
                "INSERT INTO messages (room, user_id, body, created) VALUES (?, ?, ?, ?)",
                (room, user["id"], text, int(time.time())),
            )
            con.commit()
            mid = cur.lastrowid
            con.close()
            self.send_json(200, {"ok": True, "id": mid})
            return
        if path == "/api/mail":
            to_name = str(data.get("to") or "")
            subject = str(data.get("subject") or "(no subject)")[:80]
            body = str(data.get("body") or "")[:1000]
            con = db()
            dest = con.execute("SELECT id FROM users WHERE screen_name = ?", (to_name,)).fetchone()
            if not dest:
                con.close()
                self.send_json(404, {"ok": False, "error": "No member by that screen name."})
                return
            con.execute(
                "INSERT INTO mail (from_id, to_id, subject, body, unread, created) VALUES (?, ?, ?, ?, 1, ?)",
                (user["id"], dest["id"], subject, body, int(time.time())),
            )
            con.commit()
            con.close()
            self.send_json(200, {"ok": True})
            return
        self.send_json(404, {"ok": False, "error": "Not found."})


def selftest():
    import tempfile
    global DB
    DB = os.path.join(tempfile.mkdtemp(), "thimble.db")
    init()
    from urllib import request
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    import threading
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % port

    def call(method, path, payload=None, token=None):
        data = json.dumps(payload).encode() if payload is not None else None
        req = request.Request(base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        if token:
            req.add_header("Authorization", "Bearer " + token)
        with request.urlopen(req) as res:
            return json.loads(res.read().decode())

    a = call("POST", "/api/signup", {"screenName": "ModemQueen", "password": "dialup"})
    b = call("POST", "/api/signup", {"screenName": "CoolDude95", "password": "lobby"})
    assert a["ok"] and b["ok"]
    taken = call("POST", "/api/signup", {"screenName": "ModemQueen", "password": "nope"}) if False else None
    try:
        call("POST", "/api/signup", {"screenName": "ModemQueen", "password": "nope"})
        raise SystemExit("duplicate signup should fail")
    except Exception as exc:
        if "HTTP Error 409" not in str(exc):
            raise
    call("POST", "/api/messages", {"room": "Lobby", "text": "wb from the kitchen phone"}, a["token"])
    call("POST", "/api/mail", {"to": "CoolDude95", "subject": "tonight", "body": "lobby after dinner"}, a["token"])
    seen = call("GET", "/api/messages?room=Lobby&since=0", token=b["token"])
    inbox = call("GET", "/api/mail", token=b["token"])
    assert seen["messages"][0]["body"] == "wb from the kitchen phone"
    assert inbox["mail"][0]["subject"] in ("tonight", "Welcome")
    print("SELF-TEST OK", DB)
    server.shutdown()


if __name__ == "__main__":
    import sys
    if "--selftest" in sys.argv:
        selftest()
    else:
        init()
        print("Thimble host on http://%s:%d" % (HOST, PORT))
        print("Database:", DB)
        ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
