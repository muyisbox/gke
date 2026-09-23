# Compute Classes

GKE custom ComputeClasses control what the node autoscaler *builds* when a Pod
cannot be scheduled. Without them, node auto-provisioning infers a machine shape
from Pod requests and you find out what it picked by reading node names. With
them, the fallback order is a reviewable file.

Defined in `variables.tf` (`compute_classes`), rendered by `compute-classes.tf`,
applied to every cluster this repo manages.

## The classes

| Class | Capacity | Consolidation | Use for |
| --- | --- | --- | --- |
| `default` | On-demand `e2` → `n2` → `n2d`, ≥2 cores | 70% after 10 min | Everything, automatically |
| `cost-optimized` | Spot `n2d` → `n2` → `e2`, then **on-demand `e2`** | 60% after 5 min | Stateless, restart-tolerant work |
| `platform-critical` | On-demand `n2` → `n2d` → `e2`, ≥4 cores / 16 GB | 50% after 30 min | Stateful add-ons holding PVCs |

Each list is a fallback chain: GKE tries rule 1, and only moves down when it
cannot get that shape. `cost-optimized` ends on an on-demand rule on purpose —
without it, a spot shortage leaves Pods pending indefinitely.

Every class sets `whenUnsatisfiable: ScaleUpAnyway`. The GKE default for this
field varies by version, so leaving it unset means the behaviour can change
under you on a control-plane upgrade.

## How a workload opts in

`default` needs no opt-in. The cluster sets `enable_default_compute_class`, so
GKE applies the ComputeClass named `default` to every Pod that doesn't ask for
another one.

Per Pod:

```yaml
spec:
  nodeSelector:
    cloud.google.com/compute-class: cost-optimized
```

Per namespace — every Pod in it, unless the Pod selects something else:

```bash
kubectl label namespace logging cloud.google.com/default-compute-class=platform-critical
```

In an app definition under `gke-applications/<env>/`, put the selector in the
chart's values, for example:

```yaml
helm:
  values:
    nodeSelector:
      cloud.google.com/compute-class: platform-critical
```

The key name varies by chart — check the chart's values before assuming
`nodeSelector` sits at the top level.

## Spot caveat

`cost-optimized` provisions Spot VMs, which Compute Engine reclaims with ~30
seconds of notice. GKE taints Spot nodes, so a workload targeting this class
generally also needs:

```yaml
tolerations:
  - key: cloud.google.com/gke-spot
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Verify on a live cluster (`kubectl describe node`) before moving anything real
onto it — whether the taint is applied to nodes auto-created through a
ComputeClass priority rule is not stated in the GKE docs.

`activeMigration.optimizeRulePriority` is on for this class, so Pods are moved
back onto spot capacity when it returns. It is deliberately **off** for
`platform-critical`: active migration replaces the node, and Pods holding
zonal PVCs do not benefit from being shuffled.

## Changing or adding a class

Edit `compute_classes` in `variables.tf`, or override it in
`values.auto.tfvars`. Setting it to `{}` removes every class and hands scaling
decisions back to plain node auto-provisioning.

Validation rejects an unknown `when_unsatisfiable`, an empty `priorities` list,
a rule with neither `machine_family` nor `machine_type`, and out-of-range
consolidation values — all at plan time.

## Requirements

Custom ComputeClasses need GKE 1.30.3-gke.1451000+ with node auto-provisioning
enabled. This cluster runs the REGULAR channel (1.35.x) with NAP on, so the
whole feature set is available. GKE installs and manages the CRD itself;
Terraform only applies the custom resources.
