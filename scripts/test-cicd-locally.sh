#!/bin/bash

# Local CI/CD Pipeline Testing Script
# This script validates the improved CI/CD pipeline components locally

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID="${PROJECT_ID:-cluster-dreams}"
WORKSPACES="${WORKSPACES:-gitops,dev}"
TF_VERSION="${TF_VERSION:-1.11}"
TEST_MODE="validation" # Options: validation, generation, dry-run

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for required tools
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if ! command -v yamllint &> /dev/null; then
        missing_tools+=("yamllint")
    fi
    
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "yq")
                    echo "  brew install yq"
                    ;;
                "yamllint")
                    echo "  pip install yamllint"
                    ;;
                "python3")
                    echo "  brew install python3"
                    ;;
                "gcloud")
                    echo "  brew install --cask google-cloud-sdk"
                    ;;
            esac
        done
        return 1
    fi
    
    # Check Python packages
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_warning "PyYAML not installed. Installing..."
        pip3 install pyyaml
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# Function to validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    local errors=0
    
    if [ -z "$PROJECT_ID" ]; then
        log_error "PROJECT_ID is not set"
        errors=$((errors + 1))
    fi
    
    if [ -z "$WORKSPACES" ]; then
        log_error "WORKSPACES is not set"
        errors=$((errors + 1))
    fi
    
    if [ -z "$TF_VERSION" ]; then
        log_error "TF_VERSION is not set"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Environment variables validated"
        echo "  PROJECT_ID: $PROJECT_ID"
        echo "  WORKSPACES: $WORKSPACES"
        echo "  TF_VERSION: $TF_VERSION"
    else
        log_error "Environment validation failed with $errors errors"
        return 1
    fi
}

# Function to test Python script locally
test_python_script() {
    log_info "Testing Python script generation..."
    
    # Set environment variables for the script
    export WORKSPACES="$WORKSPACES"
    export TF_VERSION="$TF_VERSION"
    
    # Test the improved script
    if [ -f "generate_cloudbuild_improved.py" ]; then
        log_info "Testing improved Python script..."
        if python3 generate_cloudbuild_improved.py; then
            log_success "Python script executed successfully"
            
            # Check if output file was created
            if [ -f "cloudbuild.yaml" ]; then
                log_success "Generated YAML file created"
                
                # Display basic stats
                local steps_count=$(yq eval '.steps | length' cloudbuild.yaml)
                local timeout=$(yq eval '.timeout' cloudbuild.yaml)
                echo "  Generated steps: $steps_count"
                echo "  Timeout: $timeout"
                
                return 0
            else
                log_error "Generated YAML file not found"
                return 1
            fi
        else
            log_error "Python script execution failed"
            return 1
        fi
    else
        log_error "generate_cloudbuild_improved.py not found"
        return 1
    fi
}

# Function to validate generated YAML
validate_generated_yaml() {
    log_info "Validating generated YAML..."
    
    if [ ! -f "cloudbuild.yaml" ]; then
        log_error "cloudbuild.yaml not found"
        return 1
    fi
    
    # Validate YAML syntax
    if python3 -m yamllint -d relaxed cloudbuild.yaml; then
        log_success "YAML syntax validation passed"
    else
        log_error "YAML syntax validation failed"
        return 1
    fi
    
    # Validate YAML structure
    if yq eval '.' cloudbuild.yaml > /dev/null; then
        log_success "YAML structure validation passed"
    else
        log_error "YAML structure validation failed"
        return 1
    fi
    
    # Check required fields
    local checks=(
        "steps"
        "timeout"
        "options"
    )
    
    for field in "${checks[@]}"; do
        if yq eval ".$field" cloudbuild.yaml | grep -q "null"; then
            log_error "Required field '$field' is missing or null"
            return 1
        else
            log_success "Field '$field' is present"
        fi
    done
    
    return 0
}

# Function to test original script for comparison
test_original_script() {
    log_info "Testing original Python script for comparison..."
    
    if [ -f "generate_cloudbuild.py" ]; then
        export WORKSPACES="$WORKSPACES"
        export TF_VERSION="$TF_VERSION"
        
        # Backup any existing generated file
        if [ -f "cloudbuild_generated.yaml" ]; then
            mv cloudbuild_generated.yaml cloudbuild_generated_improved.yaml.bak
        fi
        
        if python3 generate_cloudbuild.py; then
            log_success "Original script executed successfully"
            
            if [ -f "cloudbuild_generated.yaml" ]; then
                mv cloudbuild_generated.yaml cloudbuild_generated_original.yaml
                log_success "Original generated file saved as cloudbuild_generated_original.yaml"
            fi
        else
            log_warning "Original script execution failed (this is expected if it has issues)"
        fi
        
        # Restore improved version
        if [ -f "cloudbuild_generated_improved.yaml.bak" ]; then
            mv cloudbuild_generated_improved.yaml.bak cloudbuild_generated.yaml
        fi
    else
        log_warning "Original generate_cloudbuild.py not found - skipping comparison"
    fi
}

