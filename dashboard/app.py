"""
Flask Dashboard — expose les métriques Flume/HDFS/MySQL
pour le plugin Grafana Infinity (JSON/REST).
"""
import os
import threading
import time
from collections import deque
from datetime import datetime

import pymysql
import requests
from flask import Flask, jsonify

app = Flask(__name__)

# ── Config (surchargeable via variables d'env) ────────────────
MYSQL_CONFIG = dict(
    host     = os.getenv("MYSQL_HOST",     "mysql"),
    user     = os.getenv("MYSQL_USER",     "root"),
    password = os.getenv("MYSQL_PASSWORD", "root"),
    database = os.getenv("MYSQL_DB",       "universite"),
    charset  = "utf8mb4",
    cursorclass = pymysql.cursors.DictCursor,
)
HDFS_URL   = os.getenv("HDFS_URL", "http://namenode:9870")
START_TIME = time.time()

# ── État partagé (protégé par un verrou) ─────────────────────
_lock             = threading.Lock()
_timestamps       = deque(maxlen=300)   # Unix ms
_throughput       = deque(maxlen=300)   # events/poll
_total_events     = 0
_info_count       = 0
_warn_count       = 0
_error_count      = 0
_hdfs_files       = 0
_hdfs_size_mb     = 0.0
_prev_total       = 0


# ── Helpers MySQL ─────────────────────────────────────────────
def _get_conn():
    return pymysql.connect(**MYSQL_CONFIG)


def _mysql_metrics() -> dict:
    conn = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT level, COUNT(*) AS cnt FROM events GROUP BY level"
            )
            rows = cur.fetchall()
        result = {"INFO": 0, "WARN": 0, "ERROR": 0}
        for r in rows:
            lvl = r["level"].upper()
            if lvl in result:
                result[lvl] = r["cnt"]
        return result
    finally:
        conn.close()


# ── Helpers HDFS (WebHDFS REST API) ───────────────────────────
def _hdfs_stats() -> tuple[int, float]:
    today = datetime.now().strftime("%Y%m%d")
    url   = f"{HDFS_URL}/webhdfs/v1/flume/logs/{today}?op=GETCONTENTSUMMARY"
    try:
        resp = requests.get(url, timeout=3)
        if resp.status_code == 200:
            cs = resp.json().get("ContentSummary", {})
            return cs.get("fileCount", 0), round(cs.get("length", 0) / 1_048_576, 3)
    except Exception:
        pass
    return 0, 0.0


# ── Thread de polling (toutes les secondes) ───────────────────
def _poller():
    global _total_events, _info_count, _warn_count, _error_count
    global _hdfs_files, _hdfs_size_mb, _prev_total

    while True:
        # MySQL
        try:
            m = _mysql_metrics()
            new_total = m["INFO"] + m["WARN"] + m["ERROR"]
            delta     = max(0, new_total - _prev_total)
            with _lock:
                _info_count   = m["INFO"]
                _warn_count   = m["WARN"]
                _error_count  = m["ERROR"]
                _total_events = new_total
                _timestamps.append(int(time.time() * 1000))
                _throughput.append(delta)
                _prev_total = new_total
        except Exception:
            pass

        # HDFS
        try:
            files, size_mb = _hdfs_stats()
            with _lock:
                _hdfs_files   = files
                _hdfs_size_mb = size_mb
        except Exception:
            pass

        time.sleep(1)


threading.Thread(target=_poller, daemon=True).start()


# ── Endpoints REST ────────────────────────────────────────────

@app.route("/")
def index():
    return jsonify({"status": "ok", "service": "Hadoop Monitoring Dashboard"})


@app.route("/api/metrics")
def metrics():
    """
    Retourne un tableau à 1 élément pour le plugin Infinity (format table).
    Chaque champ est extrait par Grafana comme une colonne distincte.
    """
    elapsed = max(time.time() - START_TIME, 1)
    with _lock:
        return jsonify([{
            "total_events":  _total_events,
            "info_count":    _info_count,
            "warn_count":    _warn_count,
            "error_count":   _error_count,
            "events_per_sec": round(_total_events / elapsed, 2),
            "hdfs_files":    _hdfs_files,
            "hdfs_size_mb":  _hdfs_size_mb,
            "timestamp":     datetime.now().isoformat(),
        }])


@app.route("/api/throughput")
def throughput():
    """
    Série temporelle pour le panel Time Series.
    time  = Unix timestamp en millisecondes (Infinity type: timestamp_epoch_ms)
    value = nombre d'events depuis le dernier poll
    """
    with _lock:
        return jsonify([
            {"time": t, "value": v}
            for t, v in zip(_timestamps, _throughput)
        ])


@app.route("/api/log-distribution")
def log_distribution():
    """
    Une ligne, trois colonnes — idéal pour le Pie Chart Grafana.
    """
    with _lock:
        return jsonify([{
            "INFO":  _info_count,
            "WARN":  _warn_count,
            "ERROR": _error_count,
        }])


@app.route("/api/logs")
def recent_logs():
    """50 derniers events pour le panel Table / Log Stream."""
    try:
        conn = _get_conn()
        with conn.cursor() as cur:
            cur.execute(
                "SELECT created_at AS time, level, message "
                "FROM events ORDER BY id DESC LIMIT 50"
            )
            rows = cur.fetchall()
        conn.close()
        return jsonify([
            {
                "time":    r["time"].isoformat() if hasattr(r["time"], "isoformat")
                           else str(r["time"]),
                "level":   r["level"],
                "message": r["message"],
            }
            for r in rows
        ])
    except Exception:
        return jsonify([])


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, threaded=True)
