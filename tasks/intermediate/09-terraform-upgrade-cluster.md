# Task 9: Terraform — Upgrade Cluster Configuration

**Level:** Intermediate

**Objective:** Understand how to safely modify cluster settings through Terraform, including machine types, disk sizes, and autoscaling parameters.

## Context

Infrastructure changes must go through Terraform, not manual `gcloud` commands. This task walks through common cluster modifications and how to validate them safely.

## Steps

### Part A: Understand What's Mutable vs Immutable

1. Open `gke.tf` and categorize these settings:

   **Mutable (can change without recreation):**
   - `min_count` / `max_count` (node pool autoscaling)
   - `cluster_autoscaling` settings (CPU/memory limits)
   - Node pool labels
   - Auto-repair / auto-upgrade settings

   **Immutable (change forces recreation):**
   - `machine_type` (node pool recreated)
   - `disk_type` / `disk_size_gb` (node pool recreated)
   - Network/subnet CIDR ranges (cluster recreated!)
   - `master_ipv4_cidr_block` (cluster recreated!)

2. This is critical: changing `node_cidr` or `range_base` in `values.auto.tfvars` will **destroy and recreate the cluster**. Open the file and note the comment about this.

### Part B: Scale the Cluster Autoscaler

3. Create a branch:

   ```bash
   git checkout -b feature/adjust-autoscaling
   ```

4. Open `values.auto.tfvars` and find the `cluster_autoscaling` variable. Modify the CPU and memory limits:

   ```hcl
   cluster_autoscaling = {
     enabled             = true
     autoscaling_profile = "OPTIMIZE_UTILIZATION"
     min_cpu_cores       = 0
     max_cpu_cores       = 64    # Was 48
     min_memory_gb       = 0
     max_memory_gb       = 256   # Was 192
     gpu_resources       = []
     auto_repair         = true
     auto_upgrade        = true
   }
   ```

5. Run a plan and verify:

   ```bash
   terraform workspace select dev
   terraform plan
   ```

   - Does it show an in-place update? (It should — autoscaling limits are mutable)
   - Is anything being destroyed?

### Part C: Change Node Pool Min/Max Count

6. In `gke.tf`, change the node pool `max_count` from 4 to 6:

   ```hcl
   max_count = 6
   ```

7. Plan again:

   ```bash
   terraform plan
   ```

   - This should be an in-place update to the node pool, not a recreation

### Part D: Simulate a Dangerous Change

8. **DO NOT APPLY THIS** — just plan it to see what happens. In `gke.tf`, change the machine type:

   ```hcl
   machine_type = "e2-standard-8"  # Was e2-standard-4
   ```

9. Plan:

   ```bash
   terraform plan
   ```

   Look for:
   - `# module.gke.google_container_node_pool.pools["node-pool-01"] must be replaced`
   - The plan shows destroy then create for the node pool
   - This means **all pods on those nodes will be evicted**

10. Revert the machine type change — in production, you'd add a new node pool with the new type and drain the old one.

### Part E: Check for Release Channel Updates

11. The cluster uses `release_channel = "REGULAR"`. Check what version is running:

    ```bash
    gcloud container clusters describe dev-cluster --zone us-central1-c --project cluster-dreams --format='value(currentMasterVersion)'
    gcloud container clusters describe dev-cluster --zone us-central1-c --project cluster-dreams --format='value(currentNodeVersion)'
    ```

12. Check available versions:

    ```bash
    gcloud container get-server-config --zone us-central1-c --project cluster-dreams --format='yaml(channels)'
    ```

## Key Concepts

- **Always plan before apply** — Terraform shows exactly what will change
- **Mutable vs immutable**: Know which changes are safe (in-place) vs destructive (recreation)
- **Node pool replacement**: To change machine types safely, add a new pool → drain old pool → remove old pool
- **Release channels**: GKE manages Kubernetes version upgrades; `REGULAR` updates every ~4 weeks
- **CIDR changes destroy clusters**: Never modify network CIDRs on running environments

## Cleanup

```bash
git checkout -- gke.tf values.auto.tfvars
git checkout master
git branch -d feature/adjust-autoscaling
```
