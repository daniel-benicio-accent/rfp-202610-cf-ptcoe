output "service_url" {
  description = "Public URL of the Cloud Run service. The Cloudflare record points here."
  value       = google_cloud_run_v2_service.app.uri
}

output "service_account_email" {
  description = "Email of the dedicated service account."
  value       = google_service_account.app.email
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.app_name}"
}

output "log_sink_writer_identity" {
  description = "Writer identity of the audit log sink."
  value       = google_logging_project_sink.audit.writer_identity
}
