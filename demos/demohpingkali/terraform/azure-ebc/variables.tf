# =============================================================================
# Variables for the Azure/AKS port of the demo.
#
# This module CREATES two resource groups in the lab subscription: a principal
# one (resource_group_name) for the cluster object, VNet, subnet and NSG, and a
# second one (node_resource_group) that AKS forces to be separate for its own
# node infrastructure (VMSS, node public IPs, the outbound load balancer).
# =============================================================================

variable "subscription_id" {
  description = <<-EOT
    Subscription the resource groups are created in — coe-lab-main-subscription.
    Required by the v4 azurerm provider. Find it with
    `az account show --query id -o tsv`. Supply through terraform.tfvars or
    TF_VAR_subscription_id.
  EOT
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Principal resource group this module CREATES — the cluster object, the VNet,
    the subnet and the NSG go in here. A throwaway demo group: destroy deletes
    it and everything in it. Creating it needs only subscription-scope
    Contributor. AKS's own node infrastructure lands in node_resource_group, a
    SECOND group Azure forces to be separate.
  EOT
  type        = string
  default     = "rg-pt-cybersec-coe-deathstar-principal"
}

variable "location" {
  description = <<-EOT
    Azure region of every resource and of the two resource groups this module
    creates. "westeurope" is the Azure equivalent of the "eu-west" the demo
    targets first. Switch this (and re-check ARM capacity) if Dpsv6 is short in
    West Europe.
  EOT
  type        = string
  default     = "westeurope"
}

# ── Names (OBJ-pt-cybersec-coe-<star-wars>, OBJ = Azure CAF object abbrev) ────
variable "vnet_name" {
  description = "Dedicated virtual network. Not peered to anything, so its ranges are private to this demo."
  type        = string
  default     = "vnet-pt-cybersec-coe-deathstar"
}

variable "subnet_name" {
  description = "Node subnet inside the VNet — the way in."
  type        = string
  default     = "snet-pt-cybersec-coe-trenchrun"
}

variable "nsg_name" {
  description = "Network security group on the node subnet — the station's shields. Opens only the NodePorts."
  type        = string
  default     = "nsg-pt-cybersec-coe-shields"
}

variable "aks_name" {
  description = "The AKS cluster object. Lives in resource_group_name; its nodes live in node_resource_group."
  type        = string
  default     = "aks-pt-cybersec-coe-deathstar"
}

variable "dns_prefix" {
  description = "DNS prefix for the cluster's public API server FQDN. Lowercase alphanumeric and hyphens."
  type        = string
  default     = "deathstar"
}

variable "node_pool_name" {
  description = <<-EOT
    Name of the single (system) node pool — the troopers that carry the
    workload. AKS caps Linux pool names at 12 lowercase-alphanumeric characters,
    starting with a letter.
  EOT
  type        = string
  default     = "trooper"
}

variable "node_resource_group" {
  description = <<-EOT
    The secondary resource group AKS creates for the cluster's own
    infrastructure (VMSS, node public IPs, the outbound load balancer). Azure
    forces this to be a resource group of its own, separate from
    resource_group_name — it cannot share the group the cluster object lives in.
    AKS creates it (your subscription-scope Contributor covers that); it must not
    already exist. Set to null to let AKS fall back to MC_<rg>_<cluster>_<location>.
  EOT
  type        = string
  default     = "rg-pt-cybersec-coe-deathstar-secondary"
}

variable "app_name" {
  description = <<-EOT
    Value of the `demo` tag on every resource, and the logical name of the
    workload. Kept as "demohpingkali" so this port tags and reads the same as
    the GCP module; the Helm release itself is named "hping" in app.tf.
  EOT
  type        = string
  default     = "demohpingkali"
}

# ── Cluster ──────────────────────────────────────────────────────────────────
variable "sku_tier" {
  description = "AKS control-plane tier. Free has no uptime SLA, which a throwaway demo does not need. Standard adds one."
  type        = string
  default     = "Free"
}

variable "kubernetes_version" {
  description = <<-EOT
    Control-plane Kubernetes version. Null tracks the region's AKS default.
    Istio's support matrix follows the current stable minors, so the default is
    usually fine. List what a region offers with:
      az aks get-versions --location <location> -o table
  EOT
  type        = string
  default     = null
}

# ── Nodes ────────────────────────────────────────────────────────────────────
variable "machine_type" {
  description = <<-EOT
    Node VM size. No default here: terraform.tfvars is the one place it is set.
    tfvars uses Standard_D2pds_v6 — Azure Cobalt 100 (Arm Neoverse N2), 2 vCPU
    and 8 GiB, the closest current-generation Arm analogue to the GCP module's
    c4a-standard-2 (Google Axion, 2 vCPU / 8 GiB).

    The whole workload ships arm64 images (the Kali/Vegeta image, Istio, the
    descheduler), and main.tf pins every pod to whatever architecture this size
    is, so an x86 size (e.g. Standard_D2s_v5) also works unchanged.

    If West Europe is short on Dpsv6, the proven fallback is the previous Arm
    generation, Standard_D2ps_v5 / Standard_D2pds_v5 (Ampere Altra, 2 vCPU /
    8 GiB), which is very widely available. Arm VM families often start at a
    ZERO regional quota on a fresh subscription — check and request before
    counting on max_nodes (see quota_check_command in outputs.tf).
  EOT
  type        = string
}

