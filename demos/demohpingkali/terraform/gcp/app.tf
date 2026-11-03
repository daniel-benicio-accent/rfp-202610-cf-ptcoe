# =============================================================================
# The page: hping:alpine serving its default page, one pod per node
#
# Everything in-cluster for the app — Deployment, Service, HPA, PDB, and the
# Istio Gateway, VirtualService and PeerAuthentication — is the Helm chart in
# ../../chart, so it can be read and changed as plain Kubernetes YAML.
# =============================================================================

locals {
  app_namespace = "web"
  chart_dir     = "${path.module}/../../chart"

  # Helm only upgrades a release when its inputs change, and the files of a
  # local chart are not inputs. Hashing them into the values makes an edit to
  # the chart show up in the plan.
  chart_hash = sha1(join("", [
    for f in sort(fileset(local.chart_dir, "**")) : filesha1("${local.chart_dir}/${f}")
  ]))
}

resource "helm_release" "hping" {
  name             = "hping"
  chart            = local.chart_dir
  namespace        = local.app_namespace
  create_namespace = true

  # pod_placement (main.tf) pins hping to the node architecture and tolerates
  # the Arm taint, the same as the Istio charts.
  values = [yamlencode(merge(local.pod_placement, {
    image   = var.hping_image
    command = var.hping_command

    replicas = {
      min              = var.hping_min_replicas
      max              = var.hping_max_replicas
      cpuTargetPercent = var.hping_cpu_target
    }

    # Environment of the hping container, through the <release>-env ConfigMap.
    env = {
      papa  = var.hping_env_papa
      tango = var.hping_env_tango
    }

    chartHash = local.chart_hash
  }))]

  # The pods must be created after istiod's injection webhook is up, or they
  # start without a sidecar and STRICT mTLS refuses the gateway's traffic.
  depends_on = [
    helm_release.istiod,
    helm_release.ingress_gateway,
  ]
}
