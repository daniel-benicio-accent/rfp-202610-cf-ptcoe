terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# subscription_id is required by the v4 azurerm provider. It comes from
# terraform.tfvars (or TF_VAR_subscription_id / ARM_SUBSCRIPTION_ID). Everything
# else — tenant, credentials — is taken from the active `az login` session; see
# the account checklist in outputs.tf.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Pointed at the cluster this same module creates, so one apply goes from an
# empty resource group to a serving page. Helm is the only in-cluster provider
# on purpose: the Istio objects (Gateway, VirtualService, PeerAuthentication)
# are CRDs, and the kubernetes provider's manifest resource needs those CRDs to
# exist at plan time, which on a fresh cluster they never do. A Helm chart is
# only rendered at apply time.
#
# kube_config (the local admin kubeconfig) works because AKS keeps its local
# account enabled by default; it would be kube_admin_config if the cluster were
# switched to Entra-only (local_account_disabled).
provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}
