"""
Log Generator — écrit des logs dans :
  1. Le répertoire spool de Flume  (→ HDFS via Flume)
  2. La table MySQL `events`        (→ métriques Flask/Grafana)
"""
import os
import random
import time
from datetime import datetime

import mysql.connector

MYSQL_HOST     = os.getenv("MYSQL_HOST",     "mysql")
MYSQL_USER     = os.getenv("MYSQL_USER",     "root")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "root")
MYSQL_DB       = os.getenv("MYSQL_DB",       "universite")
SPOOL_DIR      = os.getenv("SPOOL_DIR",      "/var/log/flume/spool")

# Pondération : 70 % INFO, 20 % WARN, 10 % ERROR
LEVELS = ["INFO"] * 70 + ["WARN"] * 20 + ["ERROR"] * 10

MESSAGES = {
    "INFO": [
        "User login: student_{n:03d}",
        "File uploaded to HDFS: partition_{n}.parquet",
        "MapReduce job completed in {n}ms — records={n2}",
        "DataNode heartbeat received from dn-{n:02d}",
        "Cache refreshed: {n} entries invalidated",
        "Query executed successfully in {n}ms",
        "Batch processed: {n} events flushed to HDFS",
    ],
    "WARN": [
        "High memory usage on datanode-{n}: {n2}%",
        "Slow HDFS write detected: {n}ms (threshold 500ms)",
        "DataNode dn-{n:02d} response delayed by {n2}ms",
        "Retry attempt {n}/3 for block replication",
        "Connection pool near capacity: {n}/{n2} used",
    ],
    "ERROR": [
        "Connection refused to datanode-{n}: timeout after {n2}s",
        "HDFS write failed for block blk_{n}: disk full",
        "NullPointerException in EventProcessor at line {n}",
        "Failed to flush {n} events to HDFS after 3 retries",
        "MySQL insert error: deadlock detected on table events",
    ],
}


def wait_for_mysql() -> mysql.connector.MySQLConnection:
    while True:
        try:
            conn = mysql.connector.connect(
                host=MYSQL_HOST, user=MYSQL_USER,
                password=MYSQL_PASSWORD, database=MYSQL_DB,
                connection_timeout=5,
            )
            print("[generator] MySQL ready.", flush=True)
            return conn
        except Exception as exc:
            print(f"[generator] Waiting for MySQL: {exc}", flush=True)
            time.sleep(3)


def reconnect() -> mysql.connector.MySQLConnection:
    while True:
        try:
            return mysql.connector.connect(
                host=MYSQL_HOST, user=MYSQL_USER,
                password=MYSQL_PASSWORD, database=MYSQL_DB,
            )
        except Exception:
            time.sleep(2)


def insert_event(conn, level: str, message: str):
    cur = conn.cursor()
    cur.execute("INSERT INTO events (level, message) VALUES (%s, %s)", (level, message))
    conn.commit()
    cur.close()


def build_message(level: str) -> str:
    tmpl = random.choice(MESSAGES[level])
    return tmpl.format(
        n=random.randint(1, 999),
        n2=random.randint(1, 999),
    )


def write_to_spool(lines: list[str]):
    os.makedirs(SPOOL_DIR, exist_ok=True)
    ts   = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    tmp  = os.path.join(SPOOL_DIR, f"{ts}.log.tmp")
    dest = os.path.join(SPOOL_DIR, f"{ts}.log")
    with open(tmp, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    os.rename(tmp, dest)


def main():
    conn        = wait_for_mysql()
    batch: list[str] = []
    batch_size  = random.randint(8, 25)

    print("[generator] Starting event loop…", flush=True)
    while True:
        level   = random.choice(LEVELS)
        message = build_message(level)
        ts      = datetime.now().isoformat(timespec="milliseconds")
        line    = f"{ts} [{level}] {message}"
        batch.append(line)

        # MySQL insert
        try:
            insert_event(conn, level, message)
        except Exception:
            conn = reconnect()
            try:
                insert_event(conn, level, message)
            except Exception:
                pass

        # Flush batch to spool dir
        if len(batch) >= batch_size:
            write_to_spool(batch)
            batch      = []
            batch_size = random.randint(8, 25)

        time.sleep(random.uniform(0.05, 0.15))


if __name__ == "__main__":
    main()
