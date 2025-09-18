# GKE Private Nodes - Shared NAT Gateway Solution

## Problem
Your GKE cluster has private nodes (`enable_private_nodes = true`) but can't pull public images because:

1. **No internet access**: Private nodes lack public IPs and can't reach the internet
2. **Missing NAT Gateway**: No Cloud NAT configured for outbound connectivity
3. **Insufficient OAuth scopes**: Missing container registry access permissions
4. **Cost issue**: Creating separate NAT Gateways per cluster (~$45/month each)

## Solutions Applied

### 1. Shared Cloud NAT Gateway ✅
**COST SAVINGS: ~$90/month** (from 3 NATs to 1 NAT)

Created shared network infrastructure in `shared-network.tf`:
- **Single NAT Gateway** serves all clusters (dev, staging, gitops)
- Provides outbound internet access for private nodes across all environments
- Allows pulling images from public registries (Docker Hub, gcr.io, etc.)
- Auto-allocates NAT IPs with logging for troubleshooting

### 2. OAuth Scopes ✅
Updated `node_pools_oauth_scopes` in `gke.tf`:
- Added `devstorage.read_only` for Google Container Registry access
- Added `compute` scope for general GCP API access
- Maintained existing logging and monitoring scopes

### 3. Master Endpoint Configuration ✅
- Set `enable_private_endpoint = false` to allow external kubectl access
- Configured `master_ipv4_cidr_block` for the control plane

### 2. Shared Network Architecture
- **Single VPC Network**: `shared-gke-network` hosts all clusters
- **Dedicated Subnets**: Each environment gets its own subnet with non-overlapping CIDRs
  - Dev: `10.10.0.0/17`
  - Staging: `10.20.0.0/17` 
  - GitOps: `10.30.0.0/17`
- **Private Google Access**: Enabled on all subnets for GCP API access
- **Master CIDRs**: Non-overlapping control plane networks per environment

## Migration Steps (IMPORTANT)

⚠️ **This is a breaking change that requires careful migration!**

### Phase 1: Deploy Shared Infrastructure
1. **Deploy shared network first**:
   ```bash
   terraform plan -target=module.shared-network
   terraform apply -target=module.shared-network
   
   terraform plan -target=google_compute_router.shared_router
   terraform apply -target=google_compute_router.shared_router
   
   terraform plan -target=google_compute_router_nat.shared_nat
   terraform apply -target=google_compute_router_nat.shared_nat
   ```

### Phase 2: Migrate Clusters (One at a Time)
2. **Migrate each workspace separately** (start with dev):
   ```bash
   # Switch to dev workspace
   terraform workspace select dev
   
   # Remove old cluster (backup data first!)
   terraform destroy -target=module.gke
   
   # Apply new cluster with shared network
   terraform plan
   terraform apply
   ```

3. **Verify NAT Gateway works**:
   ```bash
   gcloud compute routers nats list --router=shared-gke-router --region=us-central1
   ```

4. **Test image pulling**:
   ```bash
   kubectl run test-pod --image=nginx:latest --rm -it --restart=Never
   ```

### Phase 3: Clean Up
5. **Remove old network resources** (after all clusters are migrated):
   ```bash
   # Remove old per-workspace networks manually via console or gcloud
   gcloud compute networks delete gke-network-dev
   gcloud compute networks delete gke-network-staging  
   gcloud compute networks delete gke-network-gitops
   ```

## Alternative Solutions

### Option 1: Artifact Registry/Container Registry Mirror
If you prefer not to use public internet access:

```bash
# Set up a private registry and mirror public images
gcloud artifacts repositories create my-repo \
    --repository-format=docker \
    --location=us-central1

# Mirror public images to your private registry
docker pull nginx:latest
docker tag nginx:latest us-central1-docker.pkg.dev/PROJECT_ID/my-repo/nginx:latest
docker push us-central1-docker.pkg.dev/PROJECT_ID/my-repo/nginx:latest
```

### Option 2: Private Google Access
Enable Private Google Access on your subnet:

```hcl
# In network.tf
subnets = [
  {
    subnet_name           = "${var.subnetwork}-${terraform.workspace}"
    subnet_ip            = lookup(local.subnet_cidrs, terraform.workspace)
    subnet_region        = var.region
    subnet_private_access = "true"  # Add this line
  },
]
```

## Troubleshooting

### Check NAT Gateway Status
```bash
gcloud compute routers nats describe gke-network-nat-dev \
    --router=gke-network-router-dev \
    --region=us-central1
```

### Check Node OAuth Scopes
```bash
gcloud container clusters describe dev-cluster \
    --zone=us-central1-b \
    --format="value(nodeConfig.oauthScopes[].join(','))"
```

### Test Internet Connectivity from Pod
```bash
kubectl run debug-pod --image=busybox --rm -it --restart=Never -- nslookup google.com
```

### Common Issues

1. **DNS Resolution**: Ensure your VPC has proper DNS configuration
2. **Firewall Rules**: Make sure egress rules allow HTTPS (443) and HTTP (80)
3. **Service Account**: Verify the compute engine service account has proper IAM roles

## Cost Considerations

- **Cloud NAT**: ~$45/month per gateway + ~$0.045 per GB processed
- **External IPs**: ~$3.65/month per static IP (if using static NAT IPs)

## Security Best Practices

1. **Limit NAT access**: Consider restricting which subnets can use NAT
2. **Private endpoints**: Use `enable_private_endpoint = true` for production
3. **Authorized networks**: Configure master authorized networks for kubectl access
4. **Image scanning**: Enable vulnerability scanning for pulled images

The changes made will resolve your image pulling issues while maintaining the security benefits of private nodes.