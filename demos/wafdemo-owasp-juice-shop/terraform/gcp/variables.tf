variable "project_id" {
  description = <<-EOT
    ID of the GCP project this module CREATES. Must be globally unique, 6-30
    characters. A deleted project's ID stays reserved for 30 days, so after a
    destroy pick a new one rather than reusing it.
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
  description = "Region for the subnet and the static IP."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone for the VM. Must be inside region."
  type        = string
  default     = "europe-west1-b"
}

variable "app_name" {
  description = "Demo name, used as the prefix for every resource."
  type        = string
}

variable "hostname" {
  description = "Public hostname Cloudflare will serve, e.g. \"demo.example.com\". Goes into the origin certificate and the nginx redirect."
  type        = string
}

variable "operator" {
  description = <<-EOT
    IAM member who SSHes into the VM, e.g. "user:someone@example.com".
    Gets IAP tunnel access and OS Login admin on the project, and
    serviceAccountUser on the VM's service account.
  EOT
  type        = string
}

variable "machine_type" {
  description = <<-EOT
    e2-small (2 shared vCPU, 2 GB) is the smallest size that runs the first-boot
    upgrade and Juice Shop comfortably. e2-micro (1 GB) runs Juice Shop but can
    run out of memory during the upgrade.
  EOT
  type        = string
  default     = "e2-small"
}

variable "image" {
  description = "Boot image or image family."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "disk_size_gb" {
  description = "Boot disk size. 10 GB is the Ubuntu image minimum and enough for both containers."
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "subnet_cidr" {
  description = "Primary range of the demo subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "juice_shop_image" {
  description = "Juice Shop image. Fully qualified, because Podman does not assume docker.io. Pin a version tag for a repeatable demo."
  type        = string
  default     = "docker.io/bkimminich/juice-shop:latest"
}

variable "proxy_image" {
  description = "nginx image that publishes Juice Shop on 80 and 443."
  type        = string
  default     = "docker.io/library/nginx:stable-alpine"
}

variable "lock_origin_to_cloudflare" {
  description = <<-EOT
    When true, ports 80 and 443 accept only Cloudflare's published IPv4 ranges,
    fetched live at plan time. Leave false until Cloudflare is in front and
    working, so the origin can be tested directly by IP first.

    This is what stops visitors from reaching the origin directly and skipping
    the WAF. Turn it on before the demo.
  EOT
  type        = bool
  default     = false
}

variable "web_source_ranges" {
  description = "Ranges allowed on 80 and 443 while lock_origin_to_cloudflare is false."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
