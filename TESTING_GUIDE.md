# CI/CD Pipeline Testing Guide

This guide provides comprehensive instructions for testing and validating the improved CI/CD pipeline both locally and in Google Cloud Build.

## 📋 **Testing Overview**

The testing strategy includes:
1. **Local Validation**: Test components without Cloud Build resources
2. **Cloud Build Testing**: Validate using actual Google Cloud resources
3. **Integration Testing**: End-to-end pipeline validation
4. **Performance Testing**: Monitor and optimize build performance

## 🛠️ **Prerequisites**

### **Local Testing Prerequisites**
```bash
# Install required tools
brew install python3 yq yamllint
pip3 install pyyaml

# Optional: Install gcloud for comprehensive testing
brew install --cask google-cloud-sdk
```

### **Cloud Build Prerequisites**
```bash
# Authenticate with Google Cloud
gcloud auth login

# Set your project
gcloud config set project cluster-dreams

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
```

## 🧪 **Testing Methods**

### **Method 1: Local Validation (Recommended for Development)**

The local testing script validates the Python code and YAML generation without using Cloud resources.

#### **Basic Local Validation**
```bash
# Test with default settings
./test_cicd_locally.sh

# Test with custom workspaces
./test_cicd_locally.sh --workspaces "prod,staging,dev" --tf-version "1.5.0"

# Dry run (check prerequisites only)
./test_cicd_locally.sh --mode dry-run
```

#### **Local Test Options**
```bash
# Available test modes
./test_cicd_locally.sh --mode validation    # Full validation suite (default)
./test_cicd_locally.sh --mode generation    # Test YAML generation only
./test_cicd_locally.sh --mode dry-run       # Check prerequisites only

# Custom parameters
./test_cicd_locally.sh \
    --project-id "my-project" \
    --workspaces "gitops,dev,staging" \
    --tf-version "1.11"
```

#### **What Local Testing Validates**
- ✅ Python script syntax and execution
- ✅ YAML generation and structure
- ✅ Input validation and sanitization  
- ✅ Error handling and edge cases
- ✅ Configuration file syntax
- ✅ Dependencies and prerequisites

### **Method 2: Cloud Build Testing (Integration Testing)**

The gcloud testing script validates the pipeline using actual Google Cloud Build.

#### **Basic Cloud Build Validation**
```bash
# Dry run validation (no actual build)
./test_cicd_gcloud.sh

# Submit test build
./test_cicd_gcloud.sh --type submit

# Full test suite with monitoring
./test_cicd_gcloud.sh --type full
```

#### **Cloud Build Test Options**
```bash
# Available test types
./test_cicd_gcloud.sh --type dry-run    # Validate config without building
./test_cicd_gcloud.sh --type submit     # Submit actual test build
./test_cicd_gcloud.sh --type monitor    # Monitor specific build
./test_cicd_gcloud.sh --type full       # Complete test with monitoring

# Monitor specific build
./test_cicd_gcloud.sh --monitor "12345-abcd-6789"

# Custom parameters
./test_cicd_gcloud.sh \
    --project-id "cluster-dreams" \
    --region "us-central1" \
    --workspaces "gitops,dev" \
    --type submit
```

#### **What Cloud Build Testing Validates**
- ✅ Google Cloud authentication and permissions
- ✅ Cloud Build API access and configuration
- ✅ Build submission and execution
- ✅ Real-world resource constraints
- ✅ Integration with Google Cloud services
- ✅ Build monitoring and logging

## 📊 **Test Scenarios**

### **Scenario 1: Development Workflow**
Test the typical development workflow with pull requests:

```bash
# Local validation first
./test_cicd_locally.sh --mode validation

# If local tests pass, test cloud integration
./test_cicd_gcloud.sh --type dry-run
```

### **Scenario 2: Production Deployment**
Test production-ready configuration:

```bash
# Test with production workspaces
./test_cicd_locally.sh --workspaces "prod,staging" --tf-version "1.11"

# Submit production test build
./test_cicd_gcloud.sh --workspaces "prod,staging" --type submit
```

### **Scenario 3: Multi-environment Testing**
Test with multiple environments:

```bash
# Test all environments
./test_cicd_locally.sh --workspaces "dev,staging,prod,gitops"

# Cloud build test with monitoring
./test_cicd_gcloud.sh --workspaces "dev,staging,prod,gitops" --type full
```

### **Scenario 4: Error Handling Validation**
Test error conditions:

```bash
# Test with invalid workspace names
./test_cicd_locally.sh --workspaces "invalid workspace name"

# Test with missing project
./test_cicd_gcloud.sh --project-id "non-existent-project" --type dry-run
```

## 🔍 **Manual Testing Commands**

### **Direct Python Testing**
```bash
# Test Python script directly
export WORKSPACES="gitops,dev"
export TF_VERSION="1.11"
python3 generate_cloudbuild_improved.py

# Validate generated output
yq eval '.' cloudbuild_generated.yaml
yamllint cloudbuild_generated.yaml
```

