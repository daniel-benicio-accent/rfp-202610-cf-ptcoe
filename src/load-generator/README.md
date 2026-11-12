# Bot Management demo simulator

This is a simple, one-shot container. It sends empty requests sequentially to
one configured demo hostname; it has no concurrency, retries, arbitrary URL,
credentials or submitted form data.

Build from the repository root:

```sh
docker build -t bot-management-demo -f src/load-generator/Dockerfile src/load-generator
```

Set `DEMO_HOSTNAME` to a Cloudflare-proxied hostname you administer and are
authorized to test. The simulator always uses HTTPS and only constructs the
predefined demo paths.

```sh
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo brute-force
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo malicious-scraping
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo spam-bots
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo form-abuse
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo account-takeover
docker run --rm -e DEMO_HOSTNAME=demo.example.com bot-management-demo credential-stuffing
```

Each run defaults to five requests. `--count` is limited to 1-10 and
`--interval` must be at least 0.5 seconds. Login scenarios send an empty POST
to an endpoint that always rejects and never checks or stores credentials.
Contact scenarios also send an empty POST; the application discards its body.

These are safe synthetic demonstrations, not production attack simulations.
Bot scoring does not replace rate limiting, MFA or account-security controls.
