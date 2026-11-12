variable "project_id" {
  description = <<-EOT
    ID of the GCP project this module CREATES. Must be globally unique, 6-30
    characters, starting with a letter. A deleted project's ID stays reserved
    for 30 days, so after a destroy pick a new one rather than reusing it.
  EOT
  type        = string
}

variable "billing_account" {
  description = <<-EOT
    Billing account the new project is linked to, e.g. "0X0X0X-0X0X0X-0X0X0X".
    Supplied through TF_VAR_billing_account; find it with
    `gcloud billing accounts list`.
  EOT
  type        = string
}

variable "org_id" {
  description = "Organization to create the project under. Set this or folder_id, never both; leave both null for an account with no organization."
  type        = string
  default     = null
}

variable "folder_id" {
  description = "Folder to create the project under. Set this or org_id, never both."
  type        = string
  default     = null
}

variable "region" {
  description = <<-EOT
    Region of the cluster. The control plane is replicated over its zones; the
    nodes run in node_zones. us-east1 by default: on 2 Nov 2026 europe-west1
    failed cluster creation twice with GCE_STOCKOUT, before any node was
    requested.
  EOT
  type        = string
  default     = "us-east1"
}

variable "node_zones" {
  description = <<-EOT
    Zones the nodes run in, all inside region. GKE starts a node pool with one
    node in EACH zone listed, so a single zone is what makes the cluster come
    up with exactly one node. Listing more zones buys zone redundancy at the
    cost of starting with one node per zone.
  EOT
  type        = list(string)
  default     = ["us-east1-b"]
}

variable "app_name" {
  description = <<-EOT
    Prefix for every resource. Must start with a letter and stay within 24
    characters, because the node service account ID is "<app_name>-nodes" and
    GCP caps those at 30.
  EOT
  type        = string
}

variable "release_channel" {
  description = "GKE release channel. REGULAR is what Istio's support matrix tracks most closely."
  type        = string
  default     = "REGULAR"
}

# ── Nodes ────────────────────────────────────────────────────────────────────
variable "machine_type" {
  description = <<-EOT
    Node size. No default here: terraform.tfvars is the one place it is set,
    and the wizard always writes it there. The wizard suggests Arm,
    c4a-standard-1: Google Axion, one full core and 4 GB. hping:alpine and
    Istio both ship arm64 images, and main.tf pins every pod to whatever
    architecture this machine is, so an x86 type works as well.

    One vCPU is enough because of how this module is sized, not by default.
    The FIRST node carries every cluster-wide pod — kube-dns, metrics-server,
    istiod, the ingress gateway — as well as the per-node agents and hping.
    With the trimmed Istio requests in istio.tf and no Workload Identity, that
    is an estimated 0.75 vCPU of requests against 0.94 allocatable. Every later
    node only holds the agents and one hping pod. If the first node does not
    fit after all, the autoscaler adds a second rather than failing.

    Prices in us-east1, compute only, on 2 Nov 2026 ($/hour):
      c4a-standard-1 0.045   n4a-standard-1 0.039   e2-medium 0.034
    (europe-west1 runs about 10% higher.) n4a is cheaper Axion, offered in
    all three us-east1 zones, but GKE support for it was not confirmed when
    this was written; c4a is the proven one. t2a, the older Arm series, is
    offered in only a few regions.
  EOT
  type        = string
}

variable "disk_size_gb" {
  description = "Boot disk per node. GKE defaults to 100 GB, which nothing here needs."
  type        = number
  default     = 30
}

variable "disk_type" {
  description = <<-EOT
    Boot disk type. Null picks the one the machine family can boot from:
    hyperdisk-balanced for fourth-generation series (C4A, N4A, C4, N4), which
    support no Persistent Disk, and pd-balanced for E2, T2A and older, which
    support no Hyperdisk boot. See local.boot_disk_type in main.tf.
  EOT
  type        = string
  default     = null
}

variable "min_nodes" {
  description = <<-EOT
    Fewest nodes in the pool, counted across all zones. The cluster autoscaler
    never goes below this. The real floor is usually hping_min_replicas, since
    each replica needs a node of its own.
  EOT
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = <<-EOT
    Most nodes in the pool, counted across all zones. Caps both the autoscaler
    and the cost. Every node holds a public IP, so the region's quota of
    in-use external IPs (IN_USE_ADDRESSES) is the real cap. It was 8 in both
    us-east1 and europe-west1 on a new project on 2 Nov 2026, and an upgrade
    surge needs one spare. Request an increase before counting on more than 7.
  EOT
  type        = number
  default     = 20
}

# ── Network ──────────────────────────────────────────────────────────────────
variable "subnet_cidr" {
  description = "Node range. A /24 is far more than 20 nodes need."
  type        = string
  default     = "10.20.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary range for pods. GKE carves a /24 per node out of it, so a /16 covers 256 nodes."
  type        = string
  default     = "10.24.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for ClusterIP services."
  type        = string
  default     = "10.28.0.0/20"
}

variable "node_port_http" {
  description = "NodePort of the Istio ingress gateway's HTTP listener. Open on every node's public IP."
  type        = number
  default     = 30080
}