variable "os_disk_size_gb" {
  description = "Managed OS disk per node. AKS floor is 30 GB; nothing here needs more."
  type        = number
  default     = 30
}

variable "os_disk_type" {
  description = <<-EOT
    "Managed" (a separate managed disk) or "Ephemeral" (the VM's local/cache
    disk, cheaper and faster but wiped on dealloc). Managed by default so the
    size is not tied to the VM's cache size; Ephemeral needs a size that fits
    the SKU's cache.
  EOT
  type        = string
  default     = "Managed"
}

variable "min_nodes" {
  description = <<-EOT
    Fewest nodes the cluster autoscaler keeps. The real floor is usually
    hping_min_replicas, since the hostname spread wants a node per pod.
  EOT
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = <<-EOT
    Most nodes the autoscaler may add, and the cost cap. Two quotas bound this
    in a fresh subscription: the Arm VM family's regional vCPU quota (often 0
    until requested — each node is 2 vCPU) and the region's Standard public-IP
    quota (each node takes one). Raise both before counting on a large count.
  EOT
  type        = number
  default     = 20
}

variable "zones" {
  description = <<-EOT
    Availability zones for the node pool. Null lets Azure place nodes without
    zone pinning, which avoids zonal Arm stockouts. Set e.g. ["1","2","3"] for
    zone redundancy once capacity is confirmed.
  EOT
  type        = list(string)
  default     = null
}

# ── Network ──────────────────────────────────────────────────────────────────
variable "vnet_cidr" {
  description = "Address space of the dedicated VNet. Isolated (no peering), so it only has to avoid the pod and service CIDRs below."
  type        = list(string)
  default     = ["10.30.0.0/16"]
}

variable "subnet_cidr" {
  description = "Node subnet. Overlay keeps pod IPs off the subnet, so a /24 is far more than max_nodes needs."
  type        = string
  default     = "10.30.0.0/24"
}

variable "pods_cidr" {
  description = <<-EOT
    Pod CIDR for Azure CNI Overlay. Overlay pods are NOT addresses on the VNet,
    so this only has to avoid the VNet and service ranges. A /16 covers the
    cluster many times over.
  EOT
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "ClusterIP service range. Must not overlap the VNet or pod CIDRs."
  type        = string
  default     = "10.31.0.0/16"
}

variable "dns_service_ip" {
  description = "In-cluster DNS service address. Must sit inside services_cidr."
  type        = string
  default     = "10.31.0.10"
}

variable "node_port_http" {
  description = "NodePort of the Istio ingress gateway's HTTP listener. Opened on every node's public IP by the NSG."
  type        = number
  default     = 30080
}

variable "node_port_https" {
  description = <<-EOT
    NodePort reserved for the gateway's HTTPS listener. Nothing answers on it
    until a TLS server is added to the Gateway — the slot exists so that adding
    TLS, or mTLS towards Cloudflare, needs no NSG change.
  EOT
  type        = number
  default     = 30443
}

variable "nodeport_source_ranges" {
  description = <<-EOT
    Who may reach the NodePorts. Open by default so the page can be tested
    straight from a laptop. Narrow it to Cloudflare's published ranges once
    Cloudflare is in front. NSG prefixes: CIDRs, or a tag like "Internet".
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
    CronJob schedule, so the time zone is the CronJob's — UTC on AKS; adjust the
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
    The workload image. Fully qualified, so nothing depends on a registry
    default. Carries an arm64 build so it runs on the Arm nodes. Pin a version
    tag for a repeatable demo.
  EOT
  type        = string
  default     = "docker.io/dbenicio/kali-custom:latest"
}

variable "hping_command" {
  description = <<-EOT
    Overrides the container's entrypoint; the image's CMD is dropped with it.
    The chart leaves out the HTTP probes while this is set, since nothing
    listens on port 80. Set [] to run the image's own entrypoint.
  EOT
  type        = list(string)
  default     = ["bash", "-c", "echo \"GET https://$tango:$papa/#/search\" | vegeta attack -rate=50 -duration=10m | vegeta report"]
}

variable "hping_min_replicas" {
  description = <<-EOT
    Fewest workload pods, and the effective node floor (the hostname spread
    wants a node per pod). One matches a cluster that starts on one node; two
    keeps the page up through a node loss.

    This is the manual scaling lever: raise it and the cluster autoscaler adds
    nodes to fit the new pods. Keep it in terraform.tfvars rather than passing
    -var, or the next apply without the flag puts it back.
  EOT
  type        = number
  default     = 1
}

variable "hping_max_replicas" {
  description = "Most workload pods. Anything above max_nodes stays Pending once the nodes are full."
  type        = number
  default     = 20
}

variable "hping_cpu_target" {
  description = "Average CPU utilisation, as a percentage of the pod's request, at which the workload scales out."
  type        = number
  default     = 60
}

variable "hping_env_papa" {
  description = <<-EOT
    Value of the "papa" environment variable in the container, set through the
    <release>-env ConfigMap. A string, because ConfigMap values are strings; a
    changed value rolls the pods (checksum/env annotation).
  EOT
  type        = string
  default     = "443"
}

variable "hping_env_tango" {
  description = <<-EOT
    Value of the "tango" environment variable in the container, set through the
    <release>-env ConfigMap. A string, because ConfigMap values are strings; a
    changed value rolls the pods (checksum/env annotation).
  EOT
  type        = string
  default     = "app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com"
}
