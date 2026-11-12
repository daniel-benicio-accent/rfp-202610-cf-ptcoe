# =============================================================================
# Istio, open source, sidecar mode, installed from the upstream Helm charts
#
#   istio-base      CRDs and cluster roles
#   istiod          control plane: config, sidecar injection, and the mesh CA
#                   that issues every workload's mTLS certificate
#   ingress gateway the entry point, published as a NodePort
#
# mTLS today: the gateway and every hping pod carry an Envoy proxy, and the
# app namespace is STRICT (see the chart), so gateway-to-hping traffic is
# mutually authenticated and plaintext to the pods is refused.
#
# mTLS later: the gateway is also where client-certificate checks would go —
# for example Cloudflare's Authenticated Origin Pulls — by adding a server
# with tls.mode MUTUAL to the Gateway. The HTTPS NodePort is already open
# for it.
#
# Upstream Istio rather than Google's managed Cloud Service Mesh: it needs no
# fleet registration and moves to any Kubernetes unchanged, which matters
# while the target environment is still open.
# =============================================================================

locals {
  istio_repo = "https://istio-release.storage.googleapis.com/charts"
}

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = local.istio_repo
  chart            = "base"
  version          = var.istio_version
  namespace        = "istio-system"
  create_namespace = true

  depends_on = [google_container_node_pool.web]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = local.istio_repo
  chart      = "istiod"
  version    = var.istio_version
  namespace  = "istio-system"

  # Requests are cut well below the chart defaults throughout this file: they
  # are reservations, not limits, and the first 1-vCPU node has to hold all of
  # them at once. Actual use at this scale is lower still. Limits stay at the
  # chart defaults, so nothing is throttled under load.
  values = [yamlencode(merge(local.pod_placement, {
    # The chart default is 500m CPU and 2 GiB, sized for a large mesh; this
    # one has two deployments.
    resources = {
      requests = {
        cpu    = "50m"
        memory = "256Mi"
      }
    }

    # Every injected sidecar — here, one per hping pod. The default 100m would
    # reserve twice what hping itself asks for.
    global = {
      proxy = {
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
        }
      }
    }
  }))]

  # Sidecar injection is a webhook served by istiod. Anything created before
  # istiod is ready starts without a proxy, and stays that way until restarted.
  wait = true

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "ingress_gateway" {
  name             = "istio-ingressgateway"
  repository       = local.istio_repo
  chart            = "gateway"
  version          = var.istio_version
  namespace        = "istio-ingress"
  create_namespace = true

  values = [yamlencode(merge(local.pod_placement, {
    autoscaling = {
      minReplicas = var.gateway_min_replicas
      maxReplicas = 5
    }

    # Half the chart's 100m. The gateway's HPA works from utilisation of this
    # request, so a smaller one also means it scales out sooner under load.
    resources = {
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }

    # Spread the gateway replicas over different nodes where possible, so
    # losing one node never takes the entry point down with it.
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector     = { matchLabels = { istio = "ingressgateway" } }
    }]

    # The chart only renders this once minReplicas is above 1.
    podDisruptionBudget = {
      maxUnavailable = 1
    }

    # NodePort instead of the chart's LoadBalancer: no cloud load balancer,
    # and the page answers on every node's public IP. externalTrafficPolicy
    # stays at Cluster, so any node answers, whether or not it runs a gateway
    # pod. The trade-off is that the gateway sees a node IP, not the visitor's.
    #
    # Fixed nodePorts, so the firewall rule and anything pointing at the
    # nodes (a Cloudflare origin rule, say) never need to change.
    service = {
      type = "NodePort"
      ports = [
        {
          name       = "status-port"
          port       = 15021
          protocol   = "TCP"
          targetPort = 15021
        },
        {
          name       = "http2"
          port       = 80
          protocol   = "TCP"
          targetPort = 80
          nodePort   = var.node_port_http
        },
        {
          name       = "https"
          port       = 443
          protocol   = "TCP"
          targetPort = 443
          nodePort   = var.node_port_https
        },
      ]
    }
  }))]

  depends_on = [helm_release.istiod]
}
