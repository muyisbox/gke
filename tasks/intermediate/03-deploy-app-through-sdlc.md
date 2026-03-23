# Task 3: Deploy a Workload Through the SDLC Pipeline (Dev → Staging → Gitops)

**Level:** Intermediate

**Objective:** Deploy an application to dev first, promote it to staging, then to gitops, following the GitOps workflow.

## Context

In this platform, applications are deployed per-cluster by adding YAML files to `gke-applications/{cluster}/`. ArgoCD's ApplicationSets auto-detect new files and deploy them. Promotion between environments is done by copying the YAML to the next environment's directory.

## Steps

### Part A: Deploy to Dev

1. Create a feature branch:

   ```bash
   git checkout -b feature/redis-deployment
   ```

2. Create the application definition for dev. Create `gke-applications/dev/redis-cache.yaml`:

   ```yaml
   name: redis-cache
   chart: redis
   repoURL: https://charts.bitnami.com/bitnami
   targetRevision: "20.6.0"
   namespace: redis
   cluster_env: dev
   helm:
     values:
       architecture: standalone
       auth:
         enabled: false
       master:
         resources:
           requests:
             cpu: 100m
             memory: 128Mi
           limits:
             memory: 256Mi
         persistence:
           enabled: false
       replica:
         replicaCount: 0
   ```

3. Commit and push:

   ```bash
   git add gke-applications/dev/redis-cache.yaml
   git commit -m "Deploy redis-cache to dev environment"
   git push -u origin feature/redis-deployment
   ```

4. Create a PR. Cloud Build runs `cloudbuild-plan.yaml` to show the plan.

5. After review, merge the PR. ArgoCD detects the new file and deploys Redis to dev.

6. Verify on the dev cluster:

   ```bash
   gcloud container clusters get-credentials dev-cluster --zone us-central1-c --project cluster-dreams
   kubectl get pods -n redis
   kubectl get svc -n redis
   ```

### Part B: Promote to Staging

7. After validating in dev, promote to staging:

   ```bash
   git checkout master && git pull
   git checkout -b promote/redis-to-staging
   ```

8. Copy the file and update `cluster_env`:

   ```bash
   cp gke-applications/dev/redis-cache.yaml gke-applications/staging/redis-cache.yaml
   ```

9. Edit `gke-applications/staging/redis-cache.yaml` — change `cluster_env: dev` to `cluster_env: staging`.

10. Commit, push, PR, merge:

    ```bash
    git add gke-applications/staging/redis-cache.yaml
    git commit -m "Promote redis-cache to staging environment"
    git push -u origin promote/redis-to-staging
    ```

11. Verify on staging:

    ```bash
    gcloud container clusters get-credentials staging-cluster --zone us-central1-c --project cluster-dreams
    kubectl get pods -n redis
    ```

### Part C: Promote to Gitops (Production-like)

12. Repeat for gitops, but increase resources for production readiness:

    ```bash
    git checkout master && git pull
    git checkout -b promote/redis-to-gitops
    cp gke-applications/staging/redis-cache.yaml gke-applications/gitops/redis-cache.yaml
    ```

13. Edit `gke-applications/gitops/redis-cache.yaml`:
    - Change `cluster_env: staging` to `cluster_env: gitops`
    - Increase memory limits
    - Enable persistence

14. Commit, push, PR, merge. Verify on gitops cluster.

### Part D: Update Across Environments

15. Now simulate a version upgrade. Update the chart version in dev first:
    - Change `targetRevision` from `"20.6.0"` to a newer version
    - Merge to master
    - Validate in dev
    - Promote the version change to staging, then gitops

## Key Concepts

- **SDLC flow**: dev → staging → gitops (production)
- **Promotion**: Copy the YAML file to the next environment's directory
- **Environment differences**: Same chart, different values per environment (resources, replicas, persistence)
- **ArgoCD ApplicationSets**: Auto-detect new files via the Git file generator
- **Cloud Build**: Runs plan on PR, apply on merge
- The `cluster_env` field must match the directory name

## Cleanup

Remove the `redis-cache.yaml` files from all environments, commit, push, and merge.