### **Direct gcloud Commands**
```bash
# Test configuration syntax
gcloud builds submit --config=cloudbuild_improved.yaml \
    --no-source \
    --substitutions="_WORKSPACES=gitops,dev,_TF_VERSION=1.11"

# Submit test build
gcloud builds submit --config=cloudbuild_improved.yaml \
    --region=us-central1 \
    --substitutions="_WORKSPACES=gitops,dev,_TF_VERSION=1.11" \
    --async

# Monitor build
gcloud builds log BUILD_ID --region=us-central1
```

## 📈 **Performance Testing**

### **Measure Build Performance**
```bash
# Time the local generation
time ./test_cicd_locally.sh --mode generation

# Monitor cloud build times
./test_cicd_gcloud.sh --type full | grep -E "(elapsed|duration)"
```

### **Resource Usage Testing**
```bash
# Test with different machine types in cloudbuild_improved.yaml
# Edit options.machineType: E2_STANDARD_4, E2_HIGHCPU_8, etc.

# Test with different parallelism settings
# Edit terraform parallelism in generated scripts
```

## 🚨 **Troubleshooting Common Issues**

### **Local Testing Issues**

#### **Missing Dependencies**
```bash
# Install missing Python packages
pip3 install pyyaml

# Install missing system tools (macOS)
brew install yq yamllint

# Install gcloud CLI
brew install --cask google-cloud-sdk
```

#### **Permission Errors**
```bash
# Make scripts executable
chmod +x test_cicd_locally.sh test_cicd_gcloud.sh

# Fix Python import issues
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
```

### **Cloud Build Testing Issues**

#### **Authentication Problems**
```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login

# Check current auth status
gcloud auth list
```

#### **Project Access Issues**
```bash
# Set correct project
gcloud config set project cluster-dreams

# Verify project access
gcloud projects describe cluster-dreams

# Check IAM permissions
gcloud projects get-iam-policy cluster-dreams
```

#### **API Enablement**
```bash
# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com

# Check enabled services
gcloud services list --enabled
```

### **Build Failure Analysis**

#### **Get Build Logs**
```bash
# List recent builds
gcloud builds list --limit=10

# Get specific build logs
gcloud builds log BUILD_ID --region=us-central1

# Describe build details
gcloud builds describe BUILD_ID --region=us-central1
```

#### **Common Build Issues**
1. **Timeout Errors**: Increase timeout values in configurations
2. **Resource Constraints**: Use higher machine types
3. **Permission Errors**: Check service account IAM roles
4. **Network Issues**: Verify VPC and firewall settings

## 📋 **Test Checklist**

### **Before Deployment**
- [ ] Local validation passes all tests
- [ ] Python script generates valid YAML
- [ ] YAML syntax validation passes
- [ ] gcloud authentication is working
- [ ] Project permissions are sufficient
- [ ] Required APIs are enabled

### **During Testing**
- [ ] Test builds submit successfully
- [ ] Build monitoring works correctly
- [ ] Error handling behaves as expected
- [ ] Performance meets requirements
- [ ] Logs are comprehensive and helpful

### **After Deployment**
- [ ] Production builds work correctly
- [ ] Monitoring and alerting function
- [ ] Rollback procedures are tested
- [ ] Documentation is updated

## 🔄 **Continuous Testing Strategy**

### **Daily Testing**
```bash
# Quick validation
./test_cicd_locally.sh --mode dry-run
```

### **Weekly Testing**
```bash
# Full local validation
./test_cicd_locally.sh

# Cloud integration test
./test_cicd_gcloud.sh --type dry-run
```

### **Pre-deployment Testing**
```bash
# Comprehensive test suite
./test_cicd_locally.sh --mode validation
./test_cicd_gcloud.sh --type full
```

## 📊 **Test Results Interpretation**

### **Success Indicators**
- ✅ All test functions return success codes
- ✅ Generated YAML is valid and complete
- ✅ Cloud builds submit and complete successfully
- ✅ No errors in build logs
- ✅ Performance metrics meet expectations

### **Warning Signs**
- ⚠️ Intermittent test failures
- ⚠️ Slow build times
- ⚠️ Authentication warnings
- ⚠️ Resource constraint warnings

### **Failure Indicators**
- ❌ Test scripts exit with error codes
- ❌ Invalid YAML generation
- ❌ Build submission failures
- ❌ Consistent timeout errors
- ❌ Permission denied errors

## 🚀 **Next Steps After Testing**

1. **If all tests pass**: Deploy the improved pipeline
2. **If tests fail**: Review errors, fix issues, and retest
3. **If performance issues**: Optimize configurations and retry
4. **If integration issues**: Check cloud resources and permissions

## 📚 **Additional Resources**

- [Local Testing Script](./test_cicd_locally.sh)
- [gcloud Testing Script](./test_cicd_gcloud.sh)
- [CI/CD Improvements Documentation](./CICD_IMPROVEMENTS.md)
- [Google Cloud Build Documentation](https://cloud.google.com/build/docs)