#!/bin/bash
# Simple Cloud Scheduler setup using gcloud builds submit approach

set -e

PROJECT_ID="cluster-dreams"
LOCATION="us-central1"
REPO_URL="https://github.com/muyisbox/gke"

echo "=========================================="
echo "Setting up Scheduled Destroy/Recreate"
echo "=========================================="
echo ""

# Enable APIs
echo "Enabling APIs..."
gcloud services enable cloudbuild.googleapis.com cloudscheduler.googleapis.com

echo ""
echo "Getting project details..."
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
echo "Project: $PROJECT_ID ($PROJECT_NUMBER)"

echo ""
echo "Creating Cloud Scheduler jobs..."

###################
# DESTROY JOB - 2 AM EST
###################

# Delete if exists
gcloud scheduler jobs delete scheduled-destroy-dev-staging \
  --location="$LOCATION" --quiet 2>/dev/null || true

# Create job that submits build via Cloud Build API
cat > /tmp/destroy-job.json <<EOF
{
  "configSource": {
    "repoSource": {
      "projectId": "${PROJECT_ID}",
      "repoName": "github_muyisbox_gke",
      "branchName": "main"
    },
    "buildConfigPath": "cicd/cloudbuild-destroy.yaml"
  }
}
EOF

gcloud scheduler jobs create http scheduled-destroy-dev-staging \
  --location="$LOCATION" \
  --schedule="0 2 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/builds" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --headers="Content-Type=application/json" \
  --message-body-from-file=/tmp/destroy-job.json \
  --description="Destroy dev/staging at 2 AM EST"

echo "✓ Destroy job created"

###################
# CREATE JOB - 10 AM EST
###################

# Delete if exists
gcloud scheduler jobs delete scheduled-create-dev-staging \
  --location="$LOCATION" --quiet 2>/dev/null || true

cat > /tmp/create-job.json <<EOF
{
  "configSource": {
    "repoSource": {
      "projectId": "${PROJECT_ID}",
      "repoName": "github_muyisbox_gke",
      "branchName": "main"
    },
    "buildConfigPath": "cicd/cloudbuild-create.yaml"
  }
}
EOF

gcloud scheduler jobs create http scheduled-create-dev-staging \
  --location="$LOCATION" \
  --schedule="0 10 * * *" \
  --time-zone="America/New_York" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/builds" \
  --http-method=POST \
  --oauth-service-account-email="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --headers="Content-Type=application/json" \
  --message-body-from-file=/tmp/create-job.json \
  --description="Recreate dev/staging at 10 AM EST"

echo "✓ Recreate job created"

echo ""
echo "=========================================="
echo "Jobs Created Successfully!"
echo "=========================================="

gcloud scheduler jobs list --location="$LOCATION"

echo ""
echo "Test manually:"
echo "  gcloud scheduler jobs run scheduled-destroy-dev-staging --location=$LOCATION"
echo ""
