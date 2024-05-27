import os
import yaml

workspaces = os.getenv('_WORKSPACES', 'dev,staging,gitops').split(',')

steps = []

# Branch name step
steps.append({
    'id': 'branch name',
    'name': 'ubuntu',
    'script': """
      #!/bin/sh
      echo "***********************"
      echo "Branch Name: $BRANCH_NAME"
      echo "***********************"
    """
})

# Setup and plan steps
for workspace in workspaces:
    steps.append({
        'id': f'setup and plan {workspace}',
        'name': f'hashicorp/terraform:{os.getenv("_TF_VERSION", "1.8")}',
        'script': f"""
          #!/bin/sh
          echo "Branch Name inside setup and plan step: $BRANCH_NAME"
          if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
            echo "Processing workspace: {workspace}"
            mkdir -p /workspace/$BUILD_ID/{workspace}
            terraform init -reconfigure
            terraform workspace select {workspace} || terraform workspace new {workspace}
            terraform validate
            terraform plan -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID" -out=/workspace/$BUILD_ID/tfplan_{workspace}
          else
            echo "Skipping setup and plan on branch $BRANCH_NAME"
          fi
        """
    })

# Apply steps
for workspace in workspaces:
    steps.append({
        'id': f'apply {workspace}',
        'name': f'hashicorp/terraform:{os.getenv("_TF_VERSION", "1.8")}',
        'waitFor': [f'setup and plan {workspace}'],
        'script': f"""
          #!/bin/sh
          echo "Branch Name inside apply step: $BRANCH_NAME"
          if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
            echo "Applying Terraform plan for workspace: {workspace}"
            terraform init -reconfigure
            terraform workspace select {workspace} || terraform workspace new {workspace}
            terraform apply -auto-approve /workspace/$BUILD_ID/tfplan_{workspace}
          else
            echo "Skipping apply on branch $BRANCH_NAME"
          fi
        """
    })

# Destroy steps
for workspace in workspaces:
    steps.append({
        'id': f'destroy {workspace}',
        'name': f'hashicorp/terraform:{os.getenv("_TF_VERSION", "1.8")}',
        'script': f"""
          #!/bin/sh
          echo "Branch Name inside destroy step: $BRANCH_NAME"
          if [ "$BRANCH_NAME" = "destroy-all" ]; then
            echo "Destroying resources in workspace: {workspace}"
            terraform init -reconfigure
            terraform workspace select {workspace} || terraform workspace new {workspace}
            terraform destroy -auto-approve -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID"
          else
            echo "Destroy operation not allowed on this branch."
          fi
        """
    })

cloudbuild_config = {
    'steps': steps,
    'substitutions': {
        '_TF_VERSION': os.getenv('_TF_VERSION', '1.8'),
        '_WORKSPACES': ','.join(workspaces)
    },
    'options': {
        'dynamicSubstitutions': True,
        'automapSubstitutions': True
    }
}

with open('cloudbuild_generated.yaml', 'w') as f:
    yaml.dump(cloudbuild_config, f)
