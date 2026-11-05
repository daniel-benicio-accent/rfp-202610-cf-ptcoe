# Bot Management demo simulator

This is a simple, one-shot container. It sends sequential requests to fixed
demo routes; it has no concurrency, retries, or arbitrary target. The two
Juice Shop login scenarios use only fictional `.invalid` accounts and passwords.

Build from the repository root:

```sh
docker build -t bot-management-demo -f src/load-generator/Dockerfile src/load-generator
```

For Juice Shop, run it locally on port 3000. The brute-force and credential
stuffing scenarios use only a reserved `.invalid` email domain and synthetic
passwords. The default host is the `XXXXX` placeholder, which is rejected until
you configure a local Juice Shop host. External hosts are not accepted. When
running inside Docker Desktop, use `host.docker.internal` to reach the host:

```sh
docker run --rm -e JUICE_SHOP_HOST=host.docker.internal bot-management-demo brute-force
docker run --rm -e JUICE_SHOP_HOST=host.docker.internal bot-management-demo credential-stuffing
```

Add `--count 10` to run the full set of ten synthetic attempts; the default is
five. Brute force repeats one fictional account with passwords
`WrongPassword01!` through `WrongPassword10!`. Credential stuffing uses ten
different fictional `bot-test-XX@example.invalid` accounts and those same
numbered test passwords. No real mailbox or password is used.

When running the script directly on the same machine as Juice Shop, explicitly
set `JUICE_SHOP_HOST=localhost`.

The other four synthetic scenarios still target the separate demo app. Set
`DEMO_HOSTNAME` to the Cloudflare-proxied demo hostname you administer:

```sh
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo malicious-scraping
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo spam-bots
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo form-abuse
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo account-takeover
```

Each run defaults to five requests. `--count` is limited to 1-10 and
`--interval` must be at least 0.5 seconds. Juice Shop login attempts use
fictional values only; do not replace them with real credentials. The other
synthetic login endpoint always rejects, and contact scenarios discard bodies.

These are safe synthetic demonstrations, not production attack simulations.
Bot scoring does not replace rate limiting, MFA or account-security controls.