# Function to compare configurations
compare_configurations() {
    log_info "Comparing original and improved configurations..."
    
    if [ -f "cloudbuild_generated_original.yaml" ] && [ -f "cloudbuild_generated.yaml" ]; then
        local original_steps=$(yq eval '.steps | length' cloudbuild_generated_original.yaml)
        local improved_steps=$(yq eval '.steps | length' cloudbuild_generated.yaml)
        
        echo "Configuration comparison:"
        echo "  Original steps: $original_steps"
        echo "  Improved steps: $improved_steps"
        
        # Show timeout comparison
        local original_timeout=$(yq eval '.timeout // "not set"' cloudbuild_generated_original.yaml)
        local improved_timeout=$(yq eval '.timeout' cloudbuild_generated.yaml)
        
        echo "  Original timeout: $original_timeout"
        echo "  Improved timeout: $improved_timeout"
        
        log_success "Configuration comparison completed"
    else
        log_warning "Cannot compare - missing original or improved configuration"
    fi
}

# Function to test Cloud Build YAML validation
test_cloudbuild_yaml() {
    log_info "Testing Cloud Build YAML configurations..."
    
    # Test improved cloudbuild.yaml
    if [ -f "cloudbuild.yaml" ]; then
        log_info "Validating cloudbuild.yaml..."
        
        if python3 -m yamllint -d relaxed cloudbuild.yaml; then
            log_success "cloudbuild.yaml syntax is valid"
        else
            log_error "cloudbuild.yaml syntax validation failed"
            return 1
        fi
        
        # Check required Cloud Build fields
        local cb_checks=(
            "steps"
            "timeout"
            "options"
            "substitutions"
        )
        
        for field in "${cb_checks[@]}"; do
            if yq eval ".$field" cloudbuild.yaml | grep -q "null"; then
                log_error "Required Cloud Build field '$field' is missing"
                return 1
            else
                log_success "Cloud Build field '$field' is present"
            fi
        done
    else
        log_error "cloudbuild.yaml not found"
        return 1
    fi
    
    return 0
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    log_info "Running comprehensive test suite..."
    
    local test_results=()
    
    # Run all tests and collect results
    if check_prerequisites; then
        test_results+=("✓ Prerequisites check")
    else
        test_results+=("✗ Prerequisites check")
    fi
    
    if validate_environment; then
        test_results+=("✓ Environment validation")
    else
        test_results+=("✗ Environment validation")
    fi
    
    if test_python_script; then
        test_results+=("✓ Python script generation")
    else
        test_results+=("✗ Python script generation")
    fi
    
    if validate_generated_yaml; then
        test_results+=("✓ Generated YAML validation")
    else
        test_results+=("✗ Generated YAML validation")
    fi
    
    if test_cloudbuild_yaml; then
        test_results+=("✓ Cloud Build YAML validation")
    else
        test_results+=("✗ Cloud Build YAML validation")
    fi
    
    # Optional comparison test
    test_original_script || true
    compare_configurations || true
    
    # Display results summary
    echo ""
    log_info "Test Results Summary:"
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    
    # Count failures
    local failures=$(printf '%s\n' "${test_results[@]}" | grep -c "✗" || true)
    
    if [ $failures -eq 0 ]; then
        log_success "All tests passed! The CI/CD pipeline is ready for deployment."
        return 0
    else
        log_error "$failures test(s) failed. Please review the errors above."
        return 1
    fi
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test and validate the improved CI/CD pipeline locally.

OPTIONS:
    -p, --project-id PROJECT_ID    Set the GCP project ID (default: cluster-dreams)
    -w, --workspaces WORKSPACES    Set comma-separated workspaces (default: gitops,dev)
    -t, --tf-version VERSION       Set Terraform version (default: 1.11)
    -m, --mode MODE               Set test mode (validation|generation|dry-run)
    -h, --help                    Show this help message

EXAMPLES:
    # Basic validation
    $0

    # Test with specific project and workspaces
    $0 --project-id my-project --workspaces prod,staging,dev

    # Test with different Terraform version
    $0 --tf-version 1.5.0

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
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
        -m|--mode)
            TEST_MODE="$2"
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

# Main execution
main() {
    echo "==================================="
    echo "CI/CD Pipeline Local Testing Script"
    echo "==================================="
    echo ""
    
    log_info "Starting local validation of improved CI/CD pipeline"
    echo "Test mode: $TEST_MODE"
    echo "Project ID: $PROJECT_ID"
    echo "Workspaces: $WORKSPACES"
    echo "Terraform Version: $TF_VERSION"
    echo ""
    
    case $TEST_MODE in
        "validation")
            run_comprehensive_tests
            ;;
        "generation")
            test_python_script && validate_generated_yaml
            ;;
        "dry-run")
            log_info "Dry run mode - checking prerequisites only"
            check_prerequisites && validate_environment
            ;;
        *)
            log_error "Invalid test mode: $TEST_MODE"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"