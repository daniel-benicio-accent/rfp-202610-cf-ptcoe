#!/usr/bin/env python3
r"""
Baseline API traffic for OWASP Juice Shop behind Cloudflare, to populate
API Shield Discovery (dashboard: Web Assets > Operations > "Discovered").

What Discovery counts (developers.cloudflare.com, checked Nov 2026):
  * requests that return 2xx at the Cloudflare edge;
  * that do not come from a Cloudflare Worker (run this from a laptop or VM);
  * on operations that get at least 500 requests within a 10-day window.
Discovery works on *sampled* traffic and is not real-time. Cloudflare publishes
no refresh interval, so start this well ahead of a demo (a day is a safe
margin) and expect the dashboard to stay unchanged for the first hours.

How the script gets every operation over that threshold:
  * Balanced rotation: each round runs every flow once, in random order, so all
    operations grow at the same rate and cross --target together.
  * Writes are round trips (create, read, update, delete), so the shop's data
    stays the same size however long this runs. The two flows that cannot clean
    up after themselves (sign-up, complaints) stop once they reach --target.
  * Paths, methods and payloads mirror the Juice Shop Angular front end, so the
    inventory matches what a browser would produce.
  * After login every request carries "Authorization: Bearer <JWT>", the header
    API Shield uses (or auto-configures) as the session identifier.
  * Logins are spaced (--login-interval) to stay under login rate-limit rules,
    and tokens are refreshed at a random point 4-5 h after login, ahead of
    Juice Shop's 6 h expiry, so users never all re-login at once.
  * Self-healing: a rejected token triggers a fresh login, and a rejected login
    (Juice Shop re-seeds its database on every restart) a fresh registration.
  * Cloudflare mitigations are counted as CF-CHALLENGE / CF-BLOCK-<status>,
    apart from origin errors, and reported with a Ray ID, so an edge rule eating
    the traffic is visible. A flow the edge blocks sits out for 30 minutes
    rather than leave half-finished round trips behind, then retries by itself.

Usage:
  pip install requests

  # One pass over every operation: prints a status per operation and exits
  # non-zero if any flow failed. Run this first.
  python3 scripts/apidiscovery-juiceshop-baseline-traffic.py \
      --base-url https://<demo-host> --check

  # Long run, logging to a file. At the default 3 req/s every operation gets
  # 500 hits in about 1.5 h (logins, deliberately throttled, in about 3 h).
  nohup python3 scripts/apidiscovery-juiceshop-baseline-traffic.py \
      --base-url https://<demo-host> --duration-hours 72 > baseline.log 2>&1 &
"""

from __future__ import annotations

import argparse
import logging
import random
import re
import signal
import sys
import threading
import time
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Callable
from urllib.parse import quote

try:
    import requests
except ImportError:
    sys.exit("This script needs the 'requests' package: pip install requests")

LOG = logging.getLogger("baseline")

REQUEST_TIMEOUT_S = 15
BREAKER_FAILURES = 10        # consecutive failed runs before a flow sits out
BREAKER_PAUSE_S = 600        # how long it sits out
# A flow Cloudflare blocks sits out at once, and for longer: retrying it every
# round would only leave half-finished round trips (a POST whose DELETE is
# blocked) behind in the shop. It resumes by itself once the edge allows it.
EDGE_BLOCK_PAUSE_S = 1800
MAX_BACKOFF_S = 60           # cap on Retry-After when rate limited
TOKEN_REFRESH_S = (4 * 3600, 5 * 3600)  # re-login window; Juice Shop JWTs last 6 h
FALLBACK_PRODUCT_IDS = list(range(1, 10))  # juices and shirts, stable across releases
DELIVERY_IDS = (1, 2, 3)
SEARCH_TERMS = ["apple", "juice", "banana", "lemon", "melon", "egg", "orange", "shirt", ""]
REVIEW_TEXTS = ["Tastes great, would buy again.", "Good value for money.",
                "Fresh and quickly delivered."]
FEEDBACK_TEXTS = ["Nice shop, easy checkout.", "Good selection of juices.",
                  "Delivery was on time."]
COMPLAINT_TEXTS = ["My order arrived a day late.", "One bottle was slightly dented."]


