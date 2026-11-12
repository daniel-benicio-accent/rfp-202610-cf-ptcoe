# =============================================================================
# Descheduler (kubernetes-sigs/descheduler), from its upstream Helm chart
#
# The chart removed the one-pod-per-node anti-affinity, so the HPA's pods may
# now pile onto whichever nodes have room — unevenly after a rollout, or when
# the autoscaler adds a node that the existing pods have not spread onto yet.
# This CronJob runs once a day and does two things, both scoped to the app
# namespace so nothing in kube-system is ever touched:
#
#   Balance  evict app pods that break the Deployment's hard kubernetes.io/
#            hostname spread (maxSkew 1), so they reschedule onto the emptier
#            nodes and the pod count per node stays flat.
#   Recycle  evict app pods older than a threshold, processed oldest-first, so
#            the longest-running pods are cycled out on each run.
#
# Eviction is safe: the DefaultEvictor honours PodDisruptionBudgets, and the app
# PDB allows maxUnavailable 1, so at most one pod moves at a time and the page
# keeps serving; minReplicas 2 (below) stops it ever evicting a workload's only
# pod, so recycling never takes the page to zero. The descheduler's own pod
# carries the system-cluster-critical priority class the chart sets, so it is
# never a candidate for eviction itself.
# =============================================================================

resource "helm_release" "descheduler" {
  name       = "descheduler"
  repository = "https://kubernetes-sigs.github.io/descheduler/"
  chart      = "descheduler"
  version    = var.descheduler_version

  # kube-system already exists on a GKE cluster, so there is nothing to create.
  namespace = "kube-system"

  # pod_placement (main.tf) pins the pod to the node architecture and tolerates
  # the Arm taint, the same as every other chart this module installs. The
  # descheduler image is multi-arch, so it runs on the Axion nodes unchanged.
  values = [yamlencode(merge(local.pod_placement, {
    # CronJob (the chart default), so it runs, acts and exits — no pod sitting
    # on a node between runs. schedule is a cron expression in the CronJob's
    # time zone, which on GKE is UTC.
    kind     = "CronJob"
    schedule = var.descheduler_schedule

    # Far below the chart default of 500m / 256Mi: each run is a short pass over
    # the pod list, and the first node is already carrying the cluster-wide pods.
    resources = {
      requests = {
        cpu    = "20m"
        memory = "64Mi"
      }
      limits = {
        cpu    = "200m"
        memory = "128Mi"
      }
    }

    # Two things, scoped to the app namespace. The chart's default policy also
    # enables RemoveDuplicates and LowNodeUtilization, dropped here as noise for
    # this demo. Replacing deschedulerPolicy swaps the whole map, so
    # DefaultEvictor (the required evictor filter) is listed too.
    deschedulerPolicyAPIVersion = "descheduler/v1alpha2"
    deschedulerPolicy = {
      profiles = [{
        name = "balance-and-recycle"
        pluginConfig = [
          {
            name = "DefaultEvictor"
            # Honours PodDisruptionBudgets by default, so at most one app pod
            # moves at a time. minReplicas 2 keeps it from ever evicting a
            # workload's only pod, so recycling never drops the page to zero.
            args = {
              minReplicas = 2
            }
          },
          {
            # Balance: enforce the Deployment's hard hostname spread by evicting
            # pods off over-full nodes (e.g. after the autoscaler adds one), so
            # they reschedule onto the emptier ones. DoNotSchedule only — the
            # zone spread is ScheduleAnyway and deliberately left alone.
            name = "RemovePodsViolatingTopologySpreadConstraint"
            args = {
              constraints = ["DoNotSchedule"]
              namespaces = {
                include = [local.app_namespace]
              }
            }
          },
          {
            # Recycle: evict app pods older than the threshold, processed
            # oldest-first, so the daily run cycles out the longest-running ones.
            # Scoped to the app namespace — unscoped it would recycle every pod
            # in the cluster past the threshold, kube-system included.
            name = "PodLifeTime"
            args = {
              maxPodLifeTimeSeconds = var.descheduler_max_pod_lifetime_seconds
              namespaces = {
                include = [local.app_namespace]
              }
            }
          },
        ]
        plugins = {
          balance = {
            enabled = ["RemovePodsViolatingTopologySpreadConstraint"]
          }
          deschedule = {
            enabled = ["PodLifeTime"]
          }
        }
      }]
    }
  }))]

  depends_on = [google_container_node_pool.web]
}
