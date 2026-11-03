# 0005 — DDoS protection — Plan

> `spec.md` for this feature is still a stub. This plan documents the
> `demohpingkali` PoC as it stands today; the **what** in `spec.md` has to be
> filled in and approved before the plan is treated as final.

| Field   | Value |
| ------- | ----- |
| Status  | WIP |
| Updated | 2026-11-02 |

## Approach

DDoS protection is largely on by default at the edge, so the configuration
story is thin — the demo's value is showing protection against traffic from
many distinct source IPs rather than one. The PoC is a public GKE cluster that
acts as the traffic source: a scalable fleet of nodes, each with its own public
IP and one load-generator pod, so scaling the fleet scales the number of
distinct source addresses the target sees.

The source pods run a Kali image rather than the load generator's default
entrypoint. The container's entrypoint is overridden to idle (`sleep infinity`)
so the pod stays up to be entered with `kubectl exec`, and traffic is driven by
hand from inside it during the demo. The image and the entrypoint are both
Terraform variables, so either can be changed per run — see
[Rollout notes](#rollout-notes).

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| Single VM load generator (the shared `freeza-vegeta` generator) | One public IP. A volumetric, many-source demo needs traffic spread over many addresses; one node cannot show that. |
| Managed node pool left at a fixed size | The node count is the lever the demo turns. Driving it from `hping_min_replicas` (one pod per node) makes the source-IP count an explicit, visible knob. |

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| demohpingkali demo | [`demos/demohpingkali/`](../../demos/demohpingkali/) | Rendered PoC: public GKE cluster, Istio mesh, one source pod per node. |
| Terraform (GCP) | [`demos/demohpingkali/terraform/gcp/`](../../demos/demohpingkali/terraform/gcp/) | Project, VPC, cluster, node pool, mesh, and the source Deployment via Helm. |
| Source chart | [`demos/demohpingkali/chart/`](../../demos/demohpingkali/chart/) | The pod: image, overridable entrypoint, one-pod-per-node placement. |

## Stack and dependencies

- GKE Standard, regional control plane, one autoscaled Arm (Axion) node pool.
- Istio in sidecar mode, STRICT mTLS in the app namespace.
- OpenTofu + Helm provider; a local chart rendered into the demo.
- Cloudflare at the edge (the thing under test), reached over the public internet.

## Interfaces and data

- **Scaling input:** `hping_min_replicas` in Terraform — one pod per node, so it
  is also the effective node floor.
- **Source IPs:** each node's `EXTERNAL-IP`; pods SNAT out through their node.
- **Overridable per run:** `hping_image` and `hping_command` in
  [`variables.tf`](../../demos/demohpingkali/terraform/gcp/variables.tf).

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Traffic only against infrastructure the team controls | Must stay inside an authorized demo against the project's own Cloudflare-fronted origin. | Document the target as the demo origin only; never point it at third parties. |
| Entrypoint override leaves no server on port 80 | HTTP probes would restart the pod and the Helm release would time out. | The chart drops the HTTP probes while `hping_command` is set. |

## Test and demo strategy

Scale the fleet, confirm the node count and the distinct public IPs, show the
edge absorbing the traffic, then scale back down. The commands are in the
Rollout notes below.

## Rollout notes

Demo notes for the presenter. This PoC lives in
[`demos/demohpingkali/`](../../demos/demohpingkali/); run the commands from its
Terraform directory:

```bash
cd demos/demohpingkali/terraform/gcp
```

### Scale the node fleet

One pod per node, so `hping_min_replicas` is the node count. Plan into a file,
read the plan, then apply the file, where X is the desired source IP

```bash
tofu plan -var 'hping_min_replicas=X' -out="${PLAN_FILE}"
tofu apply -var 'hping_min_replicas=X' "plan-1793629377.tfplan"
```

- **A saved plan carries its own variables.** The first command bakes
  `hping_min_replicas=X` into `${PLAN_FILE}`; applying that file uses X. The
  `-var` on an `apply` of a saved plan does not re-set anything — to scale to a
  different number, run a fresh `tofu plan -out=...` at that number and apply it.
- **Always pass the variable — a plain apply scales back to one node.**
  `hping_min_replicas` defaults to `1` and `terraform.tfvars` sets it to `1`, so
  the `-var 'hping_min_replicas=X'` scale-up is the only thing holding the fleet
  above one node. Any `tofu plan`/`tofu apply` run **without** that `-var` (a
  bare apply, or a plan built without it) falls back to `1` and resets the fleet
  to a single node. To keep a larger fleet across applies, set
  `hping_min_replicas` in `terraform.tfvars` instead of only passing `-var`.
- **Read the plan before applying.** Scaling up should be node-pool and
  Deployment changes only; anything that destroys the cluster, network or
  project means the variables do not match what is deployed. Stop and check.
- **Scaling is not instant.** A new pod stays `Pending` until the autoscaler
  adds a node, so the source-IP count rises over a minute or two, not at once.

#### Alternative: scale the pods directly from Cloud Shell

Without touching Terraform, adjust the pod count straight from the GCP Cloud
Shell. One pod per node, so this scales the node fleet the same way; it also
stops the application (replicas `0`) and is the way to force the pods to re-read
the `<release>-env` ConfigMap after any change to `papa`/`tango`:

```bash
gcloud config set project rfp-202610-demohpingkali
kubectl scale deploy --replicas=0 hping -n web
kubectl scale deploy --replicas=1 hping -n web
```

- **Scaling to `0` stops the app** and, once the nodes drain, lets the
  autoscaler remove them.
- **Re-reading the ConfigMap:** go to `0` and back so every pod is replaced from
  scratch and comes up with the new `papa`/`tango` — cleaner than a delete during
  the slow one-pod-per-node rollout.
- **The HPA owns the floor.** An HPA scales this Deployment with
  `minReplicas = hping_min_replicas`, so `--replicas=1` only settles at `1` while
  that floor is `1`. If the fleet was scaled up through Terraform, the HPA pulls
  the count back up to the floor within its sync period — raise or lower
  `hping_min_replicas` (above) for a change that sticks. Scaling to `0` is the
  exception: the HPA does not scale a Deployment back up from `0`.

### Raise a Compute Engine quota when scale-up stalls

If the fleet stops growing before it reaches the requested node count, the
cluster autoscaler is almost always blocked on a Compute Engine quota — C4A
vCPUs, in-use external IPs, or Hyperdisk Balanced capacity. Two steps.

**1. Confirm it is a quota, and which one.** Read the autoscaler's events (these
need cluster credentials — see
[Inspect the cluster](#inspect-the-cluster-and-the-source-pods) below to fetch
them):

```bash
kubectl get events -A --sort-by=.lastTimestamp \
  | grep -Ei 'FailedScaleUp|quota|Insufficient'

kubectl -n kube-system describe configmap cluster-autoscaler-status
```

Look for `scale.up.error.quota.exceeded` or a `GCE quota exceeded` line — that
names the quota capping the fleet.

**2. File the increase.**
[`request_gke_quotas.sh`](../../demos/demohpingkali/request_gke_quotas.sh), in
the demo root, files one Cloud Quotas request per quota needed to scale the node
pool to `TARGET_NODES` (default 20). It only requests an increase where the
current limit is below what is required — it never lowers an existing quota, and
re-running it is safe. It needs `gcloud` with the `beta` component, `jq`, and
`roles/cloudquotas.admin`.

```bash
cd demos/demohpingkali

./request_gke_quotas.sh                  # dry run: shows what it would request
DRY_RUN=false ./request_gke_quotas.sh    # submit the requests
./request_gke_quotas.sh status           # granted / pending, once submitted
```

Run the dry run first and read it; submit only once it lists the quotas and
values you expect. Approval is on Google's side, so the fleet scales past the
old limit only after the requests are granted.

### Inspect the cluster and the source pods

```bash
gcloud config set project rfp-202610-demohpingkali

gcloud container clusters get-credentials demohpingkali-gke --region=us-east1
kubectl get nodes -o wide        # the EXTERNAL-IP column is each node's public IP

for p in $(kubectl -n web get pods -l app=hping -o name); do echo $p && kubectl exec -it $p -n web -- sh -c "env | grep -E '^(tango|papa)='"; done
```

- `kubectl get nodes -o wide` lists one `EXTERNAL-IP` per node — the set of
  distinct source addresses the target sees.
- The loop confirms the per-pod environment (`tango`, `papa`) is injected, i.e.
  every source pod came up from the chart's config.

### Change the target or port (`papa` / `tango`)

`papa` and `tango` are the port and target the `hping3` line below reads
(`-p $papa $tango`). They are set from the `hping_env_papa` and
`hping_env_tango` Terraform variables, which land in the `<release>-env`
ConfigMap and reach the container as environment variables.

**Redefining them is not enough on its own — the pods must be destroyed and
recreated.** A container reads its environment once, at start, and the override
keeps the process idle on `sleep infinity`, so a running pod never picks up the
new ConfigMap values. After changing `hping_env_papa`/`hping_env_tango` and
applying, delete the pods so the Deployment recreates them against the updated
ConfigMap:

```bash
kubectl -n web delete pods -l app=hping
```

The replacements schedule back onto the existing nodes (now freed) and come up
with the new `papa`/`tango`. Cleaner still, scale the Deployment to `0` and back
(see [scale the pods directly from Cloud Shell](#alternative-scale-the-pods-directly-from-cloud-shell)),
which avoids the slow one-pod-per-node rollout. Confirm with the inspect loop
above before driving traffic.

### Change the image or the entrypoint during a run

Both the source image and the entrypoint command are Terraform variables in
[`demos/demohpingkali/terraform/gcp/variables.tf`](../../demos/demohpingkali/terraform/gcp/variables.tf):

- `hping_image` — the container image the source pods run.
- `hping_command` — overrides the image's entrypoint. The default
  (`["sleep", "infinity"]`) idles the pod so it can be entered with
  `kubectl exec`; set `[]` to run the image's own entrypoint, which restores the
  HTTP probes.
Real command to make the magic: 
hping3 -S --flood --rand-source -p $papa $tango

Change either in `variables.tf` (or pass `-var`), then re-run the plan/apply
flow above. The chart change rolls the pods on the next apply.