# ---------- small helpers ----------
def _fill(template: str, args: tuple[object, ...]) -> str:
    """Fill {placeholders} in order: ("/api/Products/{id}", (7,)) -> "/api/Products/7"."""
    values = iter(args)
    return re.sub(r"\{[^}]*\}", lambda _: quote(str(next(values)), safe=""), template)


def _json(resp: requests.Response | None) -> dict:
    if resp is None:
        return {}
    try:
        body = resp.json()
    except ValueError:
        return {}
    return body if isinstance(body, dict) else {}


def _data_id(resp: requests.Response | None) -> int | None:
    data = _json(resp).get("data")
    return data.get("id") if isinstance(data, dict) else None


def _all_ok(*responses: requests.Response | None) -> bool:
    return all(r is not None for r in responses)


def _classify(resp: requests.Response) -> str:
    """Outcome label for the stats. Cloudflare mitigations get their own label."""
    if resp.headers.get("cf-mitigated"):
        return "CF-CHALLENGE"
    if (resp.status_code in (403, 429, 503)
            and "text/html" in resp.headers.get("Content-Type", "")
            and "cloudflare" in resp.text[:5000].lower()):
        return f"CF-BLOCK-{resp.status_code}"
    return str(resp.status_code)


def _hms(seconds: float) -> str:
    s = int(seconds)
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"


# ---------- shared state ----------
@dataclass
class UserSession:
    """One synthetic shopper: its own cookies, token and connection pool."""
    http: requests.Session
    email: str = ""
    password: str = ""
    user_id: int | None = None
    basket_id: int | None = None
    review_id: str | None = None   # this user's own review, target of the PATCH flow
    review_tried: bool = False     # create at most one review per identity
    refresh_at: float = 0.0        # monotonic time of the next proactive re-login


@dataclass
class Flow:
    name: str
    # True when every request returned 2xx, False on failure, None when it
    # skipped its turn without sending anything.
    run: Callable[[UserSession], bool | None]
    ops: tuple[str, ...]                 # operations it produces, as "METHOD /template"
    grows: bool = False                  # leaves data behind, so stops at --target
    runs_ok: int = 0
    failures: int = 0
    paused_until: float = 0.0


class Stats:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._by_op: defaultdict[str, Counter[str]] = defaultdict(Counter)
        self._blocked: dict[str, str] = {}  # op -> Ray ID of the last edge mitigation
        self.started = time.monotonic()

    def record(self, op: str, outcome: str, ray: str | None = None) -> None:
        with self._lock:
            self._by_op[op][outcome] += 1
            if outcome.startswith("CF-") and ray:
                self._blocked[op] = ray
            elif outcome.startswith("2"):
                self._blocked.pop(op, None)  # the edge lets it through now

    def snapshot(self) -> dict[str, Counter[str]]:
        with self._lock:
            return {op: Counter(c) for op, c in self._by_op.items()}

    def blocked(self) -> dict[str, str]:
        with self._lock:
            return dict(self._blocked)


class Pacer:
    """Spaces requests at ~rps across all workers, with jitter."""

    def __init__(self, rps: float, stop: threading.Event) -> None:
        self._interval = 1.0 / rps
        self._stop = stop
        self._lock = threading.Lock()
        self._next = time.monotonic()

    def wait(self) -> None:
        with self._lock:
            slot = max(self._next, time.monotonic())
            # Jitter keeps the cadence organic instead of a metronome.
            self._next = slot + self._interval * random.uniform(0.5, 1.5)
        delay = slot - time.monotonic()
        if delay > 0 and not self._stop.is_set():
            self._stop.wait(delay)

    def try_acquire(self) -> bool:
        """Take the next slot only if it is already due; never waits."""
        with self._lock:
            now = time.monotonic()
            if self._next > now:
                return False
            self._next = now + self._interval * random.uniform(0.5, 1.5)
            return True


