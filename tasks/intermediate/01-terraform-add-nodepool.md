# Task 1: Terraform — Add a New Node Pool to a Cluster

**Level:** Intermediate

**Objective:** Modify the Terraform code to add a second node pool with different machine types and taints for workload isolation.

## Context

The current cluster has a single node pool (`node-pool-01`) with `e2-standard-4` machines and a `PREFER_NO_SCHEDULE` taint. You need to add a dedicated node pool for monitoring workloads.

## Steps

### Part A: Understand the Current Node Pool

1. Open `gke.tf` and study the `node_pools` configuration:
   - What machine type is used?
   - What are the min/max node counts?
   - What taint is applied?

2. Check the running nodes:

   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,TAINTS:.spec.taints
   ```

### Part B: Add a Monitoring Node Pool

3. Create a new branch:

   ```bash
   git checkout -b feature/monitoring-nodepool
   ```

4. In `gke.tf`, add a second node pool to the `node_pools` list:

   ```hcl
   {
     name               = "monitoring-pool"
     machine_type       = "e2-standard-2"
     min_count          = 1
     max_count          = 2
     disk_size_gb       = 50
     disk_type          = "pd-ssd"
     image_type         = "COS_CONTAINERD"
     auto_repair        = true
     auto_upgrade       = true
     initial_node_count = 1
   }
   ```

5. Add a taint to this pool so only monitoring workloads schedule on it. In the `node_pools_taints` block:

   ```hcl
   monitoring-pool = [
     {
       key    = "dedicated"
       value  = "monitoring"
       effect = "NO_SCHEDULE"
     }
   ]
   ```

6. Add labels so workloads can use `nodeSelector`. In `node_pools_labels`:

   ```hcl
   monitoring-pool = {
     dedicated = "monitoring"
   }
   ```

### Part C: Plan and Validate

7. Run a Terraform plan for the dev workspace:

   ```bash
   terraform workspace select dev
   terraform plan -out=nodepool.tfplan
   ```

8. Review the plan:
   - Does it show the new node pool being created?
   - Does it show any existing resources being destroyed? (It should NOT)
   - Are the taints and labels correct?

9. **Do NOT apply** — this is a planning exercise. Discuss with your team before applying.

### Part D: Deploy Workloads to the New Pool

10. To schedule monitoring pods on this pool, you would add to the prometheus-monitoring Helm values:

    ```yaml
    prometheus:
      prometheusSpec:
        nodeSelector:
          dedicated: monitoring
        tolerations:
        - key: "dedicated"
          operator: "Equal"
          value: "monitoring"
          effect: "NoSchedule"
    ```

## Key Concepts

- **Taints** repel pods; **Tolerations** allow pods to schedule on tainted nodes
- `NO_SCHEDULE` = hard restriction; `PREFER_NO_SCHEDULE` = soft preference
- `nodeSelector` ensures pods land on specific nodes
- Adding a node pool is non-destructive — existing workloads are unaffected
- Always plan before apply to verify no unintended changes

## Cleanup

```bash
git checkout master
git branch -d feature/monitoring-nodepool
```
