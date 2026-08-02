"""Dashboard: the single visible heartbeat of the demo.

Serves one auto-refreshing page on :8080 showing the consumer's live message
count, how long since the last message, and the consumer's current state. When a
break lands, the count freezes and the state/age make the failure obvious to a
room full of people watching one screen.
"""

import time

from flask import Flask
from flask import Response

import common

app = Flask(__name__)

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
    table {{ width:100%; margin-top:26px; border-collapse:collapse; font-size:14px; }}
    td {{ padding:9px 0; border-top:1px solid #232c49; }}
    td:first-child {{ color:#8ea0d0; }}
    td:last-child {{ text-align:right; font-variant-numeric:tabular-nums;
                     word-break:break-all; }}
    .err {{ margin-top:18px; padding:12px 14px; border-radius:10px; font-size:13px;
            background:rgba(231,76,60,.1); color:#ff8a80; border:1px solid rgba(231,76,60,.3);
            white-space:pre-wrap; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Orders processed</h1>
    <div class="count">{count}</div>
    <div class="sub">{age}</div>
    <span class="badge {cls}"><span class="dot"></span>{state_label}</span>
    <table>
      <tr><td>Consumer state</td><td>{state}</td></tr>
      <tr><td>Topic</td><td>{topic}</td></tr>
      <tr><td>Brokers</td><td>{brokers}</td></tr>
    </table>
    {error_block}
  </div>
</body>
</html>
"""

STATE_STYLE = {
    "connected": ("ok", "Healthy"),
    "starting": ("warn", "Starting"),
    "error": ("bad", "Broken"),
}


def render():
    s = common.read_status()
    count = s.get("count", 0)
    state = s.get("state", "unknown")
    cls, label = STATE_STYLE.get(state, ("warn", "Unknown"))

    last_ts = s.get("last_message_ts")
    if last_ts:
        secs = int(time.time() - last_ts)
        age = f"last message {secs}s ago" if secs else "last message just now"
        # A healthy pipeline should see a message every few seconds. A long gap
        # while "connected" is the tell-tale of the silent wiring break.
        if state == "connected" and secs > 12:
            cls, label = ("warn", "Stalled")
    else:
        age = "no messages yet"

    error = s.get("last_error")
    error_block = f'<div class="err">{error}</div>' if error else ""

    return PAGE.format(
        count=count,
        age=age,
        cls=cls,
        state_label=label,
        state=state,
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