class Scheduler:
    """Hands out flows in shuffled rounds: every eligible flow once per round."""

    def __init__(self, flows: list[Flow], target: int) -> None:
        self._flows = flows
        self._target = target
        self._queue: list[Flow] = []
        self._lock = threading.Lock()

    def capped(self, flow: Flow) -> bool:
        return flow.grows and flow.runs_ok >= self._target

    def next(self) -> Flow | None:
        with self._lock:
            if not self._queue:
                now = time.monotonic()
                self._queue = [f for f in self._flows
                               if f.paused_until <= now and not self.capped(f)]
                random.shuffle(self._queue)
            return self._queue.pop() if self._queue else None

    def done(self, flow: Flow, ok: bool, edge_blocked: bool = False) -> None:
        with self._lock:
            if ok:
                flow.runs_ok += 1
                flow.failures = 0
                return
            if edge_blocked:
                flow.failures = 0
                flow.paused_until = time.monotonic() + EDGE_BLOCK_PAUSE_S
                LOG.warning("Cloudflare blocked part of flow %s; it sits out %d min and "
                            "resumes by itself once the edge allows it.",
                            flow.name, EDGE_BLOCK_PAUSE_S // 60)
                return
            flow.failures += 1
            if flow.failures >= BREAKER_FAILURES:
                flow.failures = 0
                flow.paused_until = time.monotonic() + BREAKER_PAUSE_S
                LOG.warning("Flow %s failed %d times in a row; pausing it for %d min. "
                            "Rerun with --verbose to see the responses.",
                            flow.name, BREAKER_FAILURES, BREAKER_PAUSE_S // 60)


# ---------- the generator ----------
class TrafficGenerator:
    def __init__(self, base_url: str, user_agent: str, rps: float, target: int,
                 login_interval_s: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.user_agent = user_agent
        self.target = target
        self.stop = threading.Event()
        self.pacer = Pacer(rps, self.stop)
        # Every login (enrolment, rotation, refresh, recovery) goes through this one.
        self.login_pacer = Pacer(1.0 / login_interval_s, self.stop)
        self.stats = Stats()
        self._local = threading.local()  # per worker: did the current flow hit an edge block?
        self.product_ids = FALLBACK_PRODUCT_IDS
        self.basket_product_ids = FALLBACK_PRODUCT_IDS
        self.question_ids = [1]
        self.flows = self._build_flows()
        self.scheduler = Scheduler(self.flows, target)

    # ----- transport -----
    def new_user(self) -> UserSession:
        http = requests.Session()
        # Same Accept header as the Angular HttpClient in the Juice Shop front end.
        http.headers.update({"User-Agent": self.user_agent,
                             "Accept": "application/json, text/plain, */*"})
        return UserSession(http=http)

    def _call(self, user: UserSession, method: str, template: str, *args: object,
              auth: bool = True, raw: bool = False, _retried: bool = False,
              **kwargs: object) -> requests.Response | None:
        """Send one request and record it under "METHOD /template" (the same
        grouping Discovery applies to variable path segments).

        Returns the response when it is 2xx, or any response with raw=True;
        None otherwise. A 401 on an authenticated call re-logs in once and retries.
        """
        op = f"{method} {template}"
        path = _fill(template, args)
        self.pacer.wait()
        try:
            resp = user.http.request(method, self.base_url + path,
                                     timeout=REQUEST_TIMEOUT_S, **kwargs)
        except requests.RequestException as exc:
            self.stats.record(op, "ERR")
            LOG.debug("%s %s failed: %s", method, path, exc)
            return None
        outcome = _classify(resp)
        self.stats.record(op, outcome, resp.headers.get("cf-ray"))
        if outcome.startswith("2"):
            return resp
        if outcome.startswith("CF-"):
            self._local.edge_blocked = True
        LOG.debug("%s %s -> %s %s", method, path, outcome,
                  resp.text[:200].replace("\n", " "))
        if resp.status_code == 429:
            try:
                delay = float(resp.headers.get("Retry-After", 30))
            except ValueError:
                delay = 30.0
            delay = min(MAX_BACKOFF_S, max(1.0, delay))
            LOG.warning("429 (%s) on %s; this worker backs off %.0fs.", outcome, op, delay)
            self.stop.wait(delay)
        elif resp.status_code == 401 and auth and not _retried and self._reauth(user):
            return self._call(user, method, template, *args, auth=auth, raw=raw,
                              _retried=True, **kwargs)
        return resp if raw else None

    # ----- identity -----
    def _register(self, user: UserSession) -> bool:
        """Give the session a brand-new account, the way the sign-up page does."""
        user.http.headers.pop("Authorization", None)
        user.http.cookies.clear()
        user.email = f"baseline-{uuid.uuid4().hex[:10]}@demo.local"
        user.password = f"Demo!{uuid.uuid4().hex[:12]}"
        user.user_id = user.basket_id = user.review_id = None
        user.review_tried = False
        question_id = random.choice(self.question_ids)
        resp = self._call(user, "POST", "/api/Users/", auth=False, json={
            "email": user.email, "password": user.password,
            "passwordRepeat": user.password,
            "securityQuestion": {"id": question_id}, "securityAnswer": "demo"})
        user.user_id = _data_id(resp)
        if user.user_id is None:
            return False
        # The front end stores the security answer in a second call.
        self._call(user, "POST", "/api/SecurityAnswers/", auth=False, json={
            "UserId": user.user_id, "answer": "demo", "SecurityQuestionId": question_id})
        return True

    def _login(self, user: UserSession, paced: bool = True) -> str:
        """Returns "ok", "rejected" (bad credentials) or "error".
        paced=False when the caller already holds a login_pacer slot."""
        if paced:
            self.login_pacer.wait()
        resp = self._call(user, "POST", "/rest/user/login", auth=False, raw=True,
                          json={"email": user.email, "password": user.password})
        if resp is None:
            return "error"
        if resp.status_code == 401:
            return "rejected"
        auth = _json(resp).get("authentication") or {}
        token = auth.get("token") if isinstance(auth, dict) else None
        if resp.status_code != 200 or not token:
            return "error"
        # Header for API Shield's session identifier; cookie for the pages that read it.
        user.http.headers["Authorization"] = f"Bearer {token}"
        user.http.cookies.set("token", token)
        user.basket_id = auth.get("bid")
        user.refresh_at = time.monotonic() + random.uniform(*TOKEN_REFRESH_S)
        return "ok"

    def _reauth(self, user: UserSession, paced: bool = True) -> bool:
        state = self._login(user, paced)
        if state == "rejected":
            # Juice Shop re-seeds its database on every restart, which deletes
            # our accounts. Take a new identity instead of failing forever.
            LOG.warning("Login rejected for %s (Juice Shop restarted?); re-registering.",
                        user.email)
            return self._register(user) and self._login(user) == "ok"
        return state == "ok"

    def enroll(self) -> UserSession | None:
        user = self.new_user()
        # One enrolment at a time, at the login pace: workers signing up together
        # stalled the origin past the request timeout.
        self.login_pacer.wait()
        if self._register(user) and self._login(user, paced=False) == "ok":
            return user
        user.http.close()
        return None

    def load_catalog(self) -> None:
        """Learn product, stock and security-question IDs from the live shop."""
        anon = self.new_user()
        try:
            products = _json(self._call(anon, "GET", "/rest/products/search", auth=False,
                                        params={"q": ""})).get("data") or []
            stock = _json(self._call(anon, "GET", "/api/Quantitys/", auth=False)).get("data") or []
            questions = _json(self._call(anon, "GET", "/api/SecurityQuestions/",
                                         auth=False)).get("data") or []
        finally:
            anon.http.close()
        ids = [p["id"] for p in products if isinstance(p, dict) and "id" in p]
        # Products that accept a quantity of 2: in stock and not limited to 1 per user,
        # otherwise the basket PUT gets a 400.
        roomy = {q.get("ProductId") for q in stock if isinstance(q, dict)
                 and (q.get("quantity") or 0) >= 2
                 and (not q.get("limitPerUser") or q["limitPerUser"] >= 2)}
        self.product_ids = ids or FALLBACK_PRODUCT_IDS
        self.basket_product_ids = [p for p in self.product_ids if p in roomy] or self.product_ids
        self.question_ids = [q["id"] for q in questions
                             if isinstance(q, dict) and "id" in q] or [1]
        LOG.info("Catalog: %d products (%d usable in the basket), %d security questions",
                 len(self.product_ids), len(self.basket_product_ids), len(self.question_ids))

    # ----- flows -----
    def _build_flows(self) -> list[Flow]:
        def get(template: str, args: Callable[[UserSession], tuple] | None = None,
                params: Callable[[UserSession], dict] | None = None) -> Flow:
            op = f"GET {template}"

            def run(user: UserSession) -> bool:
                return self._call(user, "GET", template, *(args(user) if args else ()),
                                  params=params(user) if params else None) is not None
            return Flow(op, run, (op,))

        def product(_: UserSession) -> tuple:
            return (random.choice(self.product_ids),)

        def order_id(_: UserSession) -> tuple:
            return (f"{uuid.uuid4().hex[:4]}-{uuid.uuid4().hex[:16]}",)

        return [
            # Public reads (sent with the token anyway, as the front end does).
            get("/rest/admin/application-version"),
            get("/rest/admin/application-configuration"),
            get("/rest/languages"),
            get("/rest/memories/"),
            get("/rest/continue-code"),
            get("/api/Challenges/"),
            get("/api/Quantitys/"),
            get("/api/SecurityQuestions/"),
            get("/api/Feedbacks/"),
            get("/rest/products/search", params=lambda _: {"q": random.choice(SEARCH_TERMS)}),
            get("/api/Products/{id}", product,
                params=lambda _: {"d": time.strftime("%a %b %d %Y")}),
            get("/rest/products/{id}/reviews", product),
            get("/rest/track-order/{id}", order_id),
            get("/rest/user/security-question", params=lambda u: {"email": u.email}),
            # Authenticated reads.
            get("/rest/user/whoami"),
            get("/api/Users/{id}", lambda u: (u.user_id,)),
            get("/rest/basket/{id}", lambda u: (u.basket_id,)),
            get("/api/Addresss"),
            get("/api/Cards"),
            get("/api/Deliverys"),
            get("/api/Deliverys/{id}", lambda _: (random.choice(DELIVERY_IDS),)),
            get("/rest/wallet/balance"),
            get("/rest/order-history"),
            get("/rest/deluxe-membership"),
            get("/rest/2fa/status"),
            # Writes: each one cleans up after itself unless marked grows=True.
            Flow("login", self.flow_login, ("POST /rest/user/login",)),
            Flow("basket", self.flow_basket,
                 ("POST /api/BasketItems/", "GET /api/BasketItems/{id}",
                  "PUT /api/BasketItems/{id}", "DELETE /api/BasketItems/{id}")),
            Flow("address", self.flow_address,
                 ("POST /api/Addresss/", "GET /api/Addresss/{id}",
                  "PUT /api/Addresss/{id}", "DELETE /api/Addresss/{id}")),
            Flow("card+wallet", self.flow_card,
                 ("POST /api/Cards/", "GET /api/Cards/{id}",
                  "PUT /rest/wallet/balance", "DELETE /api/Cards/{id}")),
            Flow("feedback", self.flow_feedback,
                 ("GET /rest/captcha/", "POST /api/Feedbacks/", "DELETE /api/Feedbacks/{id}")),
            Flow("review", self.flow_review, ("PATCH /rest/products/reviews",)),
            Flow("signup", self.flow_signup,
                 ("POST /api/Users/", "POST /api/SecurityAnswers/"), grows=True),
            Flow("complaint", self.flow_complaint, ("POST /api/Complaints/",), grows=True),
        ]

    def flow_login(self, user: UserSession) -> bool | None:
        # Logins are spaced by login_pacer. When one is not due yet, skip this
        # turn rather than park a worker behind it for up to --login-interval.
        if not self.login_pacer.try_acquire():
            return None
        return self._reauth(user, paced=False)

    def flow_basket(self, user: UserSession) -> bool:
        resp = self._call(user, "POST", "/api/BasketItems/", json={
            "ProductId": random.choice(self.basket_product_ids),
            "BasketId": str(user.basket_id), "quantity": 1})
        item_id = _data_id(resp)
        if item_id is None:
            return False
        got = self._call(user, "GET", "/api/BasketItems/{id}", item_id)
        put = self._call(user, "PUT", "/api/BasketItems/{id}", item_id, json={"quantity": 2})
        # Delete even if the middle steps failed, so the basket stays empty and the
        # next POST of the same product does not hit the unique constraint.
        deleted = self._call(user, "DELETE", "/api/BasketItems/{id}", item_id)
        return _all_ok(got, put, deleted)

    def flow_address(self, user: UserSession) -> bool:
        address = {"country": "Portugal", "fullName": "Demo User", "mobileNum": 912345678,
                   "zipCode": "1000-001", "streetAddress": "Rua Demo 1",
                   "city": "Lisboa", "state": "Lisboa"}
        address_id = _data_id(self._call(user, "POST", "/api/Addresss/", json=address))
        if address_id is None:
            return False
        got = self._call(user, "GET", "/api/Addresss/{id}", address_id)
        put = self._call(user, "PUT", "/api/Addresss/{id}", address_id,
                         json={**address, "streetAddress": "Rua Demo 2"})
        deleted = self._call(user, "DELETE", "/api/Addresss/{id}", address_id)
        return _all_ok(got, put, deleted)

    def flow_card(self, user: UserSession) -> bool:
        card = {"fullName": "Demo User",
                "cardNum": random.randint(4_000_000_000_000_000, 4_999_999_999_999_999),
                "expMonth": random.randint(1, 12), "expYear": random.randint(2080, 2099)}
        card_id = _data_id(self._call(user, "POST", "/api/Cards/", json=card))
        if card_id is None:
            return False
        got = self._call(user, "GET", "/api/Cards/{id}", card_id)
        topup = self._call(user, "PUT", "/rest/wallet/balance",
                           json={"balance": 1, "paymentId": card_id})
        deleted = self._call(user, "DELETE", "/api/Cards/{id}", card_id)
        return _all_ok(got, topup, deleted)

    def flow_feedback(self, user: UserSession) -> bool:
        # Juice Shop returns the CAPTCHA answer with the CAPTCHA (an intended flaw).
        captcha = _json(self._call(user, "GET", "/rest/captcha/"))
        if "captchaId" not in captcha:
            return False
        # Ratings 2-4 only: 0 and 5 stars are tied to Juice Shop challenges, which
        # would pop "challenge solved" banners during a live demo.
        feedback_id = _data_id(self._call(user, "POST", "/api/Feedbacks/", json={
            "UserId": user.user_id, "captchaId": captcha["captchaId"],
            "captcha": captcha.get("answer"), "comment": random.choice(FEEDBACK_TEXTS),
            "rating": random.randint(2, 4)}))
        if feedback_id is None:
            return False
        return self._call(user, "DELETE", "/api/Feedbacks/{id}", feedback_id) is not None

    def flow_review(self, user: UserSession) -> bool:
        """PATCH the user's own review. Each identity creates one review, once;
        patching someone else's would solve a challenge and alter seeded data."""
        if user.review_id is None and not user.review_tried:
            product_id = random.choice(self.product_ids)
            if self._call(user, "PUT", "/rest/products/{id}/reviews", product_id, json={
                    "message": random.choice(REVIEW_TEXTS),
                    "author": user.email}) is not None:
                # Created: never create another, even if the lookup below fails.
                user.review_tried = True
                reviews = _json(self._call(user, "GET", "/rest/products/{id}/reviews",
                                           product_id)).get("data") or []
                user.review_id = next((r.get("_id") for r in reviews if isinstance(r, dict)
                                       and r.get("author") == user.email), None)
        if user.review_id is None:
            return False
        return self._call(user, "PATCH", "/rest/products/reviews", json={
            "id": user.review_id, "message": random.choice(REVIEW_TEXTS)}) is not None

    def flow_signup(self, _: UserSession) -> bool:
        """A new visitor signs up: anonymous session, account left behind."""
        visitor = self.new_user()
        try:
            return self._register(visitor)
        finally:
            visitor.http.close()

    def flow_complaint(self, user: UserSession) -> bool:
        return self._call(user, "POST", "/api/Complaints/", json={
            "UserId": user.user_id, "message": random.choice(COMPLAINT_TEXTS)}) is not None

    # ----- execution -----
    def _run_flow(self, flow: Flow, user: UserSession) -> bool | None:
        self._local.edge_blocked = False
        try:
            ok = flow.run(user)
        except Exception:  # a bug in one flow must not take the worker down
            LOG.exception("Flow %s crashed", flow.name)
            ok = False
        if ok is not None:
            self.scheduler.done(flow, ok, edge_blocked=self._local.edge_blocked)
        return ok

    def preflight(self, user: UserSession) -> list[str]:
        """Run every flow once with one user; return the names of flows that failed."""
        return [f.name for f in self.flows if not self.stop.is_set()
                and self._run_flow(f, user) is False]

    def _worker(self, users: list[UserSession], to_enroll: int) -> None:
        # Each worker owns its users, so no requests.Session is shared across
        # threads. It enrols them itself: logins are paced, so workers come online
        # one by one instead of the whole run waiting for every login up front.
        while to_enroll and not self.stop.is_set():
            user = self.enroll()
            if user:
                users.append(user)
                to_enroll -= 1
            else:
                LOG.warning("Enrolment failed; this worker retries in 60s")
                self.stop.wait(60)
        while not self.stop.is_set():
            flow = self.scheduler.next()
            if flow is None:  # every flow paused or capped
                self.stop.wait(5)
                continue
            user = random.choice(users)
            if time.monotonic() >= user.refresh_at:
                self._reauth(user)
            self._run_flow(flow, user)

    def run(self, first_user: UserSession, n_users: int, workers: int, duration_s: float,
            report_every_s: float) -> None:
        # Worker 0 starts at once with the preflight user; the others enrol theirs.
        shares = [n_users // workers + (i < n_users % workers) for i in range(workers)]
        threads = [threading.Thread(target=self._worker,
                                    args=([first_user], shares[0] - 1) if i == 0
                                    else ([], shares[i]),
                                    name=f"worker-{i}", daemon=True)
                   for i in range(workers)]
        for t in threads:
            t.start()
        deadline = time.monotonic() + duration_s
        next_report = time.monotonic() + report_every_s
        while not self.stop.is_set() and time.monotonic() < deadline:
            time.sleep(1)  # short sleeps keep Ctrl+C responsive, Windows included
            if time.monotonic() >= next_report:
                self.report()
                next_report += report_every_s
        self.stop.set()
        for t in threads:
            t.join(timeout=REQUEST_TIMEOUT_S * 2)
        self.report()

    # ----- reporting -----
    def edge_mitigations(self) -> int:
        return sum(n for c in self.stats.snapshot().values()
                   for k, n in c.items() if k.startswith("CF-"))

    def report(self) -> None:
        snap = self.stats.snapshot()
        elapsed = max(time.monotonic() - self.stats.started, 1e-6)

        def ok(op: str) -> int:
            return sum(n for k, n in snap.get(op, {}).items() if k.startswith("2"))

        def path_first(op: str) -> tuple[str, str]:
            return op.split(" ", 1)[1], op

        targeted = sorted({op for f in self.flows for op in f.ops}, key=path_first)
        capped = {op for f in self.flows if self.scheduler.capped(f) for op in f.ops}
        extras = sorted(set(snap) - set(targeted), key=path_first)
        now = time.monotonic()
        paused = {op for f in self.flows if f.paused_until > now for op in f.ops}
        blocked = self.stats.blocked()
        total = sum(sum(c.values()) for c in snap.values())
        reached = sum(ok(op) >= self.target for op in targeted)
        # ETA over the operations that can progress: paused ones would say n/a forever.
        progressing = [op for op in targeted if op not in paused and op not in capped]
        slowest = min(progressing or targeted, key=ok)
        rate = ok(slowest) / elapsed
        eta = ("done" if ok(slowest) >= self.target else
               _hms((self.target - ok(slowest)) / rate) if rate else "n/a")

        lines = [f"==== {_hms(elapsed)} elapsed | {total} requests | {total / elapsed:.1f} req/s"
                 f" | {reached}/{len(targeted)} operations at {self.target}"
                 f" | slowest {slowest} ({ok(slowest)}, ETA {eta}) ====",
                 f"  {'operation':<44} {'2xx':>7} {'target':>7}  other outcomes"]
        for op in targeted + extras:
            n = ok(op)
            if op in capped:
                progress = "capped"
            elif op in paused and n < self.target:
                progress = "paused"
            elif op in targeted:
                progress = "done" if n >= self.target else f"{n / self.target:.0%}"
            else:
                progress = "setup"
            other = " ".join(f"{k}:{v}" for k, v in sorted(snap.get(op, {}).items())
                             if not k.startswith("2"))
            lines.append(f"  {op:<44} {n:>7} {progress:>7}  {other}")

        outcomes = Counter(k for c in snap.values() for k in c.elements())
        if blocked:
            lines.append("  ! Cloudflare mitigated these operations, so Discovery cannot count "
                         "them. Look a Ray ID up in Security > Events to find the rule:")
            lines += [f"      {op:<44} ray {ray}"
                      for op, ray in sorted(blocked.items(), key=lambda i: path_first(i[0]))]
        if outcomes["ERR"]:
            lines.append("  ! Network errors (ERR): check origin health, proxies, and TLS "
                         "inspection (set REQUESTS_CA_BUNDLE if a corporate proxy re-signs).")
        LOG.info("\n".join(lines))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", required=True,
                        help="Public, Cloudflare-proxied URL of Juice Shop")
    parser.add_argument("--check", action="store_true",
                        help="Run every flow once, print the per-operation result and exit")
    parser.add_argument("--users", type=int, default=6,
                        help="Synthetic logged-in users (default: 6)")
    parser.add_argument("--workers", type=int, default=6,
                        help="Concurrent workers, each owning a share of the users; at "
                             "~0.3-1 s per request one worker sustains about 1 req/s "
                             "(default: 6)")
    parser.add_argument("--rps", type=float, default=3.0,
                        help="Average requests per second across all workers. Juice Shop "
                             "is CPU-bound on some endpoints (/rest/languages tops out "
                             "near 1.5 req/s on the demo origin); 3 keeps the shop "
                             "responsive for live use (default: 3)")
    parser.add_argument("--target", type=int, default=1000,
                        help="2xx requests wanted per operation; Discovery needs 500 in 10 "
                             "days, the margin covers sampling (default: 1000)")
    parser.add_argument("--login-interval", type=float, default=20.0,
                        help="Minimum seconds between logins, to stay under login "
                             "rate-limit rules on the zone (default: 20)")
    parser.add_argument("--duration-hours", type=float, default=72.0)
    parser.add_argument("--report-minutes", type=float, default=5.0)
    parser.add_argument("--user-agent", default="juiceshop-baseline-generator/2.0")
    parser.add_argument("--verbose", action="store_true",
                        help="Log every non-2xx response with the start of its body")
    args = parser.parse_args()
    if (args.rps <= 0 or args.login_interval <= 0 or args.users < 1 or args.workers < 1
            or args.target < 1):
        parser.error("--rps, --login-interval, --users, --workers and --target "
                     "must be positive")
    return args


def main() -> int:
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    gen = TrafficGenerator(args.base_url, args.user_agent, args.rps, args.target,
                           args.login_interval)

    def on_signal(*_: object) -> None:
        if gen.stop.is_set():
            raise KeyboardInterrupt  # second Ctrl+C: leave now
        LOG.info("Stopping; in-flight flows finish their clean-up first (Ctrl+C again to force)")
        gen.stop.set()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    gen.load_catalog()
    if gen.edge_mitigations():
        gen.report()
        LOG.error("Cloudflare challenges or blocks this client before it reaches Juice Shop. "
                  "Discovery only counts 2xx: add a WAF skip rule for this source IP or user "
                  "agent, or relax Bot Fight Mode, then retry.")
        return 2

    user = gen.enroll()
    if user is None:
        gen.report()
        LOG.error("No user could register and log in; check the URL, WAF rules and origin health.")
        return 1
    LOG.info("Preflight: every flow once, as %s", user.email)

    failed = gen.preflight(user)
    gen.report()
    if failed:
        LOG.warning("Preflight: %d of %d flows failed: %s. Rerun with --check --verbose "
                    "to see the responses.", len(failed), len(gen.flows), ", ".join(failed))
    else:
        LOG.info("Preflight: all %d flows returned 2xx", len(gen.flows))
    blocked_methods = sorted({op.split(" ", 1)[0] for op in gen.stats.blocked()})
    if blocked_methods:
        LOG.error("Cloudflare blocks %s on this host (Ray IDs above). Discovery only counts "
                  "2xx, so those operations cannot be discovered, and the shop's own basket "
                  "page breaks for real visitors too. Allow these methods for the Juice Shop "
                  "hostname, or skip the rule for this generator. Blocked flows retry every "
                  "%d min and resume by themselves.", "/".join(blocked_methods),
                  EDGE_BLOCK_PAUSE_S // 60)
    if args.check:
        return 1 if failed else 0
    if gen.stop.is_set():
        return 130

    workers = min(args.workers, args.users)
    LOG.info("Running %d workers over %d users at ~%.1f req/s for %.1f h, reporting every "
             "%.0f min. Workers come online as their user logs in (one login per ~%.0fs). "
             "Discovery is sampled and batch-processed: expect hours, not minutes, before "
             "Web Assets > Operations changes.", workers, args.users, args.rps,
             args.duration_hours, args.report_minutes, args.login_interval)
    gen.run(user, args.users, workers, args.duration_hours * 3600, args.report_minutes * 60)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
