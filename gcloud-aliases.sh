#!/bin/bash
# GCloud Aliases for Efficient Cloud Operations
# Source this file: source gcloud-aliases.sh

echo "🚀 Loading GCloud Aliases..."

# =============================================================================
# CLOUD BUILD ALIASES
# =============================================================================

# Cloud Build Operations
alias gcb-submit='gcloud builds submit'
alias gcb-test='gcloud builds submit --config=cloudbuild-test.yaml'
alias gcb-prod='gcloud builds submit --config=cloudbuild.yaml'
alias gcb-logs='gcloud builds log'
alias gcb-list='gcloud builds list --limit=10'
alias gcb-cancel='gcloud builds cancel'
alias gcb-triggers='gcloud builds triggers list'

# Cloud Build with substitutions
alias gcb-pr='gcloud builds submit --substitutions=_PR_NUMBER=${1:-123}'
alias gcb-dev='gcloud builds submit --substitutions=_WORKSPACES=dev'
alias gcb-staging='gcloud builds submit --substitutions=_WORKSPACES=staging'

# Cloud Build streaming and monitoring
alias gcb-stream='gcloud builds submit --stream-logs'
alias gcb-watch='watch -n 5 "gcloud builds list --limit=5"'

# =============================================================================
# GKE (KUBERNETES) ALIASES
# =============================================================================

# Cluster operations
alias gke-clusters='gcloud container clusters list'
alias gke-get='gcloud container clusters get-credentials'
alias gke-create='gcloud container clusters create'
alias gke-delete='gcloud container clusters delete'
alias gke-resize='gcloud container clusters resize'

# Node pool operations
alias gke-pools='gcloud container node-pools list'
alias gke-pool-create='gcloud container node-pools create'
alias gke-pool-delete='gcloud container node-pools delete'

# Kubectl context switching
alias k='kubectl'
alias kctx='kubectl config current-context'
alias kns='kubectl config set-context --current --namespace'

# =============================================================================
# COMPUTE & STORAGE ALIASES
# =============================================================================

# Compute instances
alias gce-list='gcloud compute instances list'
alias gce-ssh='gcloud compute ssh'
alias gce-start='gcloud compute instances start'
alias gce-stop='gcloud compute instances stop'
alias gce-reset='gcloud compute instances reset'

# Storage operations
alias gsutil-ls='gsutil ls -la'
alias gsutil-cp='gsutil -m cp -r'
alias gsutil-sync='gsutil -m rsync -r -d'

# =============================================================================
# PROJECT & IAM ALIASES
# =============================================================================

# Project management
alias gp='gcloud config get-value project'
alias gp-set='gcloud config set project'
alias gp-list='gcloud projects list'
alias gp-switch='gcloud config configurations activate'

# Service accounts
alias gsa-list='gcloud iam service-accounts list'
alias gsa-keys='gcloud iam service-accounts keys list'
alias gsa-create='gcloud iam service-accounts create'

# IAM policies
alias giam-list='gcloud projects get-iam-policy $(gcloud config get-value project)'
alias giam-add='gcloud projects add-iam-policy-binding $(gcloud config get-value project)'

# =============================================================================
# TERRAFORM & INFRASTRUCTURE ALIASES
# =============================================================================

# Terraform with gcloud
alias tf-init='terraform init'
alias tf-plan='terraform plan -var="project_id=$(gcloud config get-value project)"'
alias tf-apply='terraform apply -var="project_id=$(gcloud config get-value project)"'
alias tf-destroy='terraform destroy -var="project_id=$(gcloud config get-value project)"'

# =============================================================================
# MONITORING & LOGGING ALIASES
# =============================================================================

# Logging
alias glog='gcloud logging logs list'
alias glog-read='gcloud logging read'
alias glog-tail='gcloud logging tail'

# Monitoring
alias gmon-policies='gcloud alpha monitoring policies list'
alias gmon-metrics='gcloud monitoring metrics list'

# =============================================================================
# SECRET MANAGER ALIASES
# =============================================================================

# Secret management
alias gsm-list='gcloud secrets list'
alias gsm-get='gcloud secrets versions access latest --secret'
alias gsm-create='gcloud secrets create'
alias gsm-add='gcloud secrets versions add'

# =============================================================================
# SECURITY & SCANNING ALIASES
# =============================================================================

# Container Analysis
alias gca-scan='gcloud container images scan'
alias gca-list='gcloud container images list-tags'

