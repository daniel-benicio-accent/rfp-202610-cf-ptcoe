"""Send a bounded sample of synthetic requests to the Cloudflare demo."""

import argparse
import json
import math
import os
import re
import sys
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MAX_REQUESTS = 1000
MIN_INTERVAL_SECONDS = 0.1

MALICIOUS_SCRAPING_MAX_REQUESTS = 20
MALICIOUS_SCRAPING_MIN_INTERVAL_SECONDS = 0.2

SPAM_BOT_MAX_REQUESTS = 20
SPAM_BOT_MIN_INTERVAL_SECONDS = 0.2

DEFAULT_JUICE_SHOP_HOST = "XXXXXX"

JUICE_SHOP_CLOUDFLARE_HOST = (
    "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
)

JUICE_SHOP_TEST_EMAIL = "t05750647@gmail.com"

# Cloudflare test credentials.
# These are test values, not real leaked credentials.
CF_TEST_USERNAME = "CF_EXPOSED_USERNAME@example.com"
CF_TEST_PASSWORD = "CF_EXPOSED_PASSWORD"

HOST_PATTERN = re.compile(
    r"(?=.{1,253}\Z)"
    r"(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\Z"
)


# ---------------------------------------------------------------------------
# Scenario definition
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Scenario:
    method: str
    path: str
    payloads: tuple[tuple[str, str], ...] = ()
    local_juice_shop: bool = True


SCENARIOS = {
    "brute": Scenario(
        method="POST",
        path="/rest/user/login",
        payloads=tuple(
            (
                JUICE_SHOP_TEST_EMAIL,
                f"WrongPassword{index:02d}!",
            )
            for index in range(1, 11)
        ),
    ),

    "stuffing": Scenario(
        method="POST",
        path="/rest/user/login",
        payloads=(
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword01!"),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword02!"),
            (CF_TEST_USERNAME, CF_TEST_PASSWORD),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword03!"),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword04!"),
            (CF_TEST_USERNAME, CF_TEST_PASSWORD),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword05!"),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword06!"),
            (CF_TEST_USERNAME, CF_TEST_PASSWORD),
            (JUICE_SHOP_TEST_EMAIL, "WrongPassword07!"),
        ),
    ),

    "malicious-scraping": Scenario(
        method="GET",
        path="/rest/products/1/reviews",
    ),

    # This scenario has its own login and complaint submission workflow.
    "spam-bots": Scenario(
        method="POST",
        path="/api/Complaints/",
    ),
}


# ---------------------------------------------------------------------------
# Allowed destinations
# ---------------------------------------------------------------------------

ALLOWED_JUICE_SHOP_HOSTS = frozenset(
    {
        "localhost",
        "127.0.0.1",
        "host.docker.internal",
        JUICE_SHOP_CLOUDFLARE_HOST,
    }
)

LOCAL_JUICE_SHOP_PORT = 3000


# ---------------------------------------------------------------------------
# HTTP configuration
# ---------------------------------------------------------------------------

class NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(
        self,
        request,
        response,
        code,
        message,
        headers,
        new_url,
    ):
        return None


HTTP = build_opener(NoRedirectHandler())


# ---------------------------------------------------------------------------
# Target construction
# ---------------------------------------------------------------------------

def validate_hostname(hostname: str) -> str:
    """Validate and normalize the authorized Juice Shop hostname."""

    hostname = hostname.strip().lower()

    if hostname == DEFAULT_JUICE_SHOP_HOST.lower():
        raise ValueError(
            "JUICE_SHOP_HOST is still the XXXXX placeholder"
        )

    if hostname not in ALLOWED_JUICE_SHOP_HOSTS:
        raise ValueError(
            f"JUICE_SHOP_HOST is not allowed: {hostname}"
        )

    if (
        hostname not in {"localhost", "127.0.0.1", "host.docker.internal"}
        and not HOST_PATTERN.fullmatch(hostname)
    ):
        raise ValueError(
            "JUICE_SHOP_HOST must be a valid hostname"
        )

    return hostname


