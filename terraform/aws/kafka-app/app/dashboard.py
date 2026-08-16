"""Dashboard: the live view of whether the pipeline is moving.

Serves one auto-refreshing page on :8080 with the consumer's message count and a
badge describing the pipeline's current condition. The badge is derived here, not
reported by the consumer: the consumer writes only raw facts (a heartbeat, a
count, a state, an optional error) and this module turns them into one of three
conditions, each of which reads distinctly enough to tell apart from across a room:

  * heartbeat older than STALE_AFTER_S     -> the consumer process is not reporting
  * consumer reported an error             -> its connection to Kafka is failing
  * connected, no error, no message for
    STALL_AFTER_S                          -> nothing is arriving
"""

import time

from flask import Flask
from flask import Response

import common

app = Flask(__name__)

# If the consumer is alive it rewrites the status file every ~2s. A staler file
# than this means the consumer process itself is down.
STALE_AFTER_S = 8
# A healthy pipeline sees a message every few seconds; a longer gap while
# "connected" with no error means traffic has stopped without anything erroring.
STALL_AFTER_S = 12

PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="2">
  <title>Kafka Demo — live</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{ margin:0; font-family:-apple-system,Segoe UI,Roboto,sans-serif;
            background:#0b1020; color:#e6ebff; display:flex; min-height:100vh;
            align-items:center; justify-content:center; }}
    .card {{ background:#141a30; border:1px solid #26304f; border-radius:18px;
             padding:44px 56px; width:560px; box-shadow:0 20px 60px rgba(0,0,0,.45); }}
    h1 {{ margin:0 0 4px; font-size:15px; letter-spacing:.14em; text-transform:uppercase;
          color:#8ea0d0; font-weight:600; }}
    .count {{ font-size:96px; font-weight:800; line-height:1; margin:14px 0 6px;
              font-variant-numeric:tabular-nums; }}
    .sub {{ color:#8ea0d0; font-size:14px; margin-bottom:26px; }}
    .badge {{ display:inline-flex; align-items:center; gap:9px; padding:9px 16px;
              border-radius:999px; font-weight:700; font-size:15px; }}
    .dot {{ width:11px; height:11px; border-radius:50%; }}
    .ok  {{ background:rgba(46,204,113,.14); color:#5ff0a8; }}
    .ok .dot {{ background:#5ff0a8; box-shadow:0 0 10px #5ff0a8; }}
    .bad {{ background:rgba(231,76,60,.15); color:#ff8a80; }}
    .bad .dot {{ background:#ff6b5a; box-shadow:0 0 10px #ff6b5a; }}
    .warn {{ background:rgba(241,196,15,.14); color:#ffe08a; }}
    .warn .dot {{ background:#ffd54a; box-shadow:0 0 10px #ffd54a; }}
    .reason {{ margin-top:14px; font-size:14px; color:#c3cdf0; }}
    table {{ width:100%; margin-top:22px; border-collapse:collapse; font-size:14px; }}
    td {{ padding:9px 0; border-top:1px solid #232c49; }}
    td:first-child {{ color:#8ea0d0; }}
    td:last-child {{ text-align:right; font-variant-numeric:tabular-nums;
                     word-break:break-all; }}
    .err {{ margin-top:16px; padding:12px 14px; border-radius:10px; font-size:13px;
            background:rgba(231,76,60,.1); color:#ff8a80; border:1px solid rgba(231,76,60,.3);
            white-space:pre-wrap; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Orders processed</h1>
    <div class="count">{count}</div>
    <div class="sub">{age}</div>
    <span class="badge {cls}"><span class="dot"></span>{label}</span>
    <div class="reason">{reason}</div>
    <table>
      <tr><td>Topic</td><td>{topic}</td></tr>
      <tr><td>Brokers</td><td>{brokers}</td></tr>
    </table>
    {error_block}
  </div>
</body>
</html>
"""


def render():
    s = common.read_status()
    now = time.time()
    count = s.get("count", 0)
    state = s.get("state", "unknown")
    updated_at = s.get("updated_at")
    last_ts = s.get("last_message_ts")
    error = s.get("last_error")

    # Defaults
    cls, label, reason = "warn", "Starting", "Waiting for the consumer to report…"
    error_block = ""

    if updated_at and (now - updated_at) > STALE_AFTER_S:
        # The consumer stopped writing its heartbeat — the process is down.
        cls, label = "bad", "Broken"
        reason = f"Consumer not reporting for {int(now - updated_at)}s — the consumer process is down."
    elif state == "error":
        cls, label = "bad", "Broken"
        reason = "The consumer hit an error connecting to Kafka."
        if error:
            error_block = f'<div class="err">{error}</div>'
    elif state == "connected":
        if last_ts and (now - last_ts) > STALL_AFTER_S:
            cls, label = "warn", "Stalled"
            reason = "Connected and healthy, with no error — but no messages are arriving."
        else:
            cls, label = "ok", "Healthy"
            reason = "Producer → Kafka → consumer flowing normally."

    if last_ts:
        secs = int(now - last_ts)
        age = "last message just now" if secs <= 1 else f"last message {secs}s ago"
    else:
        age = "no messages yet"

    return PAGE.format(
        count=count,
        age=age,
        cls=cls,
        label=label,
        reason=reason,
        topic=s.get("topic", "—"),
        brokers=s.get("brokers", "—"),
        error_block=error_block,
    )


@app.route("/")
def index():
    return Response(render(), mimetype="text/html")


@app.route("/healthz")
def healthz():
    return "ok"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
