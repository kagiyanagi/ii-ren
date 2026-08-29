#!/usr/bin/env python3
"""LocalSend protocol v2, stdlib only.

Replaces the abandoned `localsend-cli` pip package. Speaks the same
newline-delimited JSON event stream on stdout and takes y/n on stdin, so
LocalSend.qml only had to change the commands it spawns, not its shape.

    receive --output DIR    serve, stream events, prompt for each transfer
    send IP[:PORT] FILE...  push files to a peer
    check                   exit 0 if this helper can run at all

The whole protocol is a multicast announce plus five HTTP endpoints; see
https://github.com/localsend/protocol.
"""

import argparse
import json
import mimetypes
import os
import socket
import ssl
import struct
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs
from urllib.request import Request, urlopen

MULTICAST = "224.0.0.167"
PORT = 53317
CHUNK = 256 * 1024
# Long enough for a human to walk back to the machine, short enough that a
# forgotten prompt does not pin the sender open forever.
PROMPT_TIMEOUT = 120

INFO = {
    "alias": socket.gethostname(),
    "version": "2.1",
    "deviceModel": "Linux",
    "deviceType": "desktop",
    "fingerprint": uuid.uuid4().hex,
    "port": PORT,
    # ponytail: plain HTTP. Peers honour this field and skip TLS; switch to a
    # self-signed ssl.SSLContext here if a peer ever refuses to downgrade.
    "protocol": "http",
    "download": False,
}

_out = threading.Lock()


def emit(**event):
    with _out:
        sys.stdout.write(json.dumps(event) + "\n")
        sys.stdout.flush()


# ---------------------------------------------------------------- receiving

sessions = {}
prompt_lock = threading.Lock()
prompt_answer = threading.Event()
prompt_accepted = False
outdir = "."


def ask():
    """Emit the prompt and block until the shell writes y/n on stdin."""
    global prompt_accepted
    if not prompt_lock.acquire(blocking=False):
        return False  # one transfer at a time, same as the UI
    try:
        prompt_accepted = False
        prompt_answer.clear()
        emit(event="prompt")
        prompt_answer.wait(PROMPT_TIMEOUT)
        return prompt_accepted
    finally:
        prompt_lock.release()


def stdin_loop():
    global prompt_accepted
    for line in sys.stdin:
        prompt_accepted = line.strip().lower().startswith("y")
        prompt_answer.set()
    prompt_answer.set()


def safe_dest(name):
    """Land the file inside outdir no matter what the sender called it."""
    name = os.path.basename(name or "").strip() or "file"
    if name in (".", ".."):
        name = "file"
    path = os.path.join(outdir, name)
    stem, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(path):
        path = f"{stem} ({n}){ext}"
        n += 1
    return path


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, code, obj=None):
        body = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def do_GET(self):
        self.reply(200, INFO) if "/info" in self.path else self.reply(404)

    def do_POST(self):
        path, _, query = self.path.partition("?")
        q = {k: v[0] for k, v in parse_qs(query).items()}
        if path.endswith("/register"):
            self.on_register()
        elif path.endswith("/prepare-upload"):
            self.on_prepare()
        elif path.endswith("/upload"):
            self.on_upload(q)
        elif path.endswith("/cancel"):
            sessions.pop(q.get("sessionId", ""), None)
            emit(event="cancelled")
            self.reply(200)
        else:
            self.reply(404)

    def on_register(self):
        try:
            peer = json.loads(self.body() or b"{}")
        except ValueError:
            return self.reply(400)
        seen(peer, self.client_address[0])
        self.reply(200, INFO)

    def on_prepare(self):
        try:
            req = json.loads(self.body() or b"{}")
        except ValueError:
            return self.reply(400)
        info = req.get("info") or {}
        files = req.get("files") or {}
        if not files:
            return self.reply(400)
        sender = info.get("alias") or "Unknown"
        emit(
            event="incoming",
            sender=sender,
            ip=self.client_address[0],
            files=[
                {"name": f.get("fileName", "file"), "size": f.get("size", 0)}
                for f in files.values()
            ],
            is_text=any(f.get("fileType") == "text" for f in files.values()),
        )
        if not ask():
            emit(event="cancelled")
            return self.reply(403)
        sid = uuid.uuid4().hex
        tokens = {fid: uuid.uuid4().hex for fid in files}
        sessions[sid] = {
            "files": files,
            "byToken": {t: fid for fid, t in tokens.items()},
            "sender": sender,
        }
        self.reply(200, {"sessionId": sid, "files": tokens})

    def on_upload(self, q):
        session = sessions.get(q.get("sessionId", ""))
        fid = q.get("fileId", "")
        if not session or session["byToken"].get(q.get("token", "")) != fid:
            return self.reply(403)
        meta = session["files"].get(fid) or {}
        size = int(self.headers.get("Content-Length") or 0)
        if meta.get("fileType") == "text":
            emit(
                event="text",
                sender=session["sender"],
                text=self.rfile.read(size).decode("utf-8", "replace"),
            )
            return self.reply(200)
        dest = safe_dest(meta.get("fileName"))
        left = size
        with open(dest, "wb") as fh:
            while left > 0:
                buf = self.rfile.read(min(CHUNK, left))
                if not buf:
                    break
                fh.write(buf)
                left -= len(buf)
        emit(
            event="saved",
            sender=session["sender"],
            name=os.path.basename(dest),
            path=dest,
            size=size,
        )
        self.reply(200)


