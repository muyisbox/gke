# Task 2: Create GCP Secrets and Sync Them to Applications with ESO

**Level:** Intermediate

**Objective:** Create a secret in GCP Secret Manager, configure External Secrets Operator to sync it into the cluster, and mount it in an application.

## Context

This platform uses ESO with Workload Identity to pull secrets from GCP Secret Manager. The ClusterSecretStore `gcp-secret-manager` is already configured on the gitops cluster (see `eso.tf`). You'll create a new secret and sync it to a sample application.

## Prerequisites

Connect to the dev cluster:

```bash
gcloud container clusters get-credentials dev-cluster --zone us-central1-c --project cluster-dreams
```

## Steps

### Part A: Create a Secret in GCP Secret Manager

1. Create a secret that simulates database credentials:

   ```bash
   gcloud secrets create myapp-db-credentials \
     --project=cluster-dreams \
     --replication-policy="automatic"
   ```

2. Add the secret data as a JSON payload:

   ```bash
   echo -n '{"username":"myapp_user","password":"SuperSecretP@ss123","host":"10.0.1.50","port":"5432","database":"myapp_prod"}' | \
     gcloud secrets versions add myapp-db-credentials --data-file=- --project=cluster-dreams
   ```

3. Verify the secret exists:

   ```bash
   gcloud secrets describe myapp-db-credentials --project=cluster-dreams
   gcloud secrets versions access latest --secret=myapp-db-credentials --project=cluster-dreams
   ```

### Part B: Verify ESO Infrastructure

4. Confirm the ClusterSecretStore is healthy:

   ```bash
   kubectl get clustersecretstores
   kubectl describe clustersecretstore gcp-secret-manager
   ```
   The status should show `Ready`.

5. If you're on the dev cluster and there's no ClusterSecretStore, check if ESO is running:

   ```bash
   kubectl get pods -n external-secrets
   ```

### Part C: Create an ExternalSecret

6. Create an ExternalSecret that pulls the GCP secret into Kubernetes:

   ```yaml
   # myapp-external-secret.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: myapp-db-credentials
     namespace: default
   spec:
     refreshInterval: 5m
     secretStoreRef:
       name: gcp-secret-manager
       kind: ClusterSecretStore
     target:
       name: myapp-db-secret
       creationPolicy: Owner
       template:
         type: Opaque
         data:
           DB_USERNAME: "{{ .username }}"
           DB_PASSWORD: "{{ .password }}"
           DB_HOST: "{{ .host }}"
           DB_PORT: "{{ .port }}"
           DB_NAME: "{{ .database }}"
           DB_CONNECTION_STRING: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/{{ .database }}"
     data:
     - secretKey: username
       remoteRef:
         key: myapp-db-credentials
         property: username
     - secretKey: password
       remoteRef:
         key: myapp-db-credentials
         property: password
     - secretKey: host
       remoteRef:
         key: myapp-db-credentials
         property: host
     - secretKey: port
       remoteRef:
         key: myapp-db-credentials
         property: port
     - secretKey: database
       remoteRef:
         key: myapp-db-credentials
         property: database
   ```

7. Apply and verify the sync:

   ```bash
   kubectl apply -f myapp-external-secret.yaml
   kubectl get externalsecrets
   kubectl describe externalsecret myapp-db-credentials
   ```
   Wait for the status to show `SecretSynced`.

8. Check the generated Kubernetes secret:

   ```bash
   kubectl get secret myapp-db-secret
   kubectl get secret myapp-db-secret -o jsonpath='{.data.DB_CONNECTION_STRING}' | base64 -d && echo
   ```

### Part D: Mount the Secret in an Application

9. Deploy a sample app that uses the secret as environment variables:

   ```yaml
   # myapp-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: myapp
     namespace: default
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: myapp
     template:
       metadata:
         labels:
           app: myapp
       spec:
         containers:
         - name: myapp
           image: busybox:1.36
           command: ["sh", "-c", "echo 'DB_HOST='$DB_HOST; echo 'DB_NAME='$DB_NAME; echo 'Connected as '$DB_USERNAME; sleep 3600"]
           envFrom:
           - secretRef:
               name: myapp-db-secret
   ```

10. Apply and check the logs:

    ```bash
    kubectl apply -f myapp-deployment.yaml
    kubectl logs -l app=myapp
    ```
    You should see the database configuration printed (without the password if you're careful).

### Part E: Rotate the Secret

11. Update the password in GCP Secret Manager:

    ```bash
    echo -n '{"username":"myapp_user","password":"NewRotatedP@ss456","host":"10.0.1.50","port":"5432","database":"myapp_prod"}' | \
      gcloud secrets versions add myapp-db-credentials --data-file=- --project=cluster-dreams
    ```

12. Wait for the refresh interval (5 minutes) or force a sync:

    ```bash
    kubectl annotate externalsecret myapp-db-credentials force-sync=$(date +%s) --overwrite
    ```

13. Check that the Kubernetes secret was updated:

    ```bash
    kubectl get secret myapp-db-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d && echo
    ```

14. The pod still has the old value in memory. This is where **Reloader** comes in — check `gke-applications/dev/reloader.yaml`. Reloader watches for secret changes and triggers pod restarts.

## Cleanup

```bash
kubectl delete -f myapp-deployment.yaml
kubectl delete -f myapp-external-secret.yaml
kubectl delete secret myapp-db-secret
gcloud secrets delete myapp-db-credentials --project=cluster-dreams --quiet
```

## Key Concepts

- **GCP Secret Manager**: Central secret store outside Kubernetes
- **ClusterSecretStore**: Cluster-wide connection to GCP Secret Manager (configured in `eso.tf`)
- **ExternalSecret**: Declares which GCP secret to sync and how to template the K8s secret
- **Template engine**: Lets you reshape the secret data (e.g., build a connection string)
- **Refresh interval**: How often ESO checks for changes (5m in this task, 1h for cluster secrets)
- **Reloader**: Automatically restarts pods when their mounted secrets/configmaps change
