# Cloud Scheduler Setup Guide

The easiest way to set up scheduled destroy/recreate is through the Google Cloud Console.

## 🚀 Quick Setup (5 minutes)

### Method 1: Cloud Console (Recommended)

#### Step 1: Create Cloud Build Triggers

1. Go to [Cloud Build Triggers](https://console.cloud.google.com/cloud-build/triggers?project=cluster-dreams)

2. **Click "CREATE TRIGGER"** for destroy job:
   - **Name**: `scheduled-destroy-dev-staging`
   - **Region**: us-central1
   - **Description**: Destroy dev/staging at 2 AM EST
   - **Event**: Manual invocation
   - **Source**:
     - Repository: `muyisbox/gke` (connect if needed)
     - Branch: `^main$`
   - **Configuration**:
     - Type: Cloud Build configuration file
     - Location: `/cloudbuild-destroy.yaml`
   - **Click CREATE**

3. **Click "CREATE TRIGGER"** for recreate job:
   - **Name**: `scheduled-create-dev-staging`
   - **Region**: us-central1
   - **Description**: Recreate dev/staging at 10 AM EST
   - **Event**: Manual invocation
   - **Source**:
     - Repository: `muyisbox/gke`
     - Branch: `^main$`
   - **Configuration**:
     - Type: Cloud Build configuration file
     - Location: `/cloudbuild-create.yaml`
   - **Click CREATE**

#### Step 2: Add Cloud Scheduler to Triggers

1. **Edit the destroy trigger**:
   - Click on `scheduled-destroy-dev-staging`
   - Click **EDIT**
   - Change **Event** from "Manual invocation" to **Pub/Sub message**
   - Topic: Create new topic `scheduled-destroy-trigger`
   - Save

2. **Create Cloud Scheduler job** for destroy:
   - Go to [Cloud Scheduler](https://console.cloud.google.com/cloudscheduler?project=cluster-dreams)
   - Click **CREATE JOB**
   - **Define the schedule**:
     - Name: `trigger-destroy-dev-staging`
     - Region: `us-central1`
     - Frequency: `0 2 * * *` (2 AM daily)
     - Timezone: `America/New_York`
   - **Configure the execution**:
     - Target type: **Pub/Sub**
     - Topic: `scheduled-destroy-trigger`
     - Message body: `{"branchName": "main"}`
   - Click **CREATE**

3. **Repeat for recreate**:
   - Edit `scheduled-create-dev-staging` trigger
   - Change to Pub/Sub with topic `scheduled-create-trigger`
   - Create Scheduler job:
     - Name: `trigger-create-dev-staging`
     - Frequency: `0 10 * * *` (10 AM daily)
     - Timezone: `America/New_York`
     - Topic: `scheduled-create-trigger`
     - Message: `{"branchName": "main"}`

### Method 2: Simple Script (Alternative)

If you prefer command line:

```bash
#!/bin/bash
# Run this script to set up both jobs

PROJECT_ID="cluster-dreams"

# Create Pub/Sub topics
gcloud pubsub topics create scheduled-destroy-trigger --project=$PROJECT_ID
gcloud pubsub topics create scheduled-create-trigger --project=$PROJECT_ID

# Create Cloud Scheduler jobs
gcloud scheduler jobs create pubsub trigger-destroy-dev-staging \
  --location=us-central1 \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --topic=scheduled-destroy-trigger \
  --message-body='{"branchName": "main"}' \
  --project=$PROJECT_ID

gcloud scheduler jobs create pubsub trigger-create-dev-staging \
  --location=us-central1 \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --topic=scheduled-create-trigger \
  --message-body='{"branchName": "main"}' \
  --project=$PROJECT_ID
```

Then manually configure the Cloud Build triggers in Console to use these topics.

### Method 3: Direct Submit (Simplest Test)

For immediate testing without schedulers:

```bash
# Test destroy
gcloud builds submit --config=cloudbuild-destroy.yaml

# Test recreate
gcloud builds submit --config=cloudbuild-create.yaml
```

## 🧪 Testing

### Test the Schedule Jobs

```bash
# Manually trigger the scheduler jobs
gcloud scheduler jobs run trigger-destroy-dev-staging --location=us-central1
gcloud scheduler jobs run trigger-create-dev-staging --location=us-central1

# Check if builds started
gcloud builds list --limit=2
```

### Verify Schedule

```bash
# List all scheduler jobs
gcloud scheduler jobs list --location=us-central1

# Check job details
gcloud scheduler jobs describe trigger-destroy-dev-staging --location=us-central1
```

## 📊 Monitoring

### View Execution History

```bash
# Recent builds
gcloud builds list --filter="tags:scheduled" --limit=10

# Scheduler job status
gcloud scheduler jobs describe trigger-destroy-dev-staging --location=us-central1
```

### Console Monitoring

- **Cloud Build**: https://console.cloud.google.com/cloud-build/builds?project=cluster-dreams
- **Cloud Scheduler**: https://console.cloud.google.com/cloudscheduler?project=cluster-dreams

## ⏸️ Pause/Resume

```bash
# Pause both jobs
gcloud scheduler jobs pause trigger-destroy-dev-staging --location=us-central1
gcloud scheduler jobs pause trigger-create-dev-staging --location=us-central1

# Resume both jobs
gcloud scheduler jobs resume trigger-destroy-dev-staging --location=us-central1
gcloud scheduler jobs resume trigger-create-dev-staging --location=us-central1
```

## 🗑️ Cleanup

```bash
# Delete scheduler jobs
gcloud scheduler jobs delete trigger-destroy-dev-staging --location=us-central1
gcloud scheduler jobs delete trigger-create-dev-staging --location=us-central1

# Delete Pub/Sub topics
gcloud pubsub topics delete scheduled-destroy-trigger
gcloud pubsub topics delete scheduled-create-trigger
```

## 🔧 Troubleshooting

### "Location not initialized"

```bash
# Initialize Cloud Scheduler
gcloud app create --region=us-central
```

### "Permission denied"

```bash
# Grant Cloud Build permission to be triggered by Pub/Sub
PROJECT_NUMBER=$(gcloud projects describe cluster-dreams --format="value(projectNumber)")

gcloud projects add-iam-policy-binding cluster-dreams \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

### Check what's configured

```bash
# List triggers
gcloud builds triggers list --region=us-central1

# List scheduler jobs
gcloud scheduler jobs list --location=us-central1

# List topics
gcloud pubsub topics list
```

## 💰 Expected Savings

- **Dev cluster**: ~16 hours/day offline = 480 hours/month saved
- **Staging cluster**: ~16 hours/day offline = 480 hours/month saved
- **Total**: ~960 cluster-hours/month saved
- **Estimated**: $200-400/month savings

## 📝 Notes

- Schedule uses `America/New_York` timezone (handles DST automatically)
- Destroy runs at 2 AM EST (7 AM UTC in winter, 6 AM UTC in summer)
- Recreate runs at 10 AM EST (3 PM UTC in winter, 2 PM UTC in summer)
- GitOps workspace is never destroyed (manages shared network)
- State is backed up before each destroy operation
