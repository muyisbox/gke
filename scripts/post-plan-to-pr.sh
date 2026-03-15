#!/bin/bash
# Post Terraform plan summary to GitHub PR
# Usage: ./post-plan-to-pr.sh <pr_number> <plan_file_1> <plan_file_2> ...

set -e

PR_NUMBER="${1:-$_PR_NUMBER}"
REPO_OWNER="${GITHUB_OWNER:-muyisbox}"
REPO_NAME="${GITHUB_REPO:-gke}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$PR_NUMBER" ]; then
    echo "Error: PR number not provided"
    echo "Usage: $0 <pr_number> <plan_files...>"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    echo "Set it in Cloud Build substitutions or as a secret"
    exit 1
fi

echo "Generating plan summary for PR #$PR_NUMBER..."

# Create markdown summary
SUMMARY_FILE="/tmp/plan-summary.md"

cat > "$SUMMARY_FILE" <<EOF
## 📋 Terraform Plan Summary

**Build ID**: \`${BUILD_ID}\`
**Commit**: \`${SHORT_SHA}\`
**Branch**: \`${BRANCH_NAME}\`

---

EOF

# Process each workspace plan
for workspace in gitops dev staging; do
    plan_file="/workspace/plan_${workspace}.txt"

    if [ -f "$plan_file" ]; then
        echo "Processing plan for workspace: $workspace"

        cat >> "$SUMMARY_FILE" <<EOF
### 📦 Workspace: \`$workspace\`

\`\`\`
EOF

        # Extract the plan summary (resources to add/change/destroy)
        if grep -q "No changes" "$plan_file"; then
            echo "No changes. Your infrastructure matches the configuration." >> "$SUMMARY_FILE"
        else
            # Get the Plan: X to add, Y to change, Z to destroy line
            grep "Plan:" "$plan_file" | head -1 >> "$SUMMARY_FILE" || echo "Plan generated successfully" >> "$SUMMARY_FILE"

            # Optionally include resource changes (truncated)
            echo "" >> "$SUMMARY_FILE"
            echo "Key changes:" >> "$SUMMARY_FILE"
            grep -E "^\s+(#|\+|\-|~)" "$plan_file" | head -20 >> "$SUMMARY_FILE" || true

            # Check if truncated
            if [ $(grep -cE "^\s+(#|\+|\-|~)" "$plan_file") -gt 20 ]; then
                echo "..." >> "$SUMMARY_FILE"
                echo "(truncated, see build logs for full plan)" >> "$SUMMARY_FILE"
            fi
        fi

        cat >> "$SUMMARY_FILE" <<EOF
\`\`\`

EOF
    else
        cat >> "$SUMMARY_FILE" <<EOF
### 📦 Workspace: \`$workspace\`

⚠️ Plan file not found

EOF
    fi
done

# Add footer
cat >> "$SUMMARY_FILE" <<EOF
---

<details>
<summary>View full build logs</summary>

[Cloud Build Logs](https://console.cloud.google.com/cloud-build/builds/${BUILD_ID}?project=${PROJECT_ID})

</details>

> 🤖 Posted by Cloud Build
> 💡 Merge this PR to apply these changes to infrastructure
EOF

# Post to GitHub
echo "Posting summary to PR #$PR_NUMBER..."

COMMENT_BODY=$(cat "$SUMMARY_FILE" | jq -Rs .)

curl -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${PR_NUMBER}/comments" \
    -d "{\"body\":$COMMENT_BODY}"

echo ""
echo "✓ Posted plan summary to PR #$PR_NUMBER"
