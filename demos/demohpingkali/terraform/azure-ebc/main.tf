# =============================================================================
# Static/attack page on a public AKS cluster, with Istio — Azure port
#
#   Two dedicated resource groups, both created here:
#     rg-...-deathstar-principal  — cluster object, VNet, subnet, NSG
#     rg-...-deathstar-secondary  — the AKS node RG (VMSS, node IPs, LB), which
#                                   Azure forces to be a group of its own
#   Dedicated VNet and node subnet; nothing sits on an existing network
#   AKS: public API server, one autoscaled node pool of Arm (Cobalt) nodes
#   Every node gets its own public IP (for inbound NodePort and for egress)
#   Azure CNI Overlay: pod IPs live off the VNet, SNAT'd to the node on the way
#   out — so with one public IP per node, each pod egresses from its node's IP
#   Istio (sidecar mode) with STRICT mTLS inside the app namespace
#   Ingress gateway published as a NodePort on every node's public IP
#
#   In:   Internet ─► <node public IP>:30080 ─► Istio ingress gateway
#                  ─► (mTLS) ─► workload, spread one-ish per node
#   Out:  pod ─► overlay SNAT to its node ─► node's public IP ─► Internet
#
# Files: main.tf (RG, network, shields), aks.tf (cluster, nodes), istio.tf
# (mesh, gateway), app.tf (the workload), descheduler.tf (rebalancing).
# The workload itself is the shared Helm chart in ../../chart, reused unchanged.
#
# Naming: <obj>-pt-cybersec-coe-<star-wars>, <obj> the Azure CAF abbreviation
# (vnet, snet, nsg, aks). The whole thing is the Death Star.
# =============================================================================

locals {
  # The Arm VM sizes carry a `p` right after the vCPU count (Dpsv5, Dpdsv6,
  # Epsv5, ...); x86 ones do not. AKS does NOT auto-taint Arm nodes the way GKE
  # does, so placement is by nodeSelector alone — the toleration below is a
  # harmless no-op kept for parity and in case a taint is ever added. Add a
  # pattern here only if a future size breaks the `<family><cores>p` shape.
  node_arch = can(regex("^Standard_[A-Z]+[0-9]+p", var.machine_type)) ? "arm64" : "amd64"

  pod_placement = {
    nodeSelector = { "kubernetes.io/arch" = local.node_arch }
    tolerations = [{
      key      = "kubernetes.io/arch"
      operator = "Equal"
      value    = "arm64"
      effect   = "NoSchedule"
    }]
  }
}

# ── Resource group (created) ─────────────────────────────────────────────────
# The principal group: the cluster object, VNet, subnet and NSG go in here.
# Created by this module (subscription-scope Contributor is enough), and deleted
# on destroy with everything in it — a throwaway demo group. The cluster's node
# infrastructure is the one thing Azure forces into a SECOND group of its own —
# see node_resource_group in aks.tf.
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    demo = var.app_name
  }
}

# ── Network ──────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_cidr

  tags = {
    demo = var.app_name
  }
}

resource "azurerm_subnet" "this" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

# ── Shields (NSG on the node subnet) ─────────────────────────────────────────
# The only ingress opened by hand. The NSG's default rules already allow
# intra-VNet and Azure Load Balancer traffic and deny the rest of the internet
# inbound; this adds the two NodePorts on top, so the page answers on every
# node's public IP. AKS manages its own load-balancer rules separately and is
# unaffected.
resource "azurerm_network_security_group" "this" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "allow-nodeports"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = [tostring(var.node_port_http), tostring(var.node_port_https)]
    source_address_prefixes    = var.nodeport_source_ranges
    destination_address_prefix = "*"
  }

  tags = {
    demo = var.app_name
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}
