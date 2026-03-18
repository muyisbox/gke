#!/bin/bash
# Complete setup for scheduled destroy/recreate
# Handles all prerequisites and error checking

set -e

PROJECT_ID="cluster-dreams"
REGION="us-central1"
LOCATION="us-central1"

echo "=========================================="
echo "Setting up Scheduled Destroy/Recreate"
echo "Project: $PROJECT_ID"
echo "=========================================="
echo ""

###################
# STEP 1: Enable APIs
###################
echo "Step 1: Enabling required APIs..."

gcloud services enable cloudbuild.googleapis.com \
  cloudscheduler.googleapis.com \
  --project="$PROJECT_ID"

echo "✓ APIs enabled"
echo ""

###################
# STEP 2: Get Project Number
###################
echo "Step 2: Getting project details..."

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
echo "Project Number: $PROJECT_NUMBER"
echo ""

###################
# STEP 3: Grant Cloud Scheduler permissions to Cloud Build
###################
echo "Step 3: Setting up IAM permissions..."

# Grant Cloud Build service account permissions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.builder" \
  --condition=None 2>/dev/null || echo "  (Already has permission)"

# Grant Cloud Scheduler service account permissions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com" \
  --role="roles/cloudscheduler.serviceAgent" \
  --condition=None 2>/dev/null || echo "  (Already has permission)"

echo "✓ Permissions configured"
echo ""

###################
# STEP 4: Initialize Cloud Scheduler (if needed)
###################
echo "Step 4: Checking Cloud Scheduler initialization..."

# Try to list jobs to see if location is initialized
if ! gcloud scheduler jobs list --location="$LOCATION" --project="$PROJECT_ID" &>/dev/null; then
    echo "  Initializing Cloud Scheduler in $LOCATION..."
    # Creating a dummy job and deleting it initializes the location
    gcloud scheduler jobs create http _init_dummy \
      --location="$LOCATION" \
      --schedule="0 0 1 1 0" \
      --uri="https://example.com" \
      --http-method=GET \
      --project="$PROJECT_ID" 2>/dev/null || true

    gcloud scheduler jobs delete _init_dummy \
      --location="$LOCATION" \
      --project="$PROJECT_ID" \
      --quiet 2>/dev/null || true
fi

echo "✓ Cloud Scheduler ready"
echo ""

###################
# STEP 5: Create Destroy Job
###################
echo "Step 5: Creating destroy schedule (2 AM EST)..."

# Delete if exists
gcloud scheduler jobs delete scheduled-destroy-dev-staging \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "  (Creating new job)"

# Create destroy job using gcloud builds submit
gcloud scheduler jobs create http scheduled-destroy-dev-staging \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/builds" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --headers="Content-Type=application/json" \
  --message-body="{
    \"source\": {
      \"repoSource\": {
        \"projectId\": \"${PROJECT_ID}\",
        \"repoName\": \"github_muyisbox_gke\",
        \"branchName\": \"main\"
      }
    },
    \"steps\": [{\"name\": \"gcr.io/cloud-builders/gcloud\", \"args\": [\"version\"]}],
    \"options\": {\"substitutionOption\": \"ALLOW_LOOSE\"},
    \"substitutions\": {\"_BUILD_CONFIG\": \"cloudbuild-destroy.yaml\"}
  }" \
  --description="Destroy dev/staging workspaces at 2 AM EST daily"

echo "✓ Destroy schedule created"
echo ""

###################
# STEP 6: Create Recreate Job
###################
echo "Step 6: Creating recreate schedule (10 AM EST)..."

# Delete if exists
gcloud scheduler jobs delete scheduled-create-dev-staging \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null || echo "  (Creating new job)"

# Create recreate job
gcloud scheduler jobs create http scheduled-create-dev-staging \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/builds" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --headers="Content-Type=application/json" \
  --message-body="{
    \"source\": {
      \"repoSource\": {
        \"projectId\": \"${PROJECT_ID}\",
        \"repoName\": \"github_muyisbox_gke\",
        \"branchName\": \"main\"
      }
    },
    \"steps\": [{\"name\": \"gcr.io/cloud-builders/gcloud\", \"args\": [\"version\"]}],
    \"options\": {\"substitutionOption\": \"ALLOW_LOOSE\"},
    \"substitutions\": {\"_BUILD_CONFIG\": \"cloudbuild-create.yaml\"}
  }" \
  --description="Recreate dev/staging workspaces at 10 AM EST daily"

echo "✓ Recreate schedule created"
echo ""

###################
# VERIFICATION
###################
echo "=========================================="
echo "Verification"
echo "=========================================="
echo ""

echo "Scheduled jobs:"
gcloud scheduler jobs list --location="$LOCATION" --project="$PROJECT_ID"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "✅ Destroy runs: 2 AM EST daily (destroys dev + staging)"
echo "✅ Recreate runs: 10 AM EST daily (recreates dev + staging)"
echo "✅ GitOps workspace: Always running (manages shared network)"
echo ""
echo "Estimated savings: ~960 cluster-hours/month (~$200-400/month)"
echo ""
echo "Next steps:"
echo "1. Test destroy manually:"
echo "   gcloud scheduler jobs run scheduled-destroy-dev-staging --location=$LOCATION"
echo ""
echo "2. Monitor execution:"
echo "   gcloud builds list --limit=5"
echo ""
echo "3. Pause/resume jobs:"
echo "   gcloud scheduler jobs pause scheduled-destroy-dev-staging --location=$LOCATION"
echo "   gcloud scheduler jobs resume scheduled-destroy-dev-staging --location=$LOCATION"
echo ""
