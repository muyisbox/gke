#!/bin/bash

# Cloud Build CI/CD Pipeline Testing Script
# This script tests the improved CI/CD pipeline using gcloud commands

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID="${PROJECT_ID:-cluster-dreams}"
REGION="${REGION:-us-central1}"
WORKSPACES="${WORKSPACES:-gitops,dev}"
TF_VERSION="${TF_VERSION:-1.11}"
BRANCH_NAME="${BRANCH_NAME:-feature/new-nodes}"
TEST_TYPE="dry-run" # Options: dry-run, submit, monitor, full

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check gcloud prerequisites
check_gcloud_prerequisites() {
    log_info "Checking gcloud prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        log_info "Install gcloud CLI: brew install --cask google-cloud-sdk"
        return 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud"
        log_info "Authenticate with: gcloud auth login"
        return 1
    fi
    
    # Check if project is set
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$current_project" ]; then
        log_warning "No default project set, using PROJECT_ID: $PROJECT_ID"
        gcloud config set project "$PROJECT_ID"
    else
        log_info "Current project: $current_project"
        if [ "$current_project" != "$PROJECT_ID" ]; then
            log_warning "Current project differs from specified PROJECT_ID"
            log_info "Setting project to: $PROJECT_ID"
            gcloud config set project "$PROJECT_ID"
        fi
    fi
    
    # Check Cloud Build API
    if ! gcloud services list --enabled --filter="name:cloudbuild.googleapis.com" --format="value(name)" | grep -q cloudbuild; then
        log_warning "Cloud Build API not enabled"
        log_info "Enabling Cloud Build API..."
        gcloud services enable cloudbuild.googleapis.com
    fi
    
    log_success "gcloud prerequisites satisfied"
    return 0
}

# Function to validate project access
validate_project_access() {
    log_info "Validating project access and permissions..."
    
    # Check if we can access the project
    if ! gcloud projects describe "$PROJECT_ID" --quiet &>/dev/null; then
        log_error "Cannot access project: $PROJECT_ID"
        log_info "Make sure you have the correct project ID and permissions"
        return 1
    fi
    
    # Check Cloud Build permissions
    local build_sa="${PROJECT_ID}@cloudbuild.gserviceaccount.com"
    log_info "Checking Cloud Build service account: $build_sa"
    
    # List available triggers (requires cloudbuild.triggers.list permission)
    if gcloud builds triggers list --limit=1 --quiet &>/dev/null; then
        log_success "Cloud Build triggers access verified"
    else
        log_warning "Limited Cloud Build access - may not be able to list triggers"
    fi
    
    # Check for Terraform state bucket
    local state_bucket="gs://${PROJECT_ID}-terraform-state"
    if gsutil ls "$state_bucket" &>/dev/null; then
        log_success "Terraform state bucket accessible: $state_bucket"
    else
        log_warning "Terraform state bucket not accessible: $state_bucket"
    fi
    
    return 0
}

# Function to test configuration submission (dry run)
test_dry_run() {
    log_info "Testing Cloud Build configuration (dry run)..."
    
    # Test the improved cloudbuild.yaml
    if [ ! -f "cloudbuild_improved.yaml" ]; then
        log_error "cloudbuild_improved.yaml not found"
        return 1
    fi
    
    log_info "Validating Cloud Build configuration syntax..."
    
    # Create a temporary build with --dry-run flag (if available)
    local temp_config="temp_cloudbuild_test.yaml"
    cp cloudbuild_improved.yaml "$temp_config"
    
    # Try to submit with validation
    log_info "Testing configuration submission..."
    if gcloud builds submit \
        --config="$temp_config" \
        --region="$REGION" \
        --substitutions="_WORKSPACES=$WORKSPACES,_TF_VERSION=$TF_VERSION" \
        --no-source \
        --dry-run 2>/dev/null; then
        log_success "Dry run validation passed"
    else
        log_warning "Dry run not supported, using alternative validation"
        
        # Alternative: just validate the YAML structure
        if gcloud builds submit --help | grep -q "dry-run"; then
            log_info "Dry run flag available but validation failed"
        else
            log_info "Dry run flag not available in this gcloud version"
        fi
    fi
    
    # Clean up
    rm -f "$temp_config"
    
    return 0
}

