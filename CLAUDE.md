# Claude Code Assistant Instructions

This file contains important context and instructions for Claude Code sessions working on this GKE project.

## 🚀 Available GCloud Aliases

**IMPORTANT**: This project has custom gcloud aliases defined in `scripts/gcloud-aliases.sh`.

### To Load Aliases in New Sessions:
```bash
source scripts/gcloud-aliases.sh
```

### Key Aliases to Use:

#### Cloud Build Operations
- `gcb-test` - Submit test build with cloudbuild-test.yaml
- `gcb-submit` - Submit main build with cloudbuild.yaml
- `gcb-stream` - Submit build with streaming logs
- `gcb-logs BUILD_ID` - View build logs
- `gcb-list` - List recent builds
- `gcb-status BUILD_ID` - Get detailed build status

#### Quick Testing Functions
- `gcb-quick-test` - Auto-detect and run test build
- `gcb-submit-follow CONFIG` - Submit build and follow logs
- `gcloud-health-check` - Check overall GCP setup

#### Project Management
- `gp` - Get current project
- `gp-set PROJECT_ID` - Set project
- `ginfo` - Show current config summary
- `gp-quick-switch` - Interactive project switcher

#### GKE Operations
- `gke-connect CLUSTER_NAME [ZONE]` - Connect to cluster
- `gke-clusters` - List all clusters
- `k` - kubectl shortcut

#### Security & Scanning
- `gca-scan IMAGE` - Scan container image
- `gsm-list` - List secrets
- `gsm-get SECRET_NAME` - Get secret value

### 🧪 Testing Pipeline Locally

**Always test changes locally before committing:**

1. Load aliases: `source scripts/gcloud-aliases.sh`
2. Run health check: `gcloud-health-check`
3. Test pipeline: `gcb-test` or `gcb-quick-test`
4. Monitor: `gcb-logs BUILD_ID` or use `gcb-stream`

### 📁 Important Files

- `cicd/cloudbuild.yaml` - Main production pipeline (runs on merge to main)
- `cicd/cloudbuild-plan.yaml` - PR plan pipeline (runs on PRs)
- `cicd/cloudbuild-test.yaml` - Test/development pipeline
- `cicd/cloudbuild-destroy.yaml` - Scheduled destroy (2 AM EST)
- `cicd/cloudbuild-create.yaml` - Scheduled recreate (10 AM EST)
- `scripts/gcloud-aliases.sh` - All custom aliases
- `docs/PR-WORKFLOW.md` - Pull request workflow documentation
- `docs/SCHEDULED-DESTROY.md` - Cost optimization documentation
- This file (`CLAUDE.md`) - Instructions for Claude

### 🔧 Project Context

- **Project**: GKE infrastructure with Terraform
- **Pipeline**: Multi-environment (dev/staging/gitops)
- **Security**: Trivy + Checkov scanning enabled
- **Workflow**: PR-based (plan on PR, apply on merge)
- **Cost Optimization**: Scheduled destroy/recreate (2 AM - 10 AM EST)
- **Branch**: Currently on `feature/new-nodes`

### 🛡️ Security Scanning

The pipeline includes:
- **Trivy**: Container and IaC vulnerability scanning
- **Checkov**: Terraform security analysis
- **Dynamic scanning**: Based on branch/PR context

### 💡 Best Practices for Claude

1. **Always load aliases first** in new sessions
2. **Test locally** before suggesting commits
3. **Use health check** to verify setup
4. **Reference this file** for project context
5. **Test incrementally** with cicd/cloudbuild-test.yaml
6. **Use PR workflow** - Never push directly to main

### 🔄 PR Workflow

This project uses automated PR-based workflow:

1. **Create PR** → Triggers `cloudbuild-plan.yaml` → Shows what will change
2. **Review plan** → Check Cloud Build logs for terraform plan output
3. **Merge PR** → Triggers `cloudbuild.yaml` → Actually applies changes

**See [docs/PR-WORKFLOW.md](./docs/PR-WORKFLOW.md) for full details**

### 🚨 Common Issues & Solutions

#### "bash not found" in terraform containers
- **Fix**: Use `entrypoint: /bin/sh` (hashicorp/terraform is Alpine-based)

#### Cloud Build permission errors
- **Check**: `gcloud-health-check` for auth status
- **Fix**: `gcloud auth login` if needed

#### Pipeline fails on security scans
- **Test**: Run individual tools locally first
- **Fix**: Adjust severity levels or add exemptions

### 📋 Commands to Run in New Sessions

```bash
# Essential setup commands
source scripts/gcloud-aliases.sh
gcloud-health-check
gcb-quick-test

# If making changes
gcb-test                    # Test your changes
git add . && git commit -m "description"
git push
```

---

**Last Updated**: $(date)
**Claude**: Use these aliases and context in all sessions working on this project!