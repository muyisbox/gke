#!/usr/bin/env python3
"""
Enhanced Cloud Build Generator for Terraform CI/CD Pipeline
Generates dynamic Cloud Build configurations with improved error handling,
security, and maintainability.
"""

import os
import sys
import yaml
import re
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class CloudBuildGenerator:
    """Enhanced Cloud Build configuration generator with improved features."""
    
    def __init__(self, tf_version: str = "1.11", timeout: str = "3600s"):
        self.tf_version = self._validate_tf_version(tf_version)
        self.timeout = timeout
        self.build_options = {
            'substitutionOption': 'ALLOW_LOOSE',
            'logging': 'CLOUD_LOGGING_ONLY',
            'logStreamingOption': 'STREAM_ON',
            'machineType': 'E2_HIGHCPU_8',  # Better performance
        }
    
    def _validate_tf_version(self, version: str) -> str:
        """Validate Terraform version format."""
        if not re.match(r'^\d+\.\d+(\.\d+)?$', version):
            raise ValueError(f"Invalid Terraform version format: {version}")
        return version
    
    def _validate_workspace_name(self, workspace: str) -> str:
        """Validate and sanitize workspace name."""
        if not workspace or not isinstance(workspace, str):
            raise ValueError("Workspace name must be a non-empty string")
        
        # Sanitize workspace name
        sanitized = re.sub(r'[^a-zA-Z0-9\-_]', '-', workspace.strip().lower())
        if len(sanitized) > 63:  # GCP resource name limit
            sanitized = sanitized[:63]
        
        if not re.match(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?$', sanitized):
            raise ValueError(f"Invalid workspace name after sanitization: {sanitized}")
        
        return sanitized
    
    def _create_workspace_setup_script(self, workspace: str) -> str:
        """Create robust workspace setup script with proper error handling."""
        return f'''
set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Workspace management with exponential backoff
setup_workspace() {{
    local workspace_name="{workspace}"
    local wait_time=5
    local max_wait_time=120
    local max_attempts=10
    local attempt=1
    
    echo "Setting up workspace: $workspace_name"
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts to setup workspace"
        
        # Try to select existing workspace
        if terraform workspace select "$workspace_name" 2>/dev/null; then
            echo "Successfully selected existing workspace: $workspace_name"
            return 0
        fi
        
        # Try to create new workspace
        if terraform workspace new "$workspace_name" 2>/dev/null; then
            echo "Successfully created new workspace: $workspace_name"
            return 0
        fi
        
        echo "Workspace setup failed. Waiting $wait_time seconds before retry..."
        sleep $wait_time
        
        # Exponential backoff with jitter
        wait_time=$((wait_time * 2))
        if [ $wait_time -gt $max_wait_time ]; then
            wait_time=$max_wait_time
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "Failed to setup workspace after $max_attempts attempts"
    exit 1
}}

# Initialize Terraform with retry logic
init_terraform() {{
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Initializing Terraform (attempt $attempt/$max_attempts)"
        
        if terraform init -reconfigure -input=false; then
            echo "Terraform initialization successful"
            return 0
        fi
        
        echo "Terraform init failed. Attempt $attempt/$max_attempts"
        attempt=$((attempt + 1))
        
        if [ $attempt -le $max_attempts ]; then
            sleep 10
        fi
    done
    
    echo "Terraform initialization failed after $max_attempts attempts"
    exit 1
}}

# Main execution
init_terraform
setup_workspace
'''
    
    def _create_validation_script(self) -> str:
        """Create comprehensive validation script."""
        return '''
set -euo pipefail

echo "Running Terraform validation..."

# Check Terraform configuration syntax
echo "Checking configuration syntax..."
terraform validate

# Check for formatting issues
echo "Checking formatting..."
if ! terraform fmt -check -recursive; then
    echo "Warning: Terraform files are not properly formatted"
    echo "Run 'terraform fmt -recursive' to fix formatting issues"
fi

# Security scan (if tfsec is available)
if command -v tfsec &> /dev/null; then
    echo "Running security scan..."
    tfsec . --soft-fail
fi

echo "Validation completed successfully"
'''
    
    def _create_plan_script(self, workspace: str, plan_path: str) -> str:
        """Create enhanced plan script with validation and output."""
        return f'''
set -euo pipefail

workspace_name="{workspace}"
plan_file="{plan_path}"
plan_output="/tmp/plan_output_${{workspace_name}}.txt"

echo "Creating Terraform plan for workspace: $workspace_name"

# Create plan directory
mkdir -p "$(dirname "$plan_file")"

# Generate plan with detailed output
terraform plan \\
    -detailed-exitcode \\
    -parallelism=30 \\
    -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" \\
    -var="project_id=$PROJECT_ID" \\
    -out="$plan_file" \\
    | tee "$plan_output"

# Check plan exit code
plan_exit_code=$?

case $plan_exit_code in
    0)
        echo "No changes detected in plan"
        echo "PLAN_STATUS=NO_CHANGES" >> $BUILD_ID-status.env
        ;;
    1)
        echo "Plan failed"
        exit 1
        ;;
    2)
        echo "Plan succeeded with changes"
        echo "PLAN_STATUS=HAS_CHANGES" >> $BUILD_ID-status.env
        
        # Extract plan summary
        echo "Plan Summary:" >> $BUILD_ID-plan-summary.txt
        grep -E "(Plan:|Changes to Outputs:)" "$plan_output" >> $BUILD_ID-plan-summary.txt || true
        ;;
esac

echo "Plan created successfully: $plan_file"
'''
    
    def _create_apply_script(self, workspace: str, plan_path: str) -> str:
        """Create enhanced apply script with validation and rollback preparation."""
        return f'''
set -euo pipefail

workspace_name="{workspace}"
plan_file="{plan_path}"

echo "Applying Terraform plan for workspace: $workspace_name"

# Verify plan file exists
if [ ! -f "$plan_file" ]; then
    echo "Error: Plan file not found: $plan_file"
    exit 1
fi

# Create backup of current state
echo "Creating state backup..."
terraform state pull > "/tmp/terraform_${{workspace_name}}_backup_${{BUILD_ID}}.tfstate"

# Apply with monitoring
echo "Starting Terraform apply..."
start_time=$(date +%s)

if terraform apply \\
    -parallelism=30 \\
    -auto-approve \\
    -input=false \\
    "$plan_file"; then
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "Apply completed successfully in $duration seconds"
    echo "APPLY_STATUS=SUCCESS" >> $BUILD_ID-status.env
    echo "APPLY_DURATION=$duration" >> $BUILD_ID-status.env
    
    # Verify deployment
    echo "Verifying deployment..."
    terraform output -json > "/tmp/terraform_outputs_${{workspace_name}}_${{BUILD_ID}}.json"
    
else
    echo "Apply failed for workspace: $workspace_name"
    echo "APPLY_STATUS=FAILED" >> $BUILD_ID-status.env
    
    # Restore from backup if needed (optional)
    echo "Consider restoring from backup if needed:"
    echo "  terraform state push /tmp/terraform_${{workspace_name}}_backup_${{BUILD_ID}}.tfstate"
    
    exit 1
fi
'''
    
    def _create_destroy_script(self, workspace: str) -> str:
        """Create enhanced destroy script with safety checks."""
        return f'''
set -euo pipefail

workspace_name="{workspace}"

echo "DANGER: Preparing to destroy resources in workspace: $workspace_name"

# Safety checks
if [ "$BRANCH_NAME" != "destroy-all" ] && [ "$BRANCH_NAME" != "cleanup" ]; then
    echo "Error: Destroy operations are only allowed on 'destroy-all' or 'cleanup' branches"
    echo "Current branch: $BRANCH_NAME"
    exit 1
fi

# Additional confirmation for production workspaces
if [[ "$workspace_name" == *"prod"* ]] || [[ "$workspace_name" == *"production"* ]]; then
    if [ -z "${{CONFIRM_DESTROY_PROD:-}}" ]; then
        echo "Error: Production workspace destruction requires CONFIRM_DESTROY_PROD=true"
        exit 1
    fi
fi

# Create pre-destroy backup
echo "Creating pre-destroy backup..."
terraform state pull > "/tmp/terraform_${{workspace_name}}_predestroy_${{BUILD_ID}}.tfstate"

# Show what will be destroyed
echo "Resources to be destroyed:"
terraform plan -destroy \\
    -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" \\
    -var="project_id=$PROJECT_ID"

# Execute destroy
echo "Starting destruction process..."
start_time=$(date +%s)

if terraform destroy \\
    -auto-approve \\
    -parallelism=30 \\
    -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" \\
    -var="project_id=$PROJECT_ID"; then
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "Destroy completed successfully in $duration seconds"
    echo "DESTROY_STATUS=SUCCESS" >> $BUILD_ID-status.env
    
else
    echo "Destroy failed for workspace: $workspace_name"
    echo "DESTROY_STATUS=FAILED" >> $BUILD_ID-status.env
    echo "Backup available at: /tmp/terraform_${{workspace_name}}_predestroy_${{BUILD_ID}}.tfstate"
    exit 1
fi
'''
    
    def generate_steps(self, workspaces: List[str]) -> List[Dict[str, Any]]:
        """Generate improved Cloud Build steps."""
        steps = []
        
        # Initial setup step
        steps.append({
            'name': 'ubuntu:22.04',
            'id': 'environment-info',
            'entrypoint': 'bash',
            'args': [
                '-c',
                '''
                echo "=== Build Environment Information ==="
                echo "Build ID: $BUILD_ID"
                echo "Branch Name: $BRANCH_NAME"
                echo "Pull Request: ${{_PR_NUMBER:-'N/A'}}"
                echo "Project ID: $PROJECT_ID"
                echo "Region: ${LOCATION:-'N/A'}"
                echo "Trigger Name: ${TRIGGER_NAME:-'N/A'}"
                echo "Repository: ${REPO_FULL_NAME:-'N/A'}"
                echo "Commit SHA: ${COMMIT_SHA:-'N/A'}"
                echo "=================================="
                
                # Create status tracking file
                echo "BUILD_START=$(date -Iseconds)" > $BUILD_ID-status.env
                echo "WORKSPACES=${{_WORKSPACES}}" >> $BUILD_ID-status.env
                '''
            ],
            'timeout': '60s'
        })
        
        # Process each workspace
        for workspace in workspaces:
            workspace_safe = self._validate_workspace_name(workspace)
            plan_path = f"/workspace/$BUILD_ID/tfplan_{workspace_safe}"
            
            # Setup and validation step
            steps.append({
                'id': f'setup-{workspace_safe}',
                'name': f'hashicorp/terraform:{self.tf_version}',
                'entrypoint': 'bash',
                'args': [
                    '-c',
                    f'''
                    echo "Setting up workspace: {workspace_safe}"
                    
                    # Branch protection
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "${{_PR_NUMBER:-}}" ]; then
                        {self._create_workspace_setup_script(workspace_safe)}
                        {self._create_validation_script()}
                    else
                        echo "Skipping setup on branch $BRANCH_NAME"
                        exit 0
                    fi
                    '''
                ],
                'timeout': '600s'
            })
            
            # Plan step
            steps.append({
                'id': f'plan-{workspace_safe}',
                'name': f'hashicorp/terraform:{self.tf_version}',
                'waitFor': [f'setup-{workspace_safe}'],
                'entrypoint': 'bash',
                'args': [
                    '-c',
                    f'''
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "${{_PR_NUMBER:-}}" ]; then
                        echo "Creating plan for workspace: {workspace_safe}"
                        {self._create_workspace_setup_script(workspace_safe)}
                        {self._create_plan_script(workspace_safe, plan_path)}
                    else
                        echo "Skipping plan on branch $BRANCH_NAME"
                    fi
                    '''
                ],
                'timeout': '1200s'
            })
            
            # Apply step (only on main/master)
            steps.append({
                'id': f'apply-{workspace_safe}',
                'name': f'hashicorp/terraform:{self.tf_version}',
                'waitFor': [f'plan-{workspace_safe}'],
                'entrypoint': 'bash',
                'args': [
                    '-c',
                    f'''
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                        echo "Applying plan for workspace: {workspace_safe}"
                        {self._create_workspace_setup_script(workspace_safe)}
                        {self._create_apply_script(workspace_safe, plan_path)}
                    else
                        echo "Skipping apply on branch $BRANCH_NAME (only runs on main/master)"
                    fi
                    '''
                ],
                'timeout': '2400s'
            })
            
            # Destroy step (special branches only)
            steps.append({
                'id': f'destroy-{workspace_safe}',
                'name': f'hashicorp/terraform:{self.tf_version}',
                'entrypoint': 'bash',
                'args': [
                    '-c',
                    f'''
                    if [ "$BRANCH_NAME" = "destroy-all" ] || [ "$BRANCH_NAME" = "cleanup" ]; then
                        echo "Destroying resources in workspace: {workspace_safe}"
                        {self._create_workspace_setup_script(workspace_safe)}
                        {self._create_destroy_script(workspace_safe)}
                    else
                        echo "Destroy not allowed on branch $BRANCH_NAME"
                    fi
                    '''
                ],
                'timeout': '1800s'
            })
        
        # Final status step
        steps.append({
            'name': 'ubuntu:22.04',
            'id': 'build-summary',
            'waitFor': [f'apply-{self._validate_workspace_name(ws)}' for ws in workspaces],
            'entrypoint': 'bash',
            'args': [
                '-c',
                '''
                echo "=== Build Summary ==="
                if [ -f "$BUILD_ID-status.env" ]; then
                    cat $BUILD_ID-status.env
                fi
                
                echo "BUILD_END=$(date -Iseconds)" >> $BUILD_ID-status.env
                echo "Build completed at $(date)"
                echo "===================="
                '''
            ],
            'timeout': '60s'
        })
        
        return steps
    
    def generate_cloudbuild_config(self, workspaces: List[str]) -> Dict[str, Any]:
        """Generate complete Cloud Build configuration."""
        try:
            validated_workspaces = [self._validate_workspace_name(ws) for ws in workspaces]
            steps = self.generate_steps(validated_workspaces)
            
            config = {
                'steps': steps,
                'timeout': self.timeout,
                'options': self.build_options,
                'substitutions': {
                    '_PR_NUMBER': '',
                    '_WORKSPACE': 'default',
                    '_TERRAFORM_VERSION': self.tf_version
                },
                'availableSecrets': {
                    'secretManager': [
                        {
                            'versionName': 'projects/$PROJECT_ID/secrets/terraform-service-account/versions/latest',
                            'env': 'GOOGLE_CREDENTIALS'
                        }
                    ]
                },
                'artifacts': {
                    'objects': {
                        'location': 'gs://$PROJECT_ID-terraform-state/build-artifacts',
                        'paths': [
                            '$BUILD_ID-status.env',
                            '$BUILD_ID-plan-summary.txt',
                            '/tmp/terraform_*_$BUILD_ID.*'
                        ]
                    }
                }
            }
            
            return config
            
        except Exception as e:
            logger.error(f"Failed to generate Cloud Build config: {str(e)}")
            raise


def main():
    """Main entry point."""
    try:
        # Get environment variables with validation
        workspaces_env = os.getenv('WORKSPACES', '')
        tf_version = os.getenv('TF_VERSION', '1.11')
        
        if not workspaces_env:
            raise ValueError("WORKSPACES environment variable is required")
        
        workspaces = [ws.strip() for ws in workspaces_env.split(',') if ws.strip()]
        if not workspaces:
            raise ValueError("At least one workspace must be specified")
        
        logger.info(f"Generating Cloud Build config for workspaces: {workspaces}")
        logger.info(f"Using Terraform version: {tf_version}")
        
        # Generate configuration
        generator = CloudBuildGenerator(tf_version)
        cloudbuild_config = generator.generate_cloudbuild_config(workspaces)
        
        # Write configuration file
        output_file = Path('cloudbuild.yaml')
        with output_file.open('w') as file:
            yaml.dump(
                cloudbuild_config,
                file,
                default_flow_style=False,
                sort_keys=False,
                indent=2
            )
        
        logger.info(f"Successfully generated {output_file}")
        
        # Validate the generated YAML
        with output_file.open('r') as file:
            yaml.safe_load(file)
        logger.info("Generated YAML is valid")
        
    except Exception as e:
        logger.error(f"Failed to generate Cloud Build configuration: {str(e)}")
        sys.exit(1)


if __name__ == '__main__':
    main()