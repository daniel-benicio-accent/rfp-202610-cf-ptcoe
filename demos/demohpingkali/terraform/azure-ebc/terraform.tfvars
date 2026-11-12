# Azure/AKS port of the demo. Creates two new resource groups in the
# coe-lab-main-subscription: a principal group for the cluster/VNet/NSG, and the
# AKS node group Azure forces to be separate. This file is tracked (.gitignore
# allows demos/**/terraform.tfvars), so it holds no secrets. subscription_id is
# the lab subscription's id — a work identifier, committed like the GCP twin's
# project_id; move it to TF_VAR_subscription_id if you'd rather not track it.
subscription_id = "9f16b5c9-9d52-410e-8934-0c64cb7b1ff4" # coe-lab-main-subscription
location        = "westeurope"

# Death Star / Star Wars names, <obj>-pt-cybersec-coe-<name>.
resource_group_name = "rg-pt-cybersec-coe-deathstar-principal" # created: cluster, VNet, NSG
node_resource_group = "rg-pt-cybersec-coe-deathstar-secondary" # created by AKS: VMSS, node IPs, LB
vnet_name           = "vnet-pt-cybersec-coe-deathstar"
subnet_name         = "snet-pt-cybersec-coe-trenchrun"
nsg_name            = "nsg-pt-cybersec-coe-shields"
aks_name            = "aks-pt-cybersec-coe-deathstar"
dns_prefix          = "deathstar"
node_pool_name      = "trooper"

app_name = "demohpingkali"

# Arm, 2 vCPU / 8 GiB — the Azure analogue of the GCP module's c4a-standard-2.
# Standard_D2pds_v6 is Cobalt 100 (current-gen Arm). If West Europe is short on
# it, fall back to Standard_D2ps_v5 / Standard_D2pds_v5 (Ampere Altra), or move
# region. Arm VM quota is often 0 on a fresh subscription — check first.
machine_type = "Standard_D2pds_v6"
min_nodes    = 1
max_nodes    = 20

# One workload pod per node, so the pod and node bounds move together. Raise
# hping_min_replicas here to scale out by hand: N pods, so N nodes.
hping_min_replicas = 1
hping_max_replicas = 20

# Everything else has a default in variables.tf — Istio version, workload image,
# CPU target, NodePorts and who may reach them, network CIDRs. Override here.
