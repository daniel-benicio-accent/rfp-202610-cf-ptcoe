# =============================================================================
# Origin infrastructure: OWASP Juice Shop on a single GCE VM
#
#   New project, billing linked
#   Dedicated VPC and subnet; the VM never sits on a default network
#   Ubuntu 24.04 VM with a static public IP, running Juice Shop in Podman
#   behind nginx (see ../../bootstrap/startup-script.sh.tftpl)
#   SSH through IAP and OS Login only: port 22 is never open to the internet
#
# The VM is disposable. Everything it runs comes from the startup script, so
# replacing it is always safe: the static IP is a separate resource and
# survives, and so does the Cloudflare record pointing at it.
# =============================================================================

locals {
  required_apis = [
    "compute.googleapis.com",
    "iap.googleapis.com",
    "oslogin.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  # Google's published source range for IAP TCP forwarding.
  iap_range = "35.235.240.0/20"

  network_tag = "${var.app_name}-origin"
}

# ── Project ──────────────────────────────────────────────────────────────────
resource "google_project" "this" {
  project_id      = var.project_id
  name            = var.app_name
  billing_account = var.billing_account
  org_id          = var.org_id
  folder_id       = var.folder_id

  auto_create_network = false

  # The provider defaults to PREVENT, which makes `tofu destroy` fail on the
  # project. This is a throwaway demo, so destroy means delete.
  deletion_policy = "DELETE"

  labels = {
    demo = var.app_name
  }
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

# Enablement returns before Compute Engine is ready to take requests on a new
# project. Without this wait, the first network or service account call fails
# intermittently with "API has not been used in project ... or it is disabled".
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.apis]
  create_duration = "60s"
}

# ── VM service account ───────────────────────────────────────────────────────
# Dedicated and minimal. The default compute service account has Editor on the
# project, which a deliberately vulnerable app has no business holding.
resource "google_service_account" "vm" {
  project      = google_project.this.project_id
  account_id   = "${var.app_name}-vm"
  display_name = "${var.app_name} VM service account"

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_project_iam_member" "vm_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = google_project.this.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# ── Operator access ──────────────────────────────────────────────────────────
# The project creator is Owner already, but these make SSH work for any other
# operator too, and do not depend on Owner being honoured on a fresh project.
resource "google_project_iam_member" "operator" {
  for_each = toset([
    "roles/iap.tunnelResourceAccessor",
    "roles/compute.osAdminLogin",
  ])

  project = google_project.this.project_id
  role    = each.value
  member  = var.operator

  depends_on = [time_sleep.wait_for_apis]
}

# OS Login refuses SSH to a VM that runs as a service account unless the user
# may act as that account. Resource-scoped, for the same reason as above.
resource "google_service_account_iam_member" "operator_sa_user" {
  service_account_id = google_service_account.vm.name
  role               = "roles/iam.serviceAccountUser"
  member             = var.operator
}

# ── Network ──────────────────────────────────────────────────────────────────
resource "google_compute_network" "this" {
  project                 = google_project.this.project_id
  name                    = "${var.app_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_compute_subnetwork" "this" {
  project                  = google_project.this.project_id
  name                     = "${var.app_name}-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_firewall" "iap_ssh" {
  project       = google_project.this.project_id
  name          = "${var.app_name}-allow-iap-ssh"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = [local.iap_range]
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Cloudflare's IPv4 ranges, fetched only when the lock is on. Live rather than
# hard-coded, because Cloudflare does add ranges and a stale list fails as
# intermittent 522s for some visitors only.
data "http" "cloudflare_ipv4" {
  count = var.lock_origin_to_cloudflare ? 1 : 0
  url   = "https://www.cloudflare.com/ips-v4"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && strcontains(self.response_body, "/")
      error_message = "Could not fetch Cloudflare's IP ranges. Refusing to plan a firewall from an empty list."
    }
  }
}

locals {
  # try() only falls back when the lock is off and the data source has no
  # instance. A failed fetch never gets this far: the postcondition stops it.
  cloudflare_ipv4 = [
    for cidr in split("\n", try(data.http.cloudflare_ipv4[0].response_body, "")) :
    trimspace(cidr) if trimspace(cidr) != ""
  ]

  web_source_ranges = var.lock_origin_to_cloudflare ? local.cloudflare_ipv4 : var.web_source_ranges
}

resource "google_compute_firewall" "web" {
  project       = google_project.this.project_id
  name          = "${var.app_name}-allow-web"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = local.web_source_ranges
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# ── Static public IP ─────────────────────────────────────────────────────────
# Reserved separately from the VM so that replacing the VM keeps the address,
# and the Cloudflare A record stays valid.
resource "google_compute_address" "origin" {
  project      = google_project.this.project_id
  name         = "${var.app_name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [time_sleep.wait_for_apis]
}

# ── VM ───────────────────────────────────────────────────────────────────────
resource "google_compute_instance" "origin" {
  project      = google_project.this.project_id
  name         = "${var.app_name}-vm"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = [local.network_tag]

  # Lets machine_type changes apply with a stop/start instead of failing.
  allow_stopping_for_update = true

  labels = {
    demo = var.app_name
  }

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id

    access_config {
      nat_ip       = google_compute_address.origin.address
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  # metadata_startup_script rather than a startup-script metadata key: any
  # change to the script replaces the VM, so what runs always matches the
  # code. Safe because of the static IP above.
  metadata_startup_script = templatefile("${path.module}/../../bootstrap/startup-script.sh.tftpl", {
    juice_shop_image = var.juice_shop_image
    proxy_image      = var.proxy_image
    hostname         = var.hostname
  })

  depends_on = [
    google_project_iam_member.vm_roles,
    google_compute_firewall.iap_ssh,
    google_compute_firewall.web,
  ]
}
