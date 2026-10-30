"""
Origin application for the Cloudflare RFP demo — spec 0001.

A whiteboard with two surfaces on one hostname: a browser UI and a REST API.
Both are needed so that Bot Management, Rate Limiting and API Security can each
be demonstrated against the same service.

Carried over from the CapAct MVP, plus the two things the demo needs and the
MVP did not have:

  FR-7  Requests that did not come through Cloudflare are refused, so the
        "you cannot bypass the edge" claim is actually true.
  FR-9  Arrivals are counted, so "the edge stopped it" is backed by a number
        rather than an assertion.
"""

import hmac
import logging
import os
import threading
import uuid

from flask import Flask, jsonify, render_template, request
from google.cloud import firestore

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

db = firestore.Client()
COLLECTION = "whiteboard"
DOCUMENT = "current"

# ── FR-7: edge-only access ───────────────────────────────────────────────────
#
# Cloudflare injects this header on the origin-facing request (see the zone
# Terraform module). Anything arriving without it reached Cloud Run directly,
# which the demo must refuse.
#
# This is a demo-grade control and the demo narrative should say so: anyone who
# learns the value can replay it. The production recommendation is a load
# balancer with Cloud Armor allowlisting Cloudflare's published ranges. We use
# a header because it costs nothing and needs no always-on infrastructure.
EDGE_SECRET = os.environ.get("EDGE_SECRET", "")
EDGE_SECRET_HEADER = os.environ.get("EDGE_SECRET_HEADER", "X-Edge-Auth")

# /health is exempt because Cloud Run's startup probe calls the container
# directly, not through Cloudflare, and would never carry the header. It
# returns a fixed string and nothing else, so it leaks nothing. Point the
# bypass test at / or /api/message, never at /health.
UNPROTECTED_PATHS = frozenset({"/health"})
COUNTER_EXEMPT_PATHS = frozenset({"/api/stats", "/api/demo/stats"})

# ── FR-9: arrival counter ────────────────────────────────────────────────────
#
# In-process and therefore reset by a cold start. Gunicorn runs a single worker
# (see the Dockerfile) specifically so this is one counter per instance rather
# than one per worker process.
#
# For a demo window this is enough: the question is whether traffic reached the
# origin at all, and the answer is usually "none of it did". The authoritative
# cross-instance number is Cloud Monitoring:
#
#   gcloud monitoring time-series list --project=<project> \
#     --filter='metric.type="run.googleapis.com/request_count"'
_counter_lock = threading.Lock()
_arrivals = 0
INSTANCE_ID = os.environ.get("K_REVISION", "local") + "-" + uuid.uuid4().hex[:8]
_demo_counters_lock = threading.Lock()
_demo_counters = {
    "brute_force": 0,
    "malicious_scraping": 0,
    "spam_bots": 0,
    "automated_form_abuse": 0,
    "account_takeover": 0,
    "credential_stuffing": 0,
}
LOGIN_SCENARIOS = frozenset({"brute-force", "account-takeover", "credential-stuffing"})
FORM_SCENARIOS = frozenset({"spam-bots", "form-abuse"})


def _count_arrival() -> None:
    global _arrivals
    with _counter_lock:
        _arrivals += 1


def _count_demo_event(name: str) -> None:
    with _demo_counters_lock:
        _demo_counters[name] += 1


def get_message() -> str:
    doc = db.collection(COLLECTION).document(DOCUMENT).get()
    if doc.exists:
        return doc.to_dict().get("text", "")
    return ""


def set_message(text: str) -> str:
    db.collection(COLLECTION).document(DOCUMENT).set({"text": text})
    logger.info("Message updated: %s", text[:80])
    return text


@app.before_request
def enforce_edge_and_count():
    path = request.path

    if path in UNPROTECTED_PATHS:
        return None

    if EDGE_SECRET:
        presented = request.headers.get(EDGE_SECRET_HEADER, "")
        # Constant-time comparison: a timing oracle on this value would hand an
        # attacker the one secret that makes the origin reachable.
        if not hmac.compare_digest(presented, EDGE_SECRET):
            logger.warning(
                "Refused direct request to %s from %s — missing or wrong %s",
                path,
                request.headers.get("CF-Connecting-IP", request.remote_addr),
                EDGE_SECRET_HEADER,
            )
            return (
                jsonify(
                    {
                        "error": "forbidden",
                        "detail": "This origin only accepts requests through its Cloudflare edge.",
                    }
                ),
                403,
            )

    # Counted after the edge check, so refused requests do not inflate the
    # number. /api/stats is excluded so that reading the counter never changes
    # it.
    if path not in COUNTER_EXEMPT_PATHS:
        _count_arrival()

    return None


@app.route("/", methods=["GET"])
def index():
    return render_template("whiteboard.html")


@app.route("/api/demo/login", methods=["POST"])
def demo_login():
    scenario = request.args.get("scenario", "")
    if scenario not in LOGIN_SCENARIOS:
        return jsonify({"error": "unsupported synthetic login scenario"}), 400
    _count_demo_event(scenario.replace("-", "_"))
    return (
        jsonify(
            {
                "status": "rejected",
                "detail": "Simulation only: no account is checked or created.",
            }
        ),
        401,
    )


@app.route("/api/demo/catalog", methods=["GET"])
def demo_catalog():
    _count_demo_event("malicious_scraping")
    return jsonify(
        {
            "items": [
                {"id": "sample-1", "name": "Demo item one"},
                {"id": "sample-2", "name": "Demo item two"},
                {"id": "sample-3", "name": "Demo item three"},
            ]
        }
    )


@app.route("/api/demo/contact", methods=["POST"])
def demo_contact():
    scenario = request.args.get("scenario", "")
    if scenario not in FORM_SCENARIOS:
        return jsonify({"error": "unsupported synthetic form scenario"}), 400
    counter = "spam_bots" if scenario == "spam-bots" else "automated_form_abuse"
    _count_demo_event(counter)
    return (
        jsonify(
            {
                "status": "accepted-for-demo",
                "detail": "Simulation only: submitted data was discarded.",
            }
        ),
        202,
    )


@app.route("/api/demo/stats", methods=["GET"])
def demo_stats():
    with _demo_counters_lock:
        events = dict(_demo_counters)
    return jsonify({"events": events, "instance": INSTANCE_ID}), 200


@app.route("/api/message", methods=["GET", "POST"])
def api_message():
    if request.method == "GET":
        text_param = request.args.get("text")
        if text_param is not None:
            set_message(text_param)
            return jsonify({"text": text_param, "status": "updated"}), 200
        return jsonify({"text": get_message()}), 200

    data = request.get_json(silent=True) or {}
    text = data.get("text") or request.form.get("text", "")
    set_message(text)
    return jsonify({"text": text, "status": "updated"}), 200


@app.route("/api/stats", methods=["GET"])
def api_stats():
    """Arrivals since this instance started. Compare against what the load
    generator reports it sent over the same window."""
    with _counter_lock:
        arrivals = _arrivals
    return (
        jsonify(
            {
                "arrivals": arrivals,
                "instance": INSTANCE_ID,
                "edge_enforcement": bool(EDGE_SECRET),
                "note": "Per-instance, reset on cold start. Cloud Monitoring request_count is authoritative.",
            }
        ),
        200,
    )


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


if not EDGE_SECRET:
    logger.warning(
        "EDGE_SECRET is not set — the origin is accepting direct traffic and "
        "spec 0001 FR-7 is NOT satisfied. Expected only when running locally; "
        "the Terraform always sets it."
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=False)