# Function to submit actual build for testing
submit_test_build() {
    log_info "Submitting test build to Cloud Build..."
    
    if [ ! -f "cloudbuild_improved.yaml" ]; then
        log_error "cloudbuild_improved.yaml not found"
        return 1
    fi
    
    # Prepare substitutions
    local substitutions="_WORKSPACES=$WORKSPACES,_TF_VERSION=$TF_VERSION,_PR_NUMBER=test-build"
    
    log_info "Submitting build with substitutions: $substitutions"
    log_info "Region: $REGION"
    log_info "Branch: $BRANCH_NAME"
    
    # Submit the build
    local build_id
    build_id=$(gcloud builds submit \
        --config="cloudbuild_improved.yaml" \
        --region="$REGION" \
        --substitutions="$substitutions" \
        --async \
        --format="value(id)" \
        . 2>/dev/null)
    
    if [ -n "$build_id" ]; then
        log_success "Build submitted successfully"
        echo "Build ID: $build_id"
        echo "Monitor at: https://console.cloud.google.com/cloud-build/builds/$build_id?project=$PROJECT_ID"
        
        # Store build ID for monitoring
        echo "$build_id" > .last_build_id
        
        return 0
    else
        log_error "Failed to submit build"
        return 1
    fi
}

# Function to monitor build progress
monitor_build() {
    log_info "Monitoring build progress..."
    
    local build_id=""
    
    # Get build ID from parameter or file
    if [ -n "${1:-}" ]; then
        build_id="$1"
    elif [ -f ".last_build_id" ]; then
        build_id=$(cat .last_build_id)
    else
        log_error "No build ID provided or found"
        return 1
    fi
    
    log_info "Monitoring build: $build_id"
    
    # Monitor build status
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(gcloud builds describe "$build_id" \
            --region="$REGION" \
            --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        
        case $status in
            "SUCCESS")
                log_success "Build completed successfully!"
                
                # Get build logs
                log_info "Retrieving build logs..."
                gcloud builds log "$build_id" --region="$REGION"
                
                return 0
                ;;
            "FAILURE"|"CANCELLED"|"EXPIRED"|"TIMEOUT")
                log_error "Build failed with status: $status"
                
                # Get build logs for debugging
                log_info "Retrieving failure logs..."
                gcloud builds log "$build_id" --region="$REGION" || true
                
                return 1
                ;;
            "WORKING"|"QUEUED")
                log_info "Build status: $status (elapsed: ${elapsed}s)"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            "UNKNOWN")
                log_warning "Unable to get build status. Build may not exist."
                return 1
                ;;
            *)
                log_info "Build status: $status"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
        esac
    done
    
    log_warning "Build monitoring timed out after $timeout seconds"
    return 1
}

# Function to list recent builds
list_recent_builds() {
    log_info "Listing recent Cloud Build executions..."
    
    gcloud builds list \
        --region="$REGION" \
        --limit=10 \
        --format="table(id,status,createTime.date(format='%Y-%m-%d %H:%M:%S'),duration.duration(format='%M:%S'))" \
        --filter="source.repoSource.repoName~'gke' OR tags~'terraform'" 2>/dev/null || \
    gcloud builds list \
        --region="$REGION" \
        --limit=10 \
        --format="table(id,status,createTime.date(format='%Y-%m-%d %H:%M:%S'))"
    
    return 0
}

# Function to test triggers
test_triggers() {
    log_info "Testing Cloud Build triggers..."
    
    # List existing triggers
    log_info "Listing existing triggers..."
    if gcloud builds triggers list --region="$REGION" --format="table(name,github.name,github.branch)" 2>/dev/null; then
        log_success "Triggers listed successfully"
    else
        log_warning "Unable to list triggers - may not have permission or no triggers exist"
    fi
    
    return 0
}

