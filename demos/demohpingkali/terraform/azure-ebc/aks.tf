# =============================================================================
# AKS: public cluster, one autoscaled node pool of Arm nodes, node public IPs
#
# How scaling works, end to end:
#
#   load ─► workload CPU above target ─► HPA adds a pod (app.tf)
#        ─► hostname spread (maxSkew 1) has no room ─► pod Pending
#        ─► cluster autoscaler adds a node, up to max_nodes
#
# and in reverse once the load goes: the HPA removes pods, the autoscaler
# removes the nodes they leave empty. The manual lever is the same chain,
# started by hand: raise hping_min_replicas (see the scale_* outputs).
#
# Egress: each node carries its own public IP (node_public_ip_enabled). Azure
# CNI Overlay SNATs a pod's outbound traffic to its node first; a node that has
# an instance-level public IP then egresses through that IP (an instance public
# IP takes SNAT precedence over the cluster's outbound load balancer). Expected
# result, as on GKE: one public egress IP per node, and those IPs are ephemeral
# — a replaced node comes back with a new one. VERIFY on first apply with
# egress_ip_check_command (outputs.tf); if traffic instead leaves via the
# load balancer's outbound IP, that is where to adjust (outbound_type / a NAT
# gateway).
#
# AKS forces the nodes, their public IPs and the outbound load balancer into a
# node resource group of their own (var.node_resource_group); the cluster
# object itself stays in the principal group (var.resource_group_name).
# =============================================================================

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # The node infrastructure group. Azure will not let it share the cluster
  # object's resource group.
  node_resource_group = var.node_resource_group

  # Public API server by omission: no private_cluster_enabled block, so the
  # control plane has a public endpoint.

  # Dedicated per-cluster managed identity rather than the default. The kubelet
  # identity it creates is AKS's own least-privilege set for nodes — the
  # equivalent of the GCP module's dedicated node service account.
  identity {
    type = "SystemAssigned"
  }

  # The single pool is also the system pool: it carries the cluster-wide add-ons
  # (CoreDNS, metrics-server) as well as istiod, the ingress gateway and the
  # workload. only_critical_addons_enabled is left off on purpose so the
  # workload may run here too.
  default_node_pool {
    name                 = var.node_pool_name
    vm_size              = var.machine_type
    vnet_subnet_id       = azurerm_subnet.this.id
    orchestrator_version = var.kubernetes_version
    zones                = var.zones

    # Each node gets its own public IP — what the NodePort is published on, and
    # what the node (and so its pods, after overlay SNAT) egresses from.
    node_public_ip_enabled = true

    os_disk_size_gb = var.os_disk_size_gb
    os_disk_type    = var.os_disk_type

    auto_scaling_enabled = true
    min_count            = var.min_nodes
    max_count            = var.max_nodes
    node_count           = var.min_nodes

    # Upgrades add a node before draining one, so capacity never dips. (AKS also
    # requires a surge setting on the pool.)
    upgrade_settings {
      max_surge = "1"
    }

    # Lets a vm_size / disk change roll the pool via a temporary one instead of
    # failing the apply. Must itself be a valid (<=12 char) pool name.
    temporary_name_for_rotation = "tmptrooper"

    tags = {
      demo = var.app_name
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    pod_cidr            = var.pods_cidr
    service_cidr        = var.services_cidr
    dns_service_ip      = var.dns_service_ip
  }

  # Scale down sooner than the default profile. In a demo that means the node
  # count visibly follows the load back down within minutes, not tens of them.
  auto_scaler_profile {
    expander                   = "random"
    scale_down_delay_after_add = "2m"
    scale_down_unneeded        = "1m"
  }

  tags = {
    demo = var.app_name
  }

  # The autoscaler owns the node count after creation, so don't let the live
  # count (anywhere between min and max) show up as drift against min_nodes.
  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }
}