def build_target(hostname: str, path: str) -> str:
    """Build a URL restricted to an explicitly allowed Juice Shop host."""

    hostname = validate_hostname(hostname)

    if hostname in {
        "localhost",
        "127.0.0.1",
        "host.docker.internal",
    }:
        return f"http://{hostname}:{LOCAL_JUICE_SHOP_PORT}{path}"

    return f"https://{hostname}{path}"


# ---------------------------------------------------------------------------
# Generic scenarios
# ---------------------------------------------------------------------------

def send_one(
    target: str,
    scenario: Scenario,
    index: int,
) -> int:
    """Send one request for brute, stuffing, or scraping."""

    data = None

    headers = {
        "User-Agent": "BotManagement-Demo-Simulator/1.0",
        "Accept": "application/json",
    }

    if scenario.payloads:
        email, password = scenario.payloads[
            index % len(scenario.payloads)
        ]

        payload = {
            "email": email,
            "password": password,
        }

        data = json.dumps(
            payload,
            separators=(",", ":"),
        ).encode("utf-8")

        headers["Content-Type"] = "application/json"

        credential_type = (
            "cloudflare-test"
            if email == CF_TEST_USERNAME
            else "synthetic"
        )

        print(
            f"payload_email={email} "
            f"credential_type={credential_type} "
            f"payload_bytes={len(data)}"
        )

    request = Request(
        target,
        data=(
            data
            if data is not None
            else b"" if scenario.method == "POST" else None
        ),
        method=scenario.method,
        headers=headers,
    )

    try:
        with HTTP.open(request, timeout=10) as response:
            return response.status

    except HTTPError as error:
        return error.code

    except URLError as error:
        raise RuntimeError(
            f"request failed: {error.reason}"
        ) from error

    except TimeoutError as error:
        raise RuntimeError(
            "request timed out"
        ) from error


# ---------------------------------------------------------------------------
# Spam bot scenario
# ---------------------------------------------------------------------------

def spam_bot_login(
    hostname: str,
    email: str,
    password: str,
) -> tuple[str, int]:
    """Authenticate the dedicated lab account and return its token and ID."""

    target = build_target(
        hostname,
        "/rest/user/login",
    )

    payload = json.dumps(
        {
            "email": email,
            "password": password,
        },
        separators=(",", ":"),
    ).encode("utf-8")

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
            body = json.loads(
                response.read().decode("utf-8")
            )

    except HTTPError as error:
        raise RuntimeError(
            f"login failed with HTTP {error.code}"
        ) from error

    except URLError as error:
        raise RuntimeError(
            f"login failed: {error.reason}"
        ) from error

    except TimeoutError as error:
        raise RuntimeError(
            "login request timed out"
        ) from error

    except json.JSONDecodeError as error:
        raise RuntimeError(
            "login response was not valid JSON"
        ) from error

    authentication = body.get("authentication", {})

    token_value = authentication.get("token")
    user_id = authentication.get("bid")

    if not isinstance(token_value, str) or not token_value:
        raise RuntimeError(
            "login succeeded but no authentication token was returned"
        )

    if not isinstance(user_id, int):
        raise RuntimeError(
            "login succeeded but no numeric user ID was returned"
        )

    return token_value, user_id


