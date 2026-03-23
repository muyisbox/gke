# Task 6: Terraform — Zero-Downtime Node Pool Migration

**Level:** Advanced

**Objective:** Migrate workloads from the current node pool to a new one with different machine types without downtime.

## Context

You can't change a node pool's machine type in-place — it forces recreation. The safe approach is: create a new pool → drain the old pool → delete the old pool. This is a common Day 2 operation.

## Steps

### Part A: Plan the Migration

1. Document the current state:

   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,POOL:.metadata.labels.cloud\.google\.com/gke-nodepool
   ```

2. Current pool in `gke.tf`:
   - Name: `node-pool-01`
   - Machine: `e2-standard-4` (4 vCPU, 16 GB)
   - Target: `e2-standard-8` (8 vCPU, 32 GB)

### Part B: Add the New Node Pool (Terraform)

3. Create a branch:

   ```bash
   git checkout -b feature/nodepool-migration
   ```

4. In `gke.tf`, add a new pool to the `node_pools` list (keep the old one):

   ```hcl
   {
     name               = "node-pool-02"
     machine_type       = "e2-standard-8"
     min_count          = 1
     max_count          = 4
     disk_size_gb       = 50
     disk_type          = "pd-ssd"
     image_type         = "COS_CONTAINERD"
     auto_repair        = true
     auto_upgrade       = true
     initial_node_count = 2
   }
   ```

5. Apply the same taints and labels as the old pool:

   ```hcl
   node-pool-02 = {
     default-node-pool = true
   }

   node-pool-02 = [
     {
       key    = "default-node-pool"
       value  = "true"
       effect = "PREFER_NO_SCHEDULE"
     }
   ]
   ```

6. Plan and apply:

   ```bash
   terraform workspace select dev
   terraform plan  # Verify: only ADDS node-pool-02, does NOT touch node-pool-01
   terraform apply
   ```

### Part C: Drain the Old Node Pool

7. Verify both pools have nodes:

   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.cloud\.google\.com/gke-nodepool
   ```

8. Cordon old nodes (prevent new scheduling):

   ```bash
   for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=node-pool-01 -o name); do
     kubectl cordon $node
   done
   ```

9. Drain old nodes (evict pods gracefully):

   ```bash
   for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=node-pool-01 -o name); do
     kubectl drain $node --ignore-daemonsets --delete-emptydir-data --grace-period=60
   done
   ```

10. Verify all pods moved to the new pool:

    ```bash
    kubectl get pods -A -o wide | grep node-pool-01  # Should be empty (except DaemonSets)
    kubectl get pods -A -o wide | grep node-pool-02  # Should have all workloads
    ```

### Part D: Remove the Old Pool (Terraform)

11. Remove `node-pool-01` from `gke.tf` (keep only `node-pool-02`).

12. Plan:

    ```bash
    terraform plan  # Should show: destroy node-pool-01 only
    ```

13. Apply:

    ```bash
    terraform apply
    ```

### Part E: Verify

14. Confirm the cluster is healthy:

    ```bash
    kubectl get nodes
    kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded'
    ```

15. Check all ArgoCD applications are synced:

    ```bash
    kubectl get applications -n argocd --context=gitops
    ```

## Key Concepts

- **Node pool replacement**: The only safe way to change machine types
- **Cordon**: Marks node as unschedulable (no new pods)
- **Drain**: Evicts existing pods (respects PodDisruptionBudgets)
- **Two-phase approach**: Add new pool → drain old → remove old
- **PodDisruptionBudgets**: Ensure minimum pod availability during drain
- **DaemonSets**: Ignored during drain (they run on every node by design)

## Production Considerations

- Set PodDisruptionBudgets on critical workloads before draining
- Drain one node at a time in large clusters
- Monitor during drain — watch for pods stuck in Terminating
- Consider using `kubectl drain --timeout=300s` to prevent indefinite hangs
