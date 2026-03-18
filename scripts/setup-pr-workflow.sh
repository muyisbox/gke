#!/bin/bash
# Setup Cloud Build triggers for PR-based workflow
# - Plan on PRs (cloudbuild-plan.yaml)
# - Apply on merge to main (cloudbuild.yaml)

set -e

PROJECT_ID=${1:-"cluster-dreams"}
REPO_NAME="muyisbox/gke"
REGION="us-central1"
GITHUB_OWNER="muyisbox"
GITHUB_REPO="gke"

echo "=========================================="
echo "Setting up PR-based workflow for GKE project"
echo "Project: $PROJECT_ID"
echo "Repository: $REPO_NAME"
echo "=========================================="
echo ""

# Check if GitHub connection exists
echo "Checking GitHub connection..."
if ! gcloud builds connections list --region="$REGION" --project="$PROJECT_ID" 2>/dev/null | grep -q "github"; then
    echo ""
    echo "⚠️  GitHub connection not found!"
    echo ""
    echo "To connect GitHub:"
    echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_ID"
    echo "2. Select 'GitHub (Cloud Build GitHub App)'"
    echo "3. Authenticate and select repository: $REPO_NAME"
    echo ""
    echo "After connecting, run this script again."
    exit 1
fi

echo "✓ GitHub connection found"
echo ""

###################
# TRIGGER 1: Plan on PR
###################

echo "Creating PR plan trigger..."

gcloud builds triggers create github \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --name="pr-plan-all-workspaces" \
  --repo-name="$GITHUB_REPO" \
  --repo-owner="$GITHUB_OWNER" \
  --pull-request-pattern="^.*$" \
  --build-config="cicd/cloudbuild-plan.yaml" \
  --comment-control="COMMENTS_ENABLED" \
  --description="Run terraform plan on all workspaces for PRs" \
  --substitutions='_PR_NUMBER=$(PULL_REQUEST_NUMBER)' \
  2>&1 | grep -v "already exists" || echo "✓ Trigger already exists"

echo ""
echo "✓ PR plan trigger configured:"
echo "  - Name: pr-plan-all-workspaces"
echo "  - Triggers on: All pull requests"
echo "  - Action: terraform plan (no apply)"
echo "  - Config: cicd/cloudbuild-plan.yaml"
echo ""

###################
# TRIGGER 2: Apply on main
###################

echo "Creating main branch apply trigger..."

gcloud builds triggers create github \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --name="main-apply-all-workspaces" \
  --repo-name="$GITHUB_REPO" \
  --repo-owner="$GITHUB_OWNER" \
  --branch-pattern="^main$" \
  --build-config="cicd/cloudbuild.yaml" \
  --description="Apply terraform changes when merged to main" \
  2>&1 | grep -v "already exists" || echo "✓ Trigger already exists"

echo ""
echo "✓ Main branch apply trigger configured:"
echo "  - Name: main-apply-all-workspaces"
echo "  - Triggers on: Push to main branch"
echo "  - Action: terraform plan + apply"
echo "  - Config: cicd/cloudbuild.yaml"
echo ""

###################
# OPTIONAL: Feature branch testing
###################

echo "Creating feature branch test trigger..."

gcloud builds triggers create github \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --name="feature-branch-test" \
  --repo-name="$GITHUB_REPO" \
  --repo-owner="$GITHUB_OWNER" \
  --branch-pattern="^feature/.*$" \
  --build-config="cicd/cloudbuild-test.yaml" \
  --description="Run tests on feature branches" \
  2>&1 | grep -v "already exists" || echo "✓ Trigger already exists"

echo ""
echo "✓ Feature branch test trigger configured:"
echo "  - Name: feature-branch-test"
echo "  - Triggers on: Push to feature/* branches"
echo "  - Action: Run validation tests"
echo "  - Config: cicd/cloudbuild-test.yaml"
echo ""

###################
# SUMMARY
###################

echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Workflow Summary:"
echo ""
echo "1. Developer creates PR:"
echo "   → 'pr-plan-all-workspaces' trigger runs"
echo "   → Runs terraform plan for all workspaces"
echo "   → Shows what would change (no apply)"
echo "   → Results visible in Cloud Build logs"
echo ""
echo "2. PR approved and merged to main:"
echo "   → 'main-apply-all-workspaces' trigger runs"
echo "   → Runs terraform plan + apply"
echo "   → Actually creates/modifies infrastructure"
echo ""
echo "3. Feature branch push:"
echo "   → 'feature-branch-test' trigger runs"
echo "   → Validates Terraform code"
echo "   → Runs security scans"
echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. View triggers:"
echo "   gcloud builds triggers list --region=$REGION --project=$PROJECT_ID"
echo ""
echo "2. Test PR workflow:"
echo "   - Create a test PR"
echo "   - Check Cloud Build for plan output"
echo "   - Merge PR to trigger apply"
echo ""
echo "3. Optional: Enable PR comments"
echo "   - See docs/PR-WORKFLOW.md for setup instructions"
echo "   - Requires GitHub App authentication"
echo ""
echo "4. Monitor builds:"
echo "   https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_ID"
echo ""

###################
# VALIDATE SETUP
###################

echo "Validating triggers..."
echo ""

TRIGGERS=$(gcloud builds triggers list --region="$REGION" --project="$PROJECT_ID" --format="value(name)" | sort)

echo "Configured triggers:"
echo "$TRIGGERS" | while read trigger; do
    echo "  ✓ $trigger"
done

echo ""
echo "Setup validation complete!"
