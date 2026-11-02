output "project_id" {
  description = "The project this module created."
  value       = google_project.this.project_id
}

output "hostname" {
  description = "Public hostname the origin is configured for."
  value       = var.hostname
}

output "public_ip" {
  description = "Static public IP of the VM. The Cloudflare A record points here."
  value       = google_compute_address.origin.address
}

output "instance_name" {
  description = "VM name."
  value       = google_compute_instance.origin.name
}

output "zone" {
  description = "VM zone."
  value       = google_compute_instance.origin.zone
}

output "direct_url" {
  description = "Juice Shop by IP, for checking the origin before Cloudflare is in front. Stops answering once lock_origin_to_cloudflare is true."
  value       = "http://${google_compute_address.origin.address}/"
}

output "ssh_command" {
  description = "SSH through IAP. No public port 22 involved."
  value       = "gcloud compute ssh ${google_compute_instance.origin.name} --project=${google_project.this.project_id} --zone=${google_compute_instance.origin.zone} --tunnel-through-iap"
}

output "bootstrap_log_command" {
  description = "Follow the startup script from your workstation, without SSH."
  value       = "gcloud compute instances get-serial-port-output ${google_compute_instance.origin.name} --project=${google_project.this.project_id} --zone=${google_compute_instance.origin.zone} | grep wafdemo-bootstrap"
}

output "origin_locked_to_cloudflare" {
  description = "Whether 80 and 443 accept only Cloudflare. Read by the waf module's bypass check."
  value       = var.lock_origin_to_cloudflare
}

output "origin_web_source_ranges" {
  description = "Ranges currently allowed on 80 and 443."
  value       = local.web_source_ranges
}
