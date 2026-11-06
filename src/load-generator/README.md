# Cloudflare Security Demo Simulator

## Project Context

This simulator was developed within the scope of an Accenture RFP as part of a controlled security demonstration and validation exercise.

The source code, configurations, test scenarios, and supporting materials in this repository are intended exclusively for authorized testing within the defined RFP environment and are the property of Accenture.

The simulator must only be executed against explicitly authorized lab or demonstration environments. It is not intended for use against production systems or third-party infrastructure without prior authorization.

## Overview

A bounded synthetic traffic generator for testing security controls in an authorized OWASP Juice Shop environment protected by Cloudflare.

The simulator sends sequential requests to predefined and allowlisted endpoints. It does not support arbitrary targets, concurrency, or automatic retries.

> **Important:** This project is intended exclusively for an authorized lab/demo environment. Do not use production credentials or target systems that you do not own or have explicit authorization to test.

---

## Scenarios

The simulator currently supports the following scenarios:

| Scenario | Purpose | Primary Cloudflare Control |
|---|---|---|
| `brute` | Repeated login attempts against the same test account | Rate Limiting |
| `stuffing` | Synthetic credential stuffing and leaked credential validation | Leaked Credentials Detection |
| `malicious-scraping` | Repeated requests against a public Juice Shop resource | Super Bot Fight Mode / Rate Limiting |
| `spam-bots` | Authenticated repeated complaint submissions | Super Bot Fight Mode / Rate Limiting |

---

## Cloudflare Protection Layers

The lab currently uses several complementary Cloudflare security controls:

```text
Internet
   |
   v
Super Bot Fight Mode
   |
   v
Rate Limiting
   |
   v
Leaked Credentials Detection
   |
   v
WAF / Managed Rules
   |
   v
OWASP Juice Shop
```

Each control addresses a different type of application abuse:

- **Super Bot Fight Mode**: identifies and mitigates automated traffic.
- **Rate Limiting**: limits excessive requests against sensitive endpoints.
- **Leaked Credentials Detection**: identifies authentication attempts using compromised credentials.
- **WAF / Managed Rules**: protects the application against threats such as SQL injection, XSS, and RCE.

The current Cloudflare environment does not include the Enterprise Bot Management add-on. Therefore, Bot Management-specific fields such as `cf.bot_management.score` and `cf.bot_management.detection_ids` should not be assumed to be available.

---

# Configuration

## Authorized Juice Shop target

The Cloudflare-protected Juice Shop lab hostname is:

```text
app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com
```

The simulator also supports local Juice Shop instances through:

```text
localhost
127.0.0.1
host.docker.internal
```

Local Juice Shop instances are expected on port:

```text
3000
```

The default placeholder:

```text
XXXXXX
```

is intentionally rejected until an authorized target is explicitly configured.

---

# Running locally

## Python requirements

Python 3 is required.

Check the installed version:

```sh
python3 --version
```

On Windows, depending on the installation:

```powershell
python --version
```

or:

```powershell
py --version
```

Before running the simulator, validate the Python source:

```sh
python3 -m py_compile bot_simulator.py
```

No output means that the source compiled successfully.

List available scenarios:

```sh
python3 bot_simulator.py --help
```

---

## Configure the Juice Shop hostname

### PowerShell

```powershell
$env:JUICE_SHOP_HOST = "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
```

### Bash

```bash
export JUICE_SHOP_HOST="app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
```

---

# Scenario 1: Brute Force

The brute-force scenario sends repeated authentication attempts to:

```text
POST /rest/user/login
```

using the same dedicated lab account with predefined incorrect passwords.

Example:

```sh
python3 bot_simulator.py brute --count 10 --interval 0.5
```

The scenario is designed primarily to validate Cloudflare Rate Limiting.

Example flow:

```text
Repeated login attempts
        |
        v
POST /rest/user/login
        |
        v
Cloudflare Rate Limiting
        |
        v
Managed Challenge / Block
        |
        v
Request prevented from reaching the origin
```

---

# Scenario 2: Credential Stuffing

The credential-stuffing scenario also targets:

```text
POST /rest/user/login
```

It combines synthetic invalid credentials with Cloudflare test credentials intended for validating Leaked Credentials Detection.

Example:

```sh
python3 bot_simulator.py stuffing --count 10 --interval 0.5
```

The Juice Shop login endpoint should be registered in Cloudflare Web Assets as:

```text
POST /rest/user/login
```

with the managed label:

```text
cf-log-in
```

For the Juice Shop JSON login request:

```json
{
  "email": "example@example.com",
  "password": "example"
}
```

the Leaked Credentials Detection locations correspond to:

```text
Username -> email
Password -> password
```

Do not use genuine leaked credentials for testing.

---

# Scenario 3: Malicious Scraping

The malicious-scraping scenario performs repeated GET requests against a public Juice Shop endpoint:

```text
GET /rest/products/1/reviews
```

Example:

```sh
python3 bot_simulator.py malicious-scraping --count 20 --interval 0.2
```

This scenario has stricter limits:

```text
Maximum requests: 20
Minimum interval: 0.2 seconds
```

The purpose is to generate a bounded sample of automated traffic that can be analyzed through Cloudflare security controls.

Bot classification should not be treated as equivalent to rate limiting. A high number of requests does not necessarily mean that Cloudflare will classify the client as automated.

---

# Scenario 4: Spam Bots

The `spam-bots` scenario authenticates with a dedicated Juice Shop lab account and submits a bounded number of synthetic complaints.

The account credentials must be supplied through environment variables.

Do not hard-code the password in `bot_simulator.py` or commit credentials to Git.

## PowerShell

```powershell
$env:DEMO_HOSTNAME = "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
$env:SPAM_BOT_EMAIL = "LAB_ACCOUNT_EMAIL"
$env:SPAM_BOT_PASSWORD = "LAB_ACCOUNT_PASSWORD"
```

Run the scenario:

```powershell
python3 .\bot_simulator.py spam-bots --count 5 --interval 1
```

The expected flow is:

```text
Dedicated lab account
        |
        v
Authentication
        |
        v
Authentication token
        |
        v
Synthetic complaint submissions
        |
        v
Cloudflare protection
```

For complaint spam, endpoint-specific Rate Limiting should be used as an additional protection because automated HTTP traffic may still be classified by bot detection as likely human.

---

# Request Limits

General simulator limits:

```text
MAX_REQUESTS = 1000
MIN_INTERVAL_SECONDS = 0.1
```

Individual scenarios can enforce stricter limits.

For example:

```text
malicious-scraping:
    Maximum requests = 20
    Minimum interval = 0.2 seconds
```

Start with small request counts when validating a new Cloudflare configuration.

---

# Docker

## Build the image

From the repository root:

```sh
docker build \
  -t bot-management-demo \
  -f src/load-generator/Dockerfile \
  src/load-generator
```

Confirm that the image exists:

```sh
docker images bot-management-demo
```

---

## Run Brute Force in Docker

```sh
docker run --rm \
  -e JUICE_SHOP_HOST=app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
  bot-management-demo \
  brute --count 10 --interval 0.5
```

---

## Run Credential Stuffing in Docker

```sh
docker run --rm \
  -e JUICE_SHOP_HOST=app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
  bot-management-demo \
  stuffing --count 10 --interval 0.5
```

---

## Run Malicious Scraping in Docker

```sh
docker run --rm \
  -e JUICE_SHOP_HOST=app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
  bot-management-demo \
  malicious-scraping --count 20 --interval 0.2
```

---

## Run Spam Bots in Docker

Pass credentials through environment variables instead of storing them in the image:

```sh
docker run --rm \
  -e DEMO_HOSTNAME=app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
  -e SPAM_BOT_EMAIL="$SPAM_BOT_EMAIL" \
  -e SPAM_BOT_PASSWORD="$SPAM_BOT_PASSWORD" \
  bot-management-demo \
  spam-bots --count 5 --interval 1
```

Never include `SPAM_BOT_PASSWORD` in the Dockerfile or source repository.

---

# Running the Container on a VM

The recommended deployment model is:

```text
Docker Image
    |
    v
Authorized VM
    |
    v
Cloudflare-protected Juice Shop
```

The VM must have Docker installed and network connectivity to the authorized Cloudflare-protected hostname.

After transferring or pulling the image to the VM:

```sh
docker run --rm \
  -e JUICE_SHOP_HOST=app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com \
  bot-management-demo \
  brute --count 10 --interval 0.5
```

Secrets required by authenticated scenarios should be provided at runtime through environment variables or an approved secrets-management mechanism. They must not be embedded in the container image.

---

# Validation in Cloudflare

After running a scenario, use Cloudflare Security Analytics / Security Events to inspect the corresponding traffic.

Useful properties include:

```text
HTTP method
Request path
Edge status code
Origin status code
Mitigation
Security service
Bot classification
```

For example, a successfully rate-limited request may show:

```text
Mitigation:
Managed Challenge by Rate limiting rules

Edge status:
429 Too Many Requests

Origin status:
None
```

An origin status of `None` can indicate that Cloudflare mitigated the request at the edge before it reached Juice Shop.

---

# Security Considerations

- Run the simulator only against explicitly authorized environments.
- Use dedicated lab accounts.
- Never use production credentials.
- Never store account passwords in Git.
- Never place secrets directly in the Docker image.
- Use Cloudflare-provided test credentials when validating leaked credential detection.
- Keep request volumes bounded.
- Start with small test samples before increasing request counts.
- Rate Limiting and Bot Detection serve different purposes and should be used together where appropriate.
- WAF, Rate Limiting, Leaked Credentials Detection, and Super Bot Fight Mode provide complementary layers of defense.

This simulator is intended for controlled defensive validation and demonstration purposes.