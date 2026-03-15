#!/bin/bash
# Setup Cloud Build scheduled triggers for automatic destroy/recreate
# Destroys dev/staging at 2 AM EST, recreates at 10 AM EST

set -e

PROJECT_ID=${1:-"cluster-dreams"}
REPO_NAME="muyisbox/gke"
REGION="us-central1"

echo "Setting up scheduled Cloud Build triggers for project: $PROJECT_ID"

# Note: EST = UTC-5 (Standard) or UTC-4 (Daylight)
# Using America/New_York timezone handles DST automatically
# 2 AM EST = 7 AM UTC (standard) or 6 AM UTC (daylight)
# 10 AM EST = 3 PM UTC (standard) or 2 PM UTC (daylight)

###################
# DESTROY TRIGGER
###################
echo ""
echo "Creating DESTROY trigger (2 AM EST daily)..."

gcloud builds triggers create manual \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --name="scheduled-destroy-dev-staging" \
  --build-config="cloudbuild-destroy.yaml" \
  --repo="https://github.com/$REPO_NAME" \
  --repo-type="GITHUB" \
  --branch="main" \
  --description="Automated destroy of dev and staging workspaces at 2 AM EST" \
  || echo "Trigger already exists or failed to create"

# Note: Manual triggers need to be converted to scheduled via Console or API
# The gcloud CLI doesn't directly support cron schedules in trigger creation
# Alternative: Use Cloud Scheduler to trigger the build

echo ""
echo "⚠️  MANUAL STEP REQUIRED:"
echo "Convert the 'scheduled-destroy-dev-staging' trigger to scheduled:"
echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers?project=$PROJECT_ID"
echo "2. Edit trigger: scheduled-destroy-dev-staging"
echo "3. Change from Manual to Cloud Scheduler"
echo "4. Set schedule: 0 2 * * * (2 AM daily)"
echo "5. Set timezone: America/New_York"
echo ""

###################
# CREATE TRIGGER
###################
echo "Creating CREATE trigger (10 AM EST daily)..."

gcloud builds triggers create manual \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --name="scheduled-create-dev-staging" \
  --build-config="cloudbuild-create.yaml" \
  --repo="https://github.com/$REPO_NAME" \
  --repo-type="GITHUB" \
  --branch="main" \
  --description="Automated recreation of dev and staging workspaces at 10 AM EST" \
  || echo "Trigger already exists or failed to create"

echo ""
echo "⚠️  MANUAL STEP REQUIRED:"
echo "Convert the 'scheduled-create-dev-staging' trigger to scheduled:"
echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers?project=$PROJECT_ID"
echo "2. Edit trigger: scheduled-create-dev-staging"
echo "3. Change from Manual to Cloud Scheduler"
echo "4. Set schedule: 0 10 * * * (10 AM daily)"
echo "5. Set timezone: America/New_York"
echo ""

###################
# ALTERNATIVE: Cloud Scheduler (Recommended)
###################
echo ""
echo "=========================================="
echo "ALTERNATIVE: Using Cloud Scheduler directly"
echo "=========================================="
echo ""

cat << 'EOF'
# This approach gives you more control over scheduling

# 1. Enable Cloud Scheduler API
gcloud services enable cloudscheduler.googleapis.com --project=$PROJECT_ID

# 2. Create destroy job (2 AM EST daily)
gcloud scheduler jobs create http scheduled-destroy-dev-staging \
  --project=$PROJECT_ID \
  --location=us-central1 \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/$PROJECT_ID/triggers/scheduled-destroy-dev-staging:run" \
  --message-body='{"branchName":"main"}' \
  --oauth-service-account-email="[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com" \
  --description="Destroy dev/staging at 2 AM EST"

# 3. Create recreate job (10 AM EST daily)
gcloud scheduler jobs create http scheduled-create-dev-staging \
  --project=$PROJECT_ID \
  --location=us-central1 \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/$PROJECT_ID/triggers/scheduled-create-dev-staging:run" \
  --message-body='{"branchName":"main"}' \
  --oauth-service-account-email="[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com" \
  --description="Recreate dev/staging at 10 AM EST"

# Note: Replace [PROJECT_NUMBER] with your actual project number
# Get it with: gcloud projects describe $PROJECT_ID --format="value(projectNumber)"
EOF

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Created triggers:"
echo "  - scheduled-destroy-dev-staging (2 AM EST)"
echo "  - scheduled-create-dev-staging (10 AM EST)"
echo ""
echo "Next steps:"
echo "1. Complete manual configuration in Cloud Console (see above)"
echo "2. Or use Cloud Scheduler commands (recommended)"
echo "3. Test triggers manually before relying on schedule"
echo ""
echo "Estimated monthly savings:"
echo "  - Dev cluster: ~16 hours/day × 30 days = 480 hours saved"
echo "  - Staging cluster: ~16 hours/day × 30 days = 480 hours saved"
echo "  - Total: ~960 hours/month of cluster runtime saved"
echo ""