variable "node_port_https" {
  description = <<-EOT
    NodePort reserved for the gateway's HTTPS listener. Nothing answers on it
    until a TLS server is added to the Gateway — the slot exists so that
    adding TLS, or mTLS towards Cloudflare, needs no firewall change.
  EOT
  type        = number
  default     = 30443
}

variable "nodeport_source_ranges" {
  description = <<-EOT
    Who may reach the NodePorts. Open by default so the page can be tested
    straight from a laptop. Narrow it to Cloudflare's published ranges once
    Cloudflare is in front.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Istio ────────────────────────────────────────────────────────────────────
variable "istio_version" {
  description = <<-EOT
    Version of the base, istiod and gateway charts. Pinned, because the three
    must match. 1.30.7 is the newest release with published Helm charts as of
    1 Nov 2026; 1.31.x is released but its charts are not in the repository.
    List what is available with:
      curl -s https://istio-release.storage.googleapis.com/charts/index.yaml | grep 'version:' | sort -uV
  EOT
  type        = string
  default     = "1.30.7"
}

variable "gateway_min_replicas" {
  description = <<-EOT
    Floor for the ingress gateway's own autoscaler. One, so the first node is
    not asked to hold a second copy it gains nothing from. Set 2 once the
    cluster runs on several nodes and losing one must not take the entry point
    down.
  EOT
  type        = number
  default     = 1
}

# ── Descheduler ──────────────────────────────────────────────────────────────
variable "descheduler_version" {
  description = <<-EOT
    Version of the kubernetes-sigs/descheduler Helm chart. Pinned for a
    repeatable apply. 0.36.0 is the newest published chart as of 4 Nov 2026; the
    chart version tracks the descheduler app version. List what is available
    with:
      helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
      helm search repo descheduler/descheduler --versions
  EOT
  type        = string
  default     = "0.36.0"
}

variable "descheduler_schedule" {
  description = <<-EOT
    Cron schedule for the descheduler run that rebalances pods across nodes and
    recycles the longest-running ones. Daily at midnight by default. It is a
    CronJob schedule, so the time zone is the CronJob's — UTC on GKE; adjust the
    expression if you want midnight in another zone.
  EOT
  type        = string
  default     = "0 0 * * *"
}

variable "descheduler_max_pod_lifetime_seconds" {
  description = <<-EOT
    Age, in seconds, past which the descheduler's daily run evicts an app pod so
    it is recreated — the "kill the longest-running pods" lever. Oldest pods go
    first. 86400 (24h) by default, so the midnight run cycles out any app pod
    that has lived more than a day. The DefaultEvictor respects the app PDB
    (one at a time) and never evicts a workload's only pod (minReplicas 2 in
    descheduler.tf). Applies to the app namespace only.
  EOT
  type        = number
  default     = 86400
}

# ── Application ──────────────────────────────────────────────────────────────
variable "hping_image" {
  description = <<-EOT
    The static page server. "alpine" is hping's newest mainline release on the
    newest Alpine. Fully qualified, so nothing depends on a registry default.
    Pin a version tag (e.g. 1.31.8-alpine) for a repeatable demo.
  EOT
  type        = string
  default     = "docker.io/dbenicio/kali-custom:latest"
}

variable "hping_command" {
  description = <<-EOT
    Overrides the hping container's entrypoint; the image's CMD is dropped
    with it. The default keeps the pod idle, to be entered with kubectl exec.
    The chart leaves out the HTTP probes while this is set, since nothing
    listens on port 80. Set [] to run the image's own entrypoint.
  EOT
  type        = list(string)
  default     = ["bash", "-c", "echo \"GET https://$tango:$papa/#/search\" | vegeta attack -rate=50 -duration=10m | vegeta report"]
}

variable "hping_min_replicas" {
  description = <<-EOT
    Fewest hping pods. Each pod needs its own node, so this is also the
    effective node floor. One matches a cluster that starts on one node; two
    keeps the page up through a node loss.

    This is the manual scaling lever: raise it and the cluster autoscaler adds
    nodes to fit the new pods. Keep it in terraform.tfvars rather than passing
    -var, or the next apply without the flag puts it back.
  EOT
  type        = number
  default     = 1
}

variable "hping_max_replicas" {
  description = "Most hping pods. Anything above max_nodes stays Pending, since a node holds at most one."
  type        = number
  default     = 20
}

variable "hping_cpu_target" {
  description = "Average CPU utilisation, as a percentage of the pod's request, at which hping scales out."
  type        = number
  default     = 60
}

variable "hping_env_papa" {
  description = <<-EOT
    Value of the "papa" environment variable in the hping container, set
    through the <release>-env ConfigMap. A string, because ConfigMap values
    are strings; a changed value rolls the pods (checksum/env annotation).
  EOT
  type        = string
  default     = "443"
}

variable "hping_env_tango" {
  description = <<-EOT
    Value of the "tango" environment variable in the hping container, set
    through the <release>-env ConfigMap. A string, because ConfigMap values
    are strings; a changed value rolls the pods (checksum/env annotation).
  EOT
  type        = string
  default     = "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
}
