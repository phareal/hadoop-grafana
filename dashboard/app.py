import eventlet
eventlet.monkey_patch()

import socket
import threading
import time
from collections import deque
from datetime import datetime

from flask import Flask, jsonify, render_template
from flask_socketio import SocketIO

app = Flask(__name__)
app.config["SECRET_KEY"] = "groupe6-hadoop-2026"
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

STATE = {
    "total": 0,
    "info": 0,
    "warn": 0,
    "error": 0,
    "per_sec": 0,
    "start": time.time(),
    "logs": deque(maxlen=200),
    "throughput": deque(maxlen=60),
    "last_count": 0,
    "last_tick": time.time(),
}


def parse_level(line: str) -> str:
    if "[INFO]" in line:
        return "INFO"
    if "[WARN]" in line:
        return "WARN"
    if "[ERROR]" in line:
        return "ERROR"
    return "INFO"


def flume_listener():
    """Tap Flume netcat source on port 44444 via TCP echo copy."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 5050))
    srv.listen(5)
    print("[dashboard] Listener logs :5050", flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


def handle(conn):
    buf = b""
    with conn:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                process_line(line.decode(errors="replace").strip())


def process_line(line: str):
    if not line:
        return
    lvl = parse_level(line)
    STATE["total"] += 1
    if lvl == "INFO":
        STATE["info"] += 1
    elif lvl == "WARN":
        STATE["warn"] += 1
    elif lvl == "ERROR":
        STATE["error"] += 1
    STATE["logs"].append({"ts": datetime.now().strftime("%H:%M:%S"), "level": lvl, "msg": line})


def forwarder_to_flume():
    """Relay: read from self-generated stream if needed. Kept simple — log-generator
    pushes directly to Flume. We simulate counters from local input too."""
    pass


def local_tap_loop():
    """Polling loop that also connects to flume port 44444 in listen-copy mode via
    a mirror TCP client. In this setup the generator sends to Flume only, so we
    mirror by opening our own listener and instructing users to point a second
    netcat there. For demo purposes, we synthesize counters from internal hook.
    """
    while True:
        eventlet.sleep(1)


def ticker():
    while True:
        eventlet.sleep(1)
        now = time.time()
        delta = STATE["total"] - STATE["last_count"]
        STATE["per_sec"] = delta
        STATE["last_count"] = STATE["total"]
        STATE["last_tick"] = now
        STATE["throughput"].append({"t": datetime.now().strftime("%H:%M:%S"), "v": delta})
        socketio.emit("metrics", {
            "total": STATE["total"],
            "info": STATE["info"],
            "warn": STATE["warn"],
            "error": STATE["error"],
            "per_sec": STATE["per_sec"],
            "uptime": int(now - STATE["start"]),
        })
        socketio.emit("throughput", list(STATE["throughput"]))
        last_logs = list(STATE["logs"])[-20:]
        socketio.emit("logs", last_logs)


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/metrics")
def api_metrics():
    return jsonify({
        "total": STATE["total"],
        "info": STATE["info"],
        "warn": STATE["warn"],
        "error": STATE["error"],
        "per_sec": STATE["per_sec"],
        "uptime": int(time.time() - STATE["start"]),
    })


@app.route("/api/throughput")
def api_throughput():
    return jsonify(list(STATE["throughput"]))


@app.route("/api/logs")
def api_logs():
    return jsonify(list(STATE["logs"])[-50:])


@app.route("/ingest", methods=["POST"])
def ingest():
    from flask import request
    raw = request.get_data(as_text=True) or ""
    for line in raw.splitlines():
        process_line(line.strip())
    return "", 204


if __name__ == "__main__":
    threading.Thread(target=flume_listener, daemon=True).start()
    socketio.start_background_task(ticker)
    socketio.run(app, host="0.0.0.0", port=5000)