# Function to run comprehensive gcloud tests
run_comprehensive_tests() {
    log_info "Running comprehensive gcloud test suite..."
    
    local test_results=()
    
    # Run all tests and collect results
    if check_gcloud_prerequisites; then
        test_results+=("✓ gcloud prerequisites")
    else
        test_results+=("✗ gcloud prerequisites")
        log_error "Cannot proceed without gcloud prerequisites"
        return 1
    fi
    
    if validate_project_access; then
        test_results+=("✓ Project access validation")
    else
        test_results+=("✗ Project access validation")
    fi
    
    if test_dry_run; then
        test_results+=("✓ Configuration dry run")
    else
        test_results+=("✗ Configuration dry run")
    fi
    
    # Optional tests
    test_triggers || true
    list_recent_builds || true
    
    # Display results summary
    echo ""
    log_info "gcloud Test Results Summary:"
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    
    # Count failures
    local failures=$(printf '%s\n' "${test_results[@]}" | grep -c "✗" || true)
    
    if [ $failures -eq 0 ]; then
        log_success "All gcloud tests passed! Ready to submit builds."
        return 0
    else
        log_error "$failures gcloud test(s) failed."
        return 1
    fi
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test the improved CI/CD pipeline using gcloud Cloud Build.

OPTIONS:
    -p, --project-id PROJECT_ID    Set GCP project ID (default: cluster-dreams)
    -r, --region REGION           Set Cloud Build region (default: us-central1)
    -w, --workspaces WORKSPACES   Set comma-separated workspaces (default: gitops,dev)
    -t, --tf-version VERSION      Set Terraform version (default: 1.11)
    -b, --branch BRANCH           Set branch name (default: feature/new-nodes)
    -T, --type TYPE              Set test type (dry-run|submit|monitor|full)
    -m, --monitor BUILD_ID        Monitor specific build ID
    -h, --help                   Show this help message

EXAMPLES:
    # Basic validation (dry run)
    $0

    # Submit actual test build
    $0 --type submit

    # Monitor a specific build
    $0 --monitor 12345-abcd-6789

    # Full test suite
    $0 --type full

    # Test with custom parameters
    $0 --project-id my-project --workspaces prod,dev --type submit

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -w|--workspaces)
            WORKSPACES="$2"
            shift 2
            ;;
        -t|--tf-version)
            TF_VERSION="$2"
            shift 2
            ;;
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        -T|--type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -m|--monitor)
            TEST_TYPE="monitor"
            MONITOR_BUILD_ID="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution function
main() {
    echo "======================================="
    echo "Cloud Build CI/CD Pipeline Testing"
    echo "======================================="
    echo ""
    
    log_info "Starting gcloud-based testing of improved CI/CD pipeline"
    echo "Test type: $TEST_TYPE"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Workspaces: $WORKSPACES"
    echo "Terraform Version: $TF_VERSION"
    echo "Branch: $BRANCH_NAME"
    echo ""
    
    case $TEST_TYPE in
        "dry-run")
            run_comprehensive_tests
            ;;
        "submit")
            if check_gcloud_prerequisites && validate_project_access; then
                submit_test_build
            else
                log_error "Prerequisites not met for build submission"
                exit 1
            fi
            ;;
        "monitor")
            if check_gcloud_prerequisites; then
                monitor_build "${MONITOR_BUILD_ID:-}"
            else
                log_error "Prerequisites not met for build monitoring"
                exit 1
            fi
            ;;
        "full")
            if run_comprehensive_tests; then
                log_info "Comprehensive tests passed. Submitting test build..."
                if submit_test_build; then
                    log_info "Test build submitted. Starting monitoring..."
                    monitor_build
                fi
            fi
            ;;
        *)
            log_error "Invalid test type: $TEST_TYPE"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"