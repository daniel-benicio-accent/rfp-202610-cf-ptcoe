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
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

MAX_REQUESTS = 1000
MIN_INTERVAL_SECONDS = 0.1

MALICIOUS_SCRAPING_MAX_REQUESTS = 20
MALICIOUS_SCRAPING_MIN_INTERVAL_SECONDS = 0.2

DEFAULT_JUICE_SHOP_HOST = "XXXXXX"

JUICE_SHOP_CLOUDFLARE_HOST = (
    "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
)

JUICE_SHOP_TEST_EMAIL = "t05750647@gmail.com"

# Cloudflare test credentials.
# These are intentionally test values, not real leaked credentials.
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
    query: tuple[tuple[str, str], ...] = ()
    payloads: tuple[tuple[str, str], ...] = ()
    local_juice_shop: bool = False


SCENARIOS = {
    # -----------------------------------------------------------------------
    # Scenario 1 - Brute force
    #
    # Same synthetic test account with several incorrect passwords.
    # -----------------------------------------------------------------------
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
        local_juice_shop=True,
    ),

    # -----------------------------------------------------------------------
    # Scenario 2 - Credential stuffing / leaked credentials
    #
    # Mixes synthetic incorrect credentials with Cloudflare test
    # credentials for Leaked Credentials Detection validation.
    # -----------------------------------------------------------------------
    "stuffing": Scenario(
        method="POST",
        path="/rest/user/login",
        payloads=(
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword01!",
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword02!",
            ),
            (
                CF_TEST_USERNAME,
                CF_TEST_PASSWORD,
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword03!",
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword04!",
            ),
            (
                CF_TEST_USERNAME,
                CF_TEST_PASSWORD,
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword05!",
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword06!",
            ),
            (
                CF_TEST_USERNAME,
                CF_TEST_PASSWORD,
            ),
            (
                JUICE_SHOP_TEST_EMAIL,
                "WrongPassword07!",
            ),
        ),
        local_juice_shop=True,
    ),

    # -----------------------------------------------------------------------
    # Scenario 3 - Bounded scraping simulation
    #
    # Repeated GET requests against a public Juice Shop endpoint.
    # This scenario has stricter request-count and interval limits.
    # -----------------------------------------------------------------------
    "malicious-scraping": Scenario(
        method="GET",
        path="/rest/products/1/reviews",
        local_juice_shop=True,
    ),
}


# ---------------------------------------------------------------------------
# Allowed Juice Shop destinations
# ---------------------------------------------------------------------------

LOCAL_JUICE_SHOP_HOSTS = frozenset(
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

def build_target(
    hostname: str,
    scenario: Scenario,
) -> str:
    """Build the target URL for a predefined scenario."""

    hostname = hostname.strip().lower()

    if scenario.local_juice_shop:
        if hostname == DEFAULT_JUICE_SHOP_HOST.lower():
            raise ValueError(
                "JUICE_SHOP_HOST is still the XXXXX placeholder"
            )

        if hostname not in LOCAL_JUICE_SHOP_HOSTS:
            raise ValueError(
                f"JUICE_SHOP_HOST is not allowed: {hostname}"
            )

        # Local Juice Shop deployments.
        if hostname in {
            "localhost",
            "127.0.0.1",
            "host.docker.internal",
        }:
            return (
                f"http://{hostname}:"
                f"{LOCAL_JUICE_SHOP_PORT}"
                f"{scenario.path}"
            )

        # Explicitly authorized Juice Shop endpoint behind Cloudflare.
        return f"https://{hostname}{scenario.path}"

    if scenario not in SCENARIOS.values():
        raise ValueError(
            "scenario must be one of the predefined scenarios"
        )

    if not HOST_PATTERN.fullmatch(hostname):
        raise ValueError(
            "DEMO_HOSTNAME must be a DNS hostname, not a URL or path"
        )

    query = urlencode(scenario.query)

    target = f"https://{hostname}{scenario.path}"

    if query:
        target = f"{target}?{query}"

    parsed = urlsplit(target)

    if parsed.scheme != "https" or parsed.hostname != hostname:
        raise ValueError(
            "target must use HTTPS and match DEMO_HOSTNAME"
        )

    return target


# ---------------------------------------------------------------------------
# Send request
# ---------------------------------------------------------------------------

def send_one(
    target: str,
    scenario: Scenario,
    index: int,
) -> int:
    """Send one request for a predefined scenario."""

    data = None

    headers = {
        "User-Agent": "NormalUser/1.0",
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

        # Do not print passwords to logs.
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
            else (
                b""
                if scenario.method == "POST"
                else None
            )
        ),
        method=scenario.method,
        headers=headers,
    )

    try:
        with HTTP.open(
            request,
            timeout=10,
        ) as response:
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
# CLI arguments
# ---------------------------------------------------------------------------

def parse_args(argv=None):
    """Parse and validate command-line arguments."""

    parser = argparse.ArgumentParser(
        description=(
            "Send a capped sample of synthetic "
            "requests to the demo."
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
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    """Run the selected bounded simulation."""

    args = parse_args(argv)

    scenario = SCENARIOS[args.scenario]

    if scenario.local_juice_shop:
        hostname = os.environ.get(
            "JUICE_SHOP_HOST",
            DEFAULT_JUICE_SHOP_HOST,
        )

    else:
        hostname = os.environ.get(
            "DEMO_HOSTNAME",
            "",
        )

        if not hostname:
            print(
                "Set DEMO_HOSTNAME to the "
                "authorized Cloudflare demo hostname.",
                file=sys.stderr,
            )
            return 2

    try:
        target = build_target(
            hostname,
            scenario,
        )

    except ValueError as error:
        print(
            f"Configuration error: {error}",
            file=sys.stderr,
        )
        return 2

    print(
        f"scenario={args.scenario} "
        f"requests={args.count} "
        f"interval_seconds={args.interval} "
        f"target={target}"
    )

    for index in range(args.count):
        try:
            status = send_one(
                target,
                scenario,
                index,
            )

        except RuntimeError as error:
            print(
                f"Request {index + 1}/{args.count} "
                f"failed: {error}",
                file=sys.stderr,
            )
            return 1

        print(
            f"request={index + 1}/{args.count} "
            f"http_status={status}"
        )

        if index + 1 < args.count:
            time.sleep(args.interval)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())