"""Send a bounded sample of synthetic requests to the Bot Management demo."""

import argparse
import base64
import json
import math
import os
import re
import sys
import time
from dataclasses import dataclass
import token
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


MAX_REQUESTS = 200
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
    "spam-bots": Scenario("POST", "/rest/user/login"),
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

def spam_bot_login(
    hostname: str,
    email: str,
    password: str,
) -> tuple[str, int]:
    target = f"https://{hostname}/rest/user/login"

    payload = json.dumps({
        "email": email,
        "password": password,
    }).encode("utf-8")

    request = Request(
        target,
        data=payload,
        method="POST",
        headers={
            "User-Agent": "BotManagement-Demo-Simulator/1.0",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )

    try:
        with HTTP.open(request, timeout=10) as response:
            body = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        raise RuntimeError(
            f"login failed with HTTP {error.code}"
        ) from error
    except URLError as error:
        raise RuntimeError(
            f"login failed: {error.reason}"
        ) from error

    token = body.get("authentication", {}).get("token")

    if not token:
        raise RuntimeError(
            "login succeeded but no authentication token was returned"
        )

    try:
        token_parts = token.split(".")

        if len(token_parts) != 3:
            raise ValueError("unexpected token format")

        encoded_payload = token_parts[1]
        padding = "=" * (-len(encoded_payload) % 4)

        decoded_payload = base64.urlsafe_b64decode(
            encoded_payload + padding
        )

        token_payload = json.loads(
            decoded_payload.decode("utf-8")
        )

        user_id = token_payload.get("data", {}).get("id")

        if not isinstance(user_id, int):
            raise ValueError("user ID is missing from token")

    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            "login succeeded but the user ID could not be read from the token"
        ) from error

    return token, user_id

def send_spam_complaint(
    hostname: str,
    token: str,
    email: str,
    user_id: int,
    message: str,
) -> int:
    target = f"https://{hostname}/api/Complaints/"

    payload = json.dumps({
        "UserId": user_id,
        "message": message,
    }).encode("utf-8")

    request = Request(
        target,
        data=payload,
        method="POST",
        headers={
            "User-Agent": "BotManagement-Demo-Simulator/1.0",
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "Cookie": f"token={token}",
            "x-user-email": email,
        },
    )

    try:
        with HTTP.open(request, timeout=10) as response:
            return response.status
    except HTTPError as error:
        return error.code
    except URLError as error:
        raise RuntimeError(
            f"complaint request failed: {error.reason}"
        ) from error
        
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
    if args.scenario == "spam-bots":
        email = os.environ.get("SPAM_BOT_EMAIL", "")
        password = os.environ.get("SPAM_BOT_PASSWORD", "")

    if not email or not password:
        print(
            "Set SPAM_BOT_EMAIL and SPAM_BOT_PASSWORD.",
            file=sys.stderr,
        )
        return 2

    try:
        token, user_id = spam_bot_login(
            hostname,
            email,
            password,
        )
    except RuntimeError as error:
        print(
            f"Spam bot login failed: {error}",
            file=sys.stderr,
        )
        return 1

    print(
        f"Spam bot login successful. user_id={user_id}"
    )

    for index in range(args.count):
        message = (
            f"Spam Bot Demo Complaint {index + 1:02d}"
        )

        try:
            status = send_spam_complaint(
                hostname,
                token,
                email,
                user_id,
                message,
            )
        except RuntimeError as error:
            print(
                f"Complaint {index + 1}/{args.count} "
                f"failed: {error}",
                file=sys.stderr,
            )
            return 1

        print(
            f"complaint={index + 1}/{args.count} "
            f"http_status={status}"
        )

        if index + 1 < args.count:
            time.sleep(args.interval)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
