#!/bin/bash
# Setup Cloud Scheduler using Pub/Sub (most reliable method)

set -e

PROJECT_ID="cluster-dreams"
LOCATION="us-central1"

echo "=========================================="
echo "Cloud Scheduler Setup (Pub/Sub Method)"
echo "=========================================="
echo ""

# Enable APIs
echo "[1/5] Enabling APIs..."
gcloud services enable \
  cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  pubsub.googleapis.com \
  --project="$PROJECT_ID"

echo "✓ APIs enabled"
echo ""

# Create Pub/Sub topics
echo "[2/5] Creating Pub/Sub topics..."

gcloud pubsub topics create scheduled-destroy-trigger \
  --project="$PROJECT_ID" 2>/dev/null || echo "  Topic already exists"

gcloud pubsub topics create scheduled-create-trigger \
  --project="$PROJECT_ID" 2>/dev/null || echo "  Topic already exists"

echo "✓ Topics created"
echo ""

# Grant Pub/Sub permissions
echo "[3/5] Configuring permissions..."

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --condition=None 2>/dev/null || echo "  Permission already granted"

echo "✓ Permissions configured"
echo ""

# Create Cloud Scheduler jobs
echo "[4/5] Creating scheduler jobs..."

# Delete existing jobs
gcloud scheduler jobs delete trigger-destroy-dev-staging \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || true

gcloud scheduler jobs delete trigger-create-dev-staging \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || true

# Create destroy job (2 AM EST)
gcloud scheduler jobs create pubsub trigger-destroy-dev-staging \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --topic="scheduled-destroy-trigger" \
  --message-body='{"branchName":"main"}' \
  --description="Trigger destroy of dev/staging at 2 AM EST"

echo "✓ Destroy job created (2 AM EST)"

# Create recreate job (10 AM EST)
gcloud scheduler jobs create pubsub trigger-create-dev-staging \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --topic="scheduled-create-trigger" \
  --message-body='{"branchName":"main"}' \
  --description="Trigger recreate of dev/staging at 10 AM EST"

echo "✓ Recreate job created (10 AM EST)"
echo ""

# Summary
echo "[5/5] Verifying setup..."
echo ""
gcloud scheduler jobs list --location="$LOCATION" --project="$PROJECT_ID"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: Connect Cloud Build Triggers"
echo ""
echo "You must now connect these Pub/Sub topics to Cloud Build triggers:"
echo ""
echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers?project=$PROJECT_ID"
echo ""
echo "2. Create or edit trigger 'scheduled-destroy-dev-staging':"
echo "   - Event: Pub/Sub message"
echo "   - Topic: scheduled-destroy-trigger"
echo "   - Branch: ^main$"
echo "   - Configuration: cloudbuild-destroy.yaml"
echo ""
echo "3. Create or edit trigger 'scheduled-create-dev-staging':"
echo "   - Event: Pub/Sub message"
echo "   - Topic: scheduled-create-trigger"
echo "   - Branch: ^main$"
echo "   - Configuration: cloudbuild-create.yaml"
echo ""
echo "=========================================="
echo "Testing"
echo "=========================================="
echo ""
echo "Test the scheduler manually:"
echo ""
echo "  gcloud scheduler jobs run trigger-destroy-dev-staging --location=$LOCATION"
echo "  gcloud scheduler jobs run trigger-create-dev-staging --location=$LOCATION"
echo ""
echo "Monitor builds:"
echo ""
echo "  gcloud builds list --limit=5"
echo ""
echo "Pause/resume:"
echo ""
echo "  gcloud scheduler jobs pause trigger-destroy-dev-staging --location=$LOCATION"
echo "  gcloud scheduler jobs resume trigger-destroy-dev-staging --location=$LOCATION"
echo ""
