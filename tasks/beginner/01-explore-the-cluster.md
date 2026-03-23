# Task 1: Explore the Cluster and Understand the Infrastructure

**Level:** Beginner

**Objective:** Understand how the GKE clusters are provisioned with Terraform and explore the running infrastructure.

## Context

This platform runs 3 GKE clusters (dev, staging, gitops) managed by Terraform workspaces. Before operating clusters, you need to understand how they're built.

## Part A: Understand the Terraform Structure

1. Open `values.auto.tfvars` and identify:
   - What is the GCP project ID?
   - What region are the clusters deployed in?
   - How many environments are defined in the `environments` map?
   - What CIDR ranges are assigned to each environment?

2. Open `gke.tf` and answer:
   - What GKE module is being used? What is its source?
   - What machine type do the nodes use?
   - What is the min/max node count per pool?
   - What disk type and size are configured?
   - What taint is applied to the default node pool? What effect does it have?

3. Open `shared-network.tf` and answer:
   - What is the VPC name?
   - Which workspace creates the shared network? How is this controlled?
   - How are pod and service CIDRs calculated from `range_base`?

## Part B: Connect and Explore the Live Cluster

```bash
gcloud container clusters get-credentials dev-cluster --zone us-central1-c --project cluster-dreams
```

4. List all nodes and confirm the machine type matches what's in `gke.tf`:
   ```bash
   kubectl get nodes -o wide
   ```

5. Describe a node and find:
   - The taints applied (compare to `gke.tf`)
   - The labels (look for `default-node-pool`)
   - Allocatable CPU and memory
   ```bash
   kubectl describe node <node-name>
   ```

6. List all namespaces. Map each namespace to the application YAML files in `gke-applications/dev/`:
   ```bash
   kubectl get namespaces
   ls gke-applications/dev/
   ```

## Expected Outcomes

- You can trace every running resource back to its Terraform or GitOps definition
- You understand the relationship between Terraform workspaces and cluster environments
- You can identify the taint on the default node pool and explain what `PREFER_NO_SCHEDULE` means
