output "resource_group" {
  description = "The principal resource group this module created (cluster object, VNet, NSG)."
  value       = azurerm_resource_group.this.name
}

output "node_resource_group" {
  description = "The node resource group AKS created for the VMSS, node public IPs and outbound load balancer."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "location" {
  description = "Region of the cluster."
  value       = azurerm_kubernetes_cluster.this.location
}

output "get_credentials_command" {
  description = "Points kubectl at the cluster."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing"
}

# Node IPs are not outputs on purpose: nodes come and go with the autoscaler,
# and each new node gets a new ephemeral public IP. Ask for the current list
# instead — with node public IPs enabled, the EXTERNAL-IP column is the node's
# public IP.
output "node_ips_command" {
  description = "Lists every node with its public IP."
  value       = "kubectl get nodes -o wide"
}

output "page_url" {
  description = "The page, on any node's public IP. Every node answers, including ones without a gateway pod."
  value       = "http://<node-public-ip>:${var.node_port_http}/"
}

output "served_by_command" {
  description = "Shows which workload pod answered each request. Repeat it to see the load spread across pods."
  value       = "curl -s -o /dev/null -D - http://<node-public-ip>:${var.node_port_http}/ | grep -i x-served-by"
}

# Asks a public what-is-my-IP service from inside each pod, so the answer is the
# address the internet really sees, after SNAT. Should match node_ips_command
# line for line when egress is per-node: one pod, one node, one public IP. If it
# instead shows the same handful of IPs for every pod, egress is leaving through
# the cluster's outbound load balancer, not the node public IPs — see the egress
# note in aks.tf.
output "egress_ip_check_command" {
  description = "Prints each workload pod, its node, and the public IP its outbound traffic leaves from."
  value       = "for p in $(kubectl -n ${local.app_namespace} get pods -l app=hping -o name); do echo \"$p $(kubectl -n ${local.app_namespace} get $p -o jsonpath='{.spec.nodeName}') $(kubectl -n ${local.app_namespace} exec $p -c hping -- wget -qO- http://checkip.amazonaws.com)\"; done"
}

output "quota_check_command" {
  description = "Regional vCPU usage/limit for the Arm VM family, plus Standard public-IP usage. Each node needs one of each, so these cap the node count below max_nodes in a fresh subscription."
  value       = "az vm list-usage --location ${var.location} --output table | grep -iE 'Name|Dpds|Dps|Total Regional'; echo '---'; az network list-usages --location ${var.location} --output table | grep -iE 'Name|PublicIPAddresses'"
}

output "scale_out_command" {
  description = "Manual scale-out: raise the pod floor to N, and the autoscaler adds nodes until each pod has one. Lasts only until an apply without the flag; set hping_min_replicas in terraform.tfvars to keep it."
  value       = "tofu apply -var hping_min_replicas=N"
}

output "scale_out_kubectl_command" {
  description = "Same as scale_out_command, without a plan. Terraform never sees the patch: undo it with the same command and N = hping_min_replicas, or it stays until an apply that changes the hping release."
  value       = "kubectl -n ${local.app_namespace} patch hpa hping --type=merge -p '{\"spec\":{\"minReplicas\":N}}'"
}

output "watch_command" {
  description = "Watch pods land across nodes while scaling."
  value       = "kubectl -n ${local.app_namespace} get hpa,pods -o wide --watch"
}