# Binary Authorization
alias gba-policy='gcloud container binauthz policy export'
alias gba-attestors='gcloud container binauthz attestors list'

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to submit build and follow logs
gcb-submit-follow() {
    local config_file=${1:-cloudbuild.yaml}
    echo "🚀 Submitting build with config: $config_file"
    gcloud builds submit --config="$config_file" --stream-logs
}

# Function to get build status
gcb-status() {
    local build_id=${1}
    if [ -z "$build_id" ]; then
        echo "❌ Please provide build ID"
        echo "Usage: gcb-status BUILD_ID"
        return 1
    fi
    gcloud builds describe "$build_id"
}

# Function to get cluster credentials and set context
gke-connect() {
    local cluster_name=${1}
    local zone=${2:-us-central1-a}
    if [ -z "$cluster_name" ]; then
        echo "❌ Please provide cluster name"
        echo "Usage: gke-connect CLUSTER_NAME [ZONE]"
        return 1
    fi
    echo "🔗 Connecting to cluster: $cluster_name in zone: $zone"
    gcloud container clusters get-credentials "$cluster_name" --zone="$zone"
    kubectl config current-context
}

# Function to switch between GCP projects
gp-quick-switch() {
    echo "📋 Available projects:"
    gcloud projects list --format="table(projectId,name)" --limit=10
    echo ""
    read -p "Enter project ID: " project_id
    if [ -n "$project_id" ]; then
        gcloud config set project "$project_id"
        echo "✅ Switched to project: $(gcloud config get-value project)"
    fi
}

# Function to create and activate new gcloud configuration
gconfig-create() {
    local config_name=${1}
    if [ -z "$config_name" ]; then
        echo "❌ Please provide configuration name"
        echo "Usage: gconfig-create CONFIG_NAME"
        return 1
    fi
    gcloud config configurations create "$config_name"
    gcloud config configurations activate "$config_name"
    echo "✅ Created and activated configuration: $config_name"
    echo "🔧 Now set your project and account:"
    echo "   gcloud config set account YOUR_EMAIL"
    echo "   gcloud config set project YOUR_PROJECT"
}

# Function to test current setup
gcloud-health-check() {
    echo "🔍 GCloud Health Check"
    echo "======================"
    echo "Active Account: $(gcloud config get-value account)"
    echo "Active Project: $(gcloud config get-value project)"
    echo "Active Config: $(gcloud config configurations list --filter=is_active:true --format='value(name)')"
    echo ""
    echo "🔑 Authentication Status:"
    gcloud auth list --filter=status:ACTIVE --format="table(account,status)"
    echo ""
    echo "📋 Recent Builds:"
    gcloud builds list --limit=3 --format="table(id,status,createTime.date())"
    echo ""
    echo "🏗️ Available Clusters:"
    gcloud container clusters list --format="table(name,location,status)" 2>/dev/null || echo "No clusters found or permission denied"
}

# Function to quickly submit test build
gcb-quick-test() {
    echo "🧪 Quick Test Build"
    if [ -f "cloudbuild-test.yaml" ]; then
        gcloud builds submit --config=cloudbuild-test.yaml --stream-logs
    elif [ -f "cloudbuild.yaml" ]; then
        echo "⚠️  No test config found, using main cloudbuild.yaml"
        gcloud builds submit --config=cloudbuild.yaml --stream-logs
    else
        echo "❌ No Cloud Build configuration found"
        return 1
    fi
}

# =============================================================================
# HELPFUL SHORTCUTS
# =============================================================================

# Quick project info
alias ginfo='echo "Project: $(gp)" && echo "Account: $(gcloud config get-value account)" && echo "Region: $(gcloud config get-value compute/region)" && echo "Zone: $(gcloud config get-value compute/zone)"'

# Quick resource listing
alias gresources='echo "=== COMPUTE INSTANCES ===" && gcloud compute instances list --limit=5 && echo -e "\n=== GKE CLUSTERS ===" && gcloud container clusters list --limit=5 && echo -e "\n=== RECENT BUILDS ===" && gcloud builds list --limit=5'

# Enable/disable APIs quickly
alias gapi-enable='gcloud services enable'
alias gapi-list='gcloud services list --enabled'

# =============================================================================
# LOAD COMPLETION
# =============================================================================

echo "✅ GCloud aliases loaded successfully!"
echo ""
echo "🔧 Key aliases:"
echo "   gcb-test     - Submit test build"
echo "   gcb-submit   - Submit main build"
echo "   gke-connect  - Connect to GKE cluster"
echo "   gp-set       - Set project"
echo "   ginfo        - Show current config"
echo "   gcloud-health-check - Full system check"
echo ""
echo "💡 Type any alias name to see what it does!"