# Workstation prerequisites

What you need installed and authenticated before running anything in this
repository. The recipe is distilled from the CapAct MVP's setup guide, which
lives outside this repository — see
[inherited-from-capact.md](inherited-from-capact.md).

| Requirement | Details |
| --- | --- |
| OS | Windows 10/11 with WSL 2, Ubuntu 24.04 LTS |
| Permissions | `sudo` inside WSL |
| Cloud | A GCP project with billing, and a Cloudflare zone on an Enterprise plan |

## Why OpenTofu rather than Terraform

HashiCorp moved Terraform from MPL 2.0 to the Business Source License at version
1.6, which restricts some commercial use. [OpenTofu](https://opentofu.org/) is
the Linux Foundation fork under MPL 2.0 — a drop-in replacement with the same
HCL, the same providers and a compatible state format. Use `tofu` wherever you
would type `terraform`.

<a id="install-steps"></a>

## Install

```bash
# 1. Base packages
sudo apt update && sudo apt install -y gnupg software-properties-common curl \
  apt-transport-https ca-certificates

# 2. OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash -s -- --install-method deb
tofu --version

# 3. Google Cloud CLI
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
  sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
sudo apt update && sudo apt install -y google-cloud-cli
gcloud --version
```

## Authenticate

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud auth application-default login
```

The last step is not optional. Without Application Default Credentials the
Google provider fails with authentication errors on `tofu plan`.

## Environment variables

Neither of these is ever written to a tracked file.

| Variable | What it is |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Scoped to edit the demo zone |
| `TF_VAR_edge_secret` | The shared secret the edge injects and the origin checks, generated per environment. See `0001` FR-7. |

## Troubleshooting

| Issue | Fix |
| --- | --- |
| `GPG error: NO_PUBKEY` on `apt update` | Re-import the repository key from the install step above |
| `tofu: command not found` | Re-run the install script; check `/usr/bin/tofu` exists |
| `gcloud auth login` does not open a browser | Copy the URL from the terminal into a Windows browser |
| Terraform state compatibility | OpenTofu reads and writes the same state format; no migration needed |