def send_spam_complaint(
    hostname: str,
    token_value: str,
    email: str,
    user_id: int,
    message: str,
) -> int:
    """Submit one synthetic complaint using the dedicated lab account."""

    target = build_target(
        hostname,
        "/api/Complaints/",
    )

    payload = json.dumps(
        {
            "UserId": user_id,
            "message": message,
        },
        separators=(",", ":"),
    ).encode("utf-8")

    request = Request(
        target,
        data=payload,
        method="POST",
        headers={
            "User-Agent": "BotManagement-Demo-Simulator/1.0",
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token_value}",
            "Cookie": f"token={token_value}",
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

    except TimeoutError as error:
        raise RuntimeError(
            "complaint request timed out"
        ) from error


# ---------------------------------------------------------------------------
# CLI arguments
# ---------------------------------------------------------------------------

def parse_args(argv=None):
    """Parse and validate command-line arguments."""

    parser = argparse.ArgumentParser(
        description=(
            "Send a bounded sample of synthetic "
            "requests to the authorized demo."
        )
    )

    parser.add_argument(
        "scenario",
        choices=sorted(SCENARIOS),
        help="Synthetic scenario to execute.",
    )

    parser.add_argument(
        "--count",
        type=int,
        default=5,
        help="Number of requests to send.",
    )

    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Delay between requests in seconds.",
    )

    args = parser.parse_args(argv)

    if args.scenario == "malicious-scraping":
        max_requests = MALICIOUS_SCRAPING_MAX_REQUESTS
        min_interval = MALICIOUS_SCRAPING_MIN_INTERVAL_SECONDS

    elif args.scenario == "spam-bots":
        max_requests = SPAM_BOT_MAX_REQUESTS
        min_interval = SPAM_BOT_MIN_INTERVAL_SECONDS

    else:
        max_requests = MAX_REQUESTS
        min_interval = MIN_INTERVAL_SECONDS

    if not 1 <= args.count <= max_requests:
        parser.error(
            f"--count must be between 1 and {max_requests}"
        )

    if (
        not math.isfinite(args.interval)
        or args.interval < min_interval
    ):
        parser.error(
            f"--interval must be at least "
            f"{min_interval} seconds"
        )

    return args


# ---------------------------------------------------------------------------
# Scenario execution
# ---------------------------------------------------------------------------

def run_generic_scenario(
    hostname: str,
    scenario_name: str,
    scenario: Scenario,
    count: int,
    interval: float,
) -> int:
    """Run brute, stuffing, or scraping."""

    target = build_target(
        hostname,
        scenario.path,
    )

    print(
        f"scenario={scenario_name} "
        f"requests={count} "
        f"interval_seconds={interval} "
        f"target={target}"
    )

    for index in range(count):
        try:
            status = send_one(
                target,
                scenario,
                index,
            )

        except RuntimeError as error:
            print(
                f"Request {index + 1}/{count} failed: {error}",
                file=sys.stderr,
            )
            return 1

        print(
            f"request={index + 1}/{count} "
            f"http_status={status}"
        )

        if index + 1 < count:
            time.sleep(interval)

    return 0


def run_spam_bot_scenario(
    hostname: str,
    count: int,
    interval: float,
) -> int:
    """Run the authenticated, bounded complaint-spam simulation."""

    email = os.environ.get(
        "SPAM_BOT_EMAIL",
        "",
    )

    password = os.environ.get(
        "SPAM_BOT_PASSWORD",
        "",
    )

    if not email or not password:
        print(
            "Set SPAM_BOT_EMAIL and SPAM_BOT_PASSWORD "
            "to a dedicated lab account.",
            file=sys.stderr,
        )
        return 2

    try:
        token_value, user_id = spam_bot_login(
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

    target = build_target(
        hostname,
        "/api/Complaints/",
    )

    print(
        f"scenario=spam-bots "
        f"requests={count} "
        f"interval_seconds={interval} "
        f"target={target} "
        f"user_id={user_id}"
    )

    for index in range(count):
        message = (
            f"Synthetic spam demo complaint "
            f"{index + 1:02d}"
        )

        try:
            status = send_spam_complaint(
                hostname,
                token_value,
                email,
                user_id,
                message,
            )

        except RuntimeError as error:
            print(
                f"Complaint {index + 1}/{count} "
                f"failed: {error}",
                file=sys.stderr,
            )
            return 1

        print(
            f"complaint={index + 1}/{count} "
            f"http_status={status}"
        )

        if index + 1 < count:
            time.sleep(interval)

    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    """Run the selected bounded simulation."""

    args = parse_args(argv)

    hostname = os.environ.get(
        "JUICE_SHOP_HOST",
        DEFAULT_JUICE_SHOP_HOST,
    )

    try:
        hostname = validate_hostname(hostname)

    except ValueError as error:
        print(
            f"Configuration error: {error}",
            file=sys.stderr,
        )
        return 2

    scenario = SCENARIOS[args.scenario]

    if args.scenario == "spam-bots":
        return run_spam_bot_scenario(
            hostname,
            args.count,
            args.interval,
        )

    return run_generic_scenario(
        hostname,
        args.scenario,
        scenario,
        args.count,
        args.interval,
    )


if __name__ == "__main__":
    raise SystemExit(main())