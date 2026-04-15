# Scheduled Destroy & Recreate

Automatically destroy all workspaces nightly and recreate weekly to save costs.

## 📅 Schedule

| Action | Time | Workspaces | Frequency |
|--------|------|------------|-----------|
| **Destroy** | 2 AM EST | dev, staging, gitops | Every night |
| **Recreate** | 10 AM EST | gitops, dev, staging | Monday only |

**Destroy order**: dev → staging → gitops (network destroyed last)
**Recreate order**: gitops → dev → staging (network created first)

## 💰 Cost Savings

- **All 3 clusters offline**: Mon night through next Mon morning
- **Only online**: Monday 10 AM → Tuesday 2 AM (~16 hours/week)
- **Offline**: ~152 hours/week
- **Estimated savings**: $500-800/month (depending on cluster size)

## 🔧 Setup Instructions

### Option 1: Quick Setup (Console)

1. Go to [Cloud Build Triggers](https://console.cloud.google.com/cloud-build/triggers)
2. Create two triggers:

**Destroy Trigger:**
- Name: `scheduled-destroy-dev-staging`
- Event: Cloud Scheduler
- Schedule: `0 2 * * *`
- Timezone: `America/New_York`
- Branch: `main`
- Cloud Build config: `cicd/cloudbuild-destroy.yaml`

**Create Trigger:**
- Name: `scheduled-create-dev-staging`
- Event: Cloud Scheduler
- Schedule: `0 10 * * *`
- Timezone: `America/New_York`
- Branch: `main`
- Cloud Build config: `cicd/cloudbuild-create.yaml`

### Option 2: Automated Setup (gcloud)

```bash
# Run the setup script
chmod +x scripts/setup-scheduled-triggers.sh
./scripts/setup-scheduled-triggers.sh cluster-dreams
```

### Option 3: Cloud Scheduler (Most Flexible)

```bash
# 1. Enable API
gcloud services enable cloudscheduler.googleapis.com

# 2. Get your project number
PROJECT_NUMBER=$(gcloud projects describe cluster-dreams --format="value(projectNumber)")

# 3. Create Cloud Build triggers (manual triggers)
gcloud builds triggers create manual \
  --project=cluster-dreams \
  --region=us-central1 \
  --name=scheduled-destroy-dev-staging \
  --build-config=cicd/cloudbuild-destroy.yaml \
  --repo=https://github.com/muyisbox/gke \
  --repo-type=GITHUB \
  --branch=main

gcloud builds triggers create manual \
  --project=cluster-dreams \
  --region=us-central1 \
  --name=scheduled-create-dev-staging \
  --build-config=cicd/cloudbuild-create.yaml \
  --repo=https://github.com/muyisbox/gke \
  --repo-type=GITHUB \
  --branch=main

# 4. Get trigger IDs
DESTROY_TRIGGER_ID=$(gcloud builds triggers list --project=cluster-dreams --filter="name=scheduled-destroy-dev-staging" --format="value(id)")
CREATE_TRIGGER_ID=$(gcloud builds triggers list --project=cluster-dreams --filter="name=scheduled-create-dev-staging" --format="value(id)")

# 5. Create Cloud Scheduler jobs
gcloud scheduler jobs create http scheduled-destroy-dev-staging \
  --project=cluster-dreams \
  --location=us-central1 \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/cluster-dreams/locations/us-central1/triggers/${DESTROY_TRIGGER_ID}:run" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --message-body='{"branchName":"main"}' \
  --description="Destroy dev/staging at 2 AM EST daily"

gcloud scheduler jobs create http scheduled-create-dev-staging \
  --project=cluster-dreams \
  --location=us-central1 \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/cluster-dreams/locations/us-central1/triggers/${CREATE_TRIGGER_ID}:run" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --message-body='{"branchName":"main"}' \
  --description="Recreate dev/staging at 10 AM EST daily"
```

## 🧪 Testing

### Test Destroy Manually

```bash
gcloud builds submit --config=cicd/cloudbuild-destroy.yaml
```

### Test Create Manually

```bash
gcloud builds submit --config=cicd/cloudbuild-create.yaml
```

### Trigger via Cloud Scheduler (without waiting)

```bash
# Manually trigger destroy job
gcloud scheduler jobs run scheduled-destroy-dev-staging --location=us-central1

# Manually trigger create job
gcloud scheduler jobs run scheduled-create-dev-staging --location=us-central1
```

## 📊 Monitoring

### View Scheduled Jobs

```bash
gcloud scheduler jobs list --location=us-central1
```

### View Job Execution History

```bash
gcloud scheduler jobs describe scheduled-destroy-dev-staging --location=us-central1
gcloud scheduler jobs describe scheduled-create-dev-staging --location=us-central1
```

### View Cloud Build History

```bash
gcloud builds list --filter="buildTriggerId:scheduled-destroy-dev-staging" --limit=10
gcloud builds list --filter="buildTriggerId:scheduled-create-dev-staging" --limit=10
```

## 🔔 Notifications (Optional)

### Add Slack Notifications

Add to both `cicd/cloudbuild-destroy.yaml` and `cicd/cloudbuild-create.yaml`:

```yaml
- name: gcr.io/cloud-builders/gcloud
  entrypoint: bash
  args:
  - -c
  - |
    curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
      -H 'Content-Type: application/json' \
      -d '{
        "text": "🤖 Dev/Staging clusters destroyed at $(date)",
        "username": "Cloud Build",
        "icon_emoji": ":cloud:"
      }'
```

## 🛡️ Safety Features

- ✅ **State backup before destroy** - Automatic backup of Terraform state
- ✅ **Sequential execution** - Dev destroyed/created before staging
- ✅ **GitOps preserved** - Shared network stays intact
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Timezone-aware** - Uses America/New_York (handles DST)

## 🔄 Modifying the Schedule

### Change Times

Edit the cron schedule in Cloud Scheduler:

```bash
# Update destroy time (example: change to 11 PM)
gcloud scheduler jobs update http scheduled-destroy-dev-staging \
  --location=us-central1 \
  --schedule="0 23 * * *"

# Update create time (example: change to 7 AM)
gcloud scheduler jobs update http scheduled-create-dev-staging \
  --location=us-central1 \
  --schedule="0 7 * * *"
```

### Weekdays Only

Change schedule to exclude weekends:

```bash
# Only run Monday-Friday
gcloud scheduler jobs update http scheduled-destroy-dev-staging \
  --location=us-central1 \
  --schedule="0 2 * * 1-5"

gcloud scheduler jobs update http scheduled-create-dev-staging \
  --location=us-central1 \
  --schedule="0 10 * * 1-5"
```

## ⏸️ Pausing Scheduled Destroys

### Temporarily Disable

```bash
# Pause destroy job
gcloud scheduler jobs pause scheduled-destroy-dev-staging --location=us-central1

# Pause create job
gcloud scheduler jobs pause scheduled-create-dev-staging --location=us-central1
```

### Re-enable

```bash
gcloud scheduler jobs resume scheduled-destroy-dev-staging --location=us-central1
gcloud scheduler jobs resume scheduled-create-dev-staging --location=us-central1
```

## 🗑️ Cleanup

Remove scheduled jobs:

```bash
gcloud scheduler jobs delete scheduled-destroy-dev-staging --location=us-central1
gcloud scheduler jobs delete scheduled-create-dev-staging --location=us-central1
```

## 📝 Notes

- **DST Handling**: Using `America/New_York` timezone automatically adjusts for Daylight Saving Time
- **Execution Time**: Destroy takes ~15-20 minutes, create takes ~20-30 minutes
- **State Location**: Terraform state is stored in GCS bucket with prefix `terraform/state`
- **Build Logs**: Available in Cloud Build history for 90 days

## 🚨 Troubleshooting

### Job Doesn't Run

```bash
# Check job configuration
gcloud scheduler jobs describe scheduled-destroy-dev-staging --location=us-central1

# Check if job is paused
gcloud scheduler jobs list --location=us-central1
```

### Build Fails

```bash
# View latest build logs
gcloud builds list --limit=1 --filter="buildTriggerId:scheduled-destroy-dev-staging"

# Get build details
gcloud builds describe BUILD_ID
```

### State Recovery

If destroy fails and state is corrupted:

```bash
# List state backups
gsutil ls gs://YOUR_BUCKET/tmp/terraform_*_predestroy_*.tfstate

# Restore state
gsutil cp gs://YOUR_BUCKET/tmp/terraform_dev_predestroy_BUILD_ID.tfstate ./terraform.tfstate
terraform state push terraform.tfstate
```
