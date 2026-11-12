output "project_id" {
  description = "The project this module created."
  value       = google_project.this.project_id
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "region" {
  description = "Region of the cluster."
  value       = google_container_cluster.this.location
}

output "get_credentials_command" {
  description = "Points kubectl at the cluster. Needs gke-gcloud-auth-plugin."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region=${google_container_cluster.this.location} --project=${google_project.this.project_id}"
}

# Node IPs are not outputs on purpose: nodes come and go with the autoscaler,
# and each new node gets a new ephemeral IP. Ask for the current list instead.
output "node_ips_command" {
  description = "Lists every node with its public IP. Works without kubectl."
  value       = "gcloud compute instances list --project=${google_project.this.project_id} --filter=labels.goog-k8s-cluster-name=${google_container_cluster.this.name} --format='table(name,zone.basename(),networkInterfaces[0].accessConfigs[0].natIP)'"
}

output "page_url" {
  description = "The page, on any node's public IP. Every node answers, including ones without a gateway pod."
  value       = "http://<node-public-ip>:${var.node_port_http}/"
}

output "served_by_command" {
  description = "Shows which hping pod answered each request. Repeat it to see the load spread across pods."
  value       = "curl -s -o /dev/null -D - http://<node-public-ip>:${var.node_port_http}/ | grep -i x-served-by"
}

# Asks a public what-is-my-IP service from inside each hping pod, so the answer
# is the address the internet really sees, after SNAT. wget is busybox's,
# which the Alpine image ships. Should match node_ips_command line for line:
# one pod, one node, one public IP.
output "egress_ip_check_command" {
  description = "Prints each hping pod, its node, and the public IP its outbound traffic leaves from."
  value       = "for p in $(kubectl -n ${local.app_namespace} get pods -l app=hping -o name); do echo \"$p $(kubectl -n ${local.app_namespace} get $p -o jsonpath='{.spec.nodeName}') $(kubectl -n ${local.app_namespace} exec $p -c hping -- wget -qO- http://checkip.amazonaws.com)\"; done"
}

output "quota_check_command" {
  description = "In-use external IP and CPU quotas for the region. Each node needs one external IP, so these cap the node count below max_nodes in a new project."
  value       = "gcloud compute regions describe ${var.region} --project=${google_project.this.project_id} --flatten=quotas --format='table(quotas.metric,quotas.usage,quotas.limit)' | grep -E '^(METRIC|IN_USE_ADDRESSES|CPUS) '"
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
  description = "Watch pods land one per node while scaling."
  value       = "kubectl -n ${local.app_namespace} get hpa,pods -o wide --watch"
}
