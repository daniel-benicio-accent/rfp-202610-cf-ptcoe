"""Send a bounded sample of synthetic requests to the Bot Management demo."""

import argparse
import math
import os
import re
import sys
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


MAX_REQUESTS = 10
MIN_INTERVAL_SECONDS = 0.5
HOST_PATTERN = re.compile(
    r"(?=.{1,253}\Z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\Z"
)


@dataclass(frozen=True)
class Scenario:
    method: str
    path: str
    query: tuple[tuple[str, str], ...] = ()


SCENARIOS = {
    "brute-force": Scenario("POST", "/api/demo/login", (("scenario", "brute-force"),)),
    "malicious-scraping": Scenario("GET", "/api/demo/catalog"),
    "spam-bots": Scenario("POST", "/api/demo/contact", (("scenario", "spam-bots"),)),
    "form-abuse": Scenario("POST", "/api/demo/contact", (("scenario", "form-abuse"),)),
    "account-takeover": Scenario(
        "POST", "/api/demo/login", (("scenario", "account-takeover"),)
    ),
    "credential-stuffing": Scenario(
        "POST", "/api/demo/login", (("scenario", "credential-stuffing"),)
    ),
}


class NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


HTTP = build_opener(NoRedirectHandler())


def build_target(hostname: str, scenario: Scenario) -> str:
    """Build an HTTPS URL for a predefined route on the configured hostname."""
    hostname = hostname.lower()
    if not HOST_PATTERN.fullmatch(hostname):
        raise ValueError("DEMO_HOSTNAME must be a DNS hostname, not a URL or path")
    if scenario not in SCENARIOS.values():
        raise ValueError("scenario must be one of the predefined scenarios")
    query = urlencode(scenario.query)
    target = f"https://{hostname}{scenario.path}"
    if query:
        target = f"{target}?{query}"
    parsed = urlsplit(target)
    if parsed.scheme != "https" or parsed.hostname != hostname:
        raise ValueError("target must use HTTPS and match DEMO_HOSTNAME")
    return target


def send_one(target: str, method: str) -> int:
    request = Request(
        target,
        data=b"" if method == "POST" else None,
        method=method,
        headers={
            "User-Agent": "BotManagement-Demo-Simulator/1.0",
            "Accept": "application/json",
        },
    )
    try:
        with HTTP.open(request, timeout=10) as response:
            return response.status
    except HTTPError as error:
        return error.code
    except URLError as error:
        raise RuntimeError(f"request failed: {error.reason}") from error


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Send a capped sample of empty, synthetic requests to the demo."
    )
    parser.add_argument("scenario", choices=sorted(SCENARIOS))
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args(argv)
    if not 1 <= args.count <= MAX_REQUESTS:
        parser.error(f"--count must be between 1 and {MAX_REQUESTS}")
    if not math.isfinite(args.interval) or args.interval < MIN_INTERVAL_SECONDS:
        parser.error(f"--interval must be at least {MIN_INTERVAL_SECONDS} seconds")
    return args


def main(argv=None):
    args = parse_args(argv)
    hostname = os.environ.get("DEMO_HOSTNAME", "")
    if not hostname:
        print("Set DEMO_HOSTNAME to the authorized Cloudflare demo hostname.", file=sys.stderr)
        return 2
    try:
        target = build_target(hostname, SCENARIOS[args.scenario])
    except ValueError as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2

    print(
        f"scenario={args.scenario} requests={args.count} "
        f"interval_seconds={args.interval} target=https://{hostname}"
    )
    for index in range(args.count):
        try:
            status = send_one(target, SCENARIOS[args.scenario].method)
        except RuntimeError as error:
            print(f"Request {index + 1}/{args.count} failed: {error}", file=sys.stderr)
            return 1
        print(f"request={index + 1}/{args.count} http_status={status}")
        if index + 1 < args.count:
            time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