# ---------------------------------------------------------------- discovery

known = set()


def seen(peer, ip):
    fp = peer.get("fingerprint")
    if not fp or fp == INFO["fingerprint"] or fp in known:
        return
    known.add(fp)
    emit(
        event="device",
        alias=peer.get("alias") or "Unknown",
        ip=ip,
        port=peer.get("port") or PORT,
    )


def discovery():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except OSError:
        pass
    sock.bind(("", PORT))
    sock.setsockopt(
        socket.IPPROTO_IP,
        socket.IP_ADD_MEMBERSHIP,
        struct.pack("4sl", socket.inet_aton(MULTICAST), socket.INADDR_ANY),
    )

    def announce():
        msg = json.dumps({**INFO, "announce": True}).encode()
        while True:
            try:
                sock.sendto(msg, (MULTICAST, PORT))
            except OSError as exc:
                emit(error=f"announce failed: {exc}")
            time.sleep(10)

    threading.Thread(target=announce, daemon=True).start()
    reply = json.dumps({**INFO, "announce": False}).encode()
    while True:
        try:
            data, addr = sock.recvfrom(65535)
            peer = json.loads(data)
        except (OSError, ValueError):
            continue
        if peer.get("fingerprint") == INFO["fingerprint"]:
            continue
        seen(peer, addr[0])
        if peer.get("announce"):
            sock.sendto(reply, addr)


def receive(args):
    global outdir
    outdir = os.path.expanduser(args.output)
    os.makedirs(outdir, exist_ok=True)
    try:
        server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    except OSError as exc:
        emit(error=f"cannot bind port {PORT} (is the LocalSend app running?): {exc}")
        return 1
    threading.Thread(target=stdin_loop, daemon=True).start()
    threading.Thread(target=discovery, daemon=True).start()
    emit(event="ready", alias=INFO["alias"], port=PORT)
    server.serve_forever()
    return 0


# ---------------------------------------------------------------- sending

LAX = ssl._create_unverified_context()


def post(url, obj=None, data=None, length=None):
    headers = {"Content-Type": "application/json" if obj is not None else
               "application/octet-stream"}
    if length is not None:
        headers["Content-Length"] = str(length)
    body = json.dumps(obj).encode() if obj is not None else data
    return urlopen(Request(url, data=body, headers=headers, method="POST"),
                   timeout=30, context=LAX)


def send(args):
    host, _, port = args.target.partition(":")
    port = port or PORT
    files = {}
    for i, path in enumerate(args.files):
        fid = str(i)
        files[fid] = {
            "id": fid,
            "fileName": os.path.basename(path),
            "size": os.path.getsize(path),
            "fileType": mimetypes.guess_type(path)[0] or "application/octet-stream",
        }

    # Peers default to TLS with a self-signed cert; fall back for http-only ones.
    prepared = base = last = None
    for scheme in ("https", "http"):
        url = f"{scheme}://{host}:{port}/api/localsend/v2"
        try:
            with post(f"{url}/prepare-upload", {"info": INFO, "files": files}) as r:
                if r.status == 204:
                    emit(error="declined by receiver")
                    return 1
                prepared = json.loads(r.read() or b"{}")
            base = url
            break
        except HTTPError as exc:
            if exc.code in (403, 204):
                emit(error="declined by receiver")
                return 1
            last = exc
        except URLError as exc:
            last = exc
        except OSError as exc:
            last = exc
    if prepared is None:
        emit(error=f"cannot reach {host}:{port}: {last}")
        return 1

    sid = prepared.get("sessionId", "")
    tokens = prepared.get("files") or {}
    for fid, meta in files.items():
        token = tokens.get(fid)
        if not token:
            continue  # receiver declined this one
        try:
            with open(args.files[int(fid)], "rb") as fh:
                post(f"{base}/upload?sessionId={sid}&fileId={fid}&token={token}",
                     data=fh, length=meta["size"]).close()
        except (OSError, URLError) as exc:
            emit(error=f"{meta['fileName']}: {exc}")
            return 1
        emit(event="progress", name=meta["fileName"])
    emit(event="completed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("receive")
    r.add_argument("--output", default=".")
    r.set_defaults(func=receive)
    s = sub.add_parser("send")
    s.add_argument("target")
    s.add_argument("files", nargs="+")
    s.set_defaults(func=send)
    c = sub.add_parser("check")
    c.set_defaults(func=lambda a: 0)
    args = parser.parse_args()
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
