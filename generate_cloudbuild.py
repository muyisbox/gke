import yaml
import os

workspaces = '${_WORKSPACES}'.split(',')

steps = [
    {
        'id': 'branch name',
        'name': 'ubuntu',
        'entrypoint': 'bash',
        'args': [
            '-c',
            'echo "************************"; echo "Branch Name: $BRANCH_NAME"; echo "************************"'
        ]
    },
]

for workspace in workspaces:
    steps.extend([
        {
            'id': f'setup and plan {workspace}',
            'name': 'hashicorp/terraform:${_TF_VERSION}',
            'entrypoint': 'sh',
            'args': [
                '-c',
                f'''
                echo "Branch Name inside setup and plan step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                    echo "Processing workspace: {workspace}"
                    terraform init -reconfigure
                    if ! terraform workspace select {workspace}; then
                        terraform workspace new {workspace}
                    fi
                    terraform validate
                    terraform plan -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID" -out=/workspace/$BUILD_ID/tfplan_{workspace}
                else
                    echo "Skipping setup and plan on branch $BRANCH_NAME"
                fi
                '''
            ]
        },
        {
            'id': f'apply {workspace}',
            'name': 'hashicorp/terraform:${_TF_VERSION}',
            'waitFor': [f'setup and plan {workspace}'],
            'entrypoint': 'sh',
            'args': [
                '-c',
                f'''
                echo "Branch Name inside apply step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                    echo "Applying Terraform plan for workspace: {workspace}"
                    if ! terraform workspace select {workspace}; then
                        terraform workspace new {workspace}
                    fi
                    terraform apply -auto-approve /workspace/$BUILD_ID/tfplan_{workspace}
                else
                    echo "Skipping apply on branch $BRANCH_NAME"
                fi
                '''
            ]
        },
        {
            'id': f'destroy {workspace}',
            'name': 'hashicorp/terraform:${_TF_VERSION}',
            'entrypoint': 'sh',
            'args': [
                '-c',
                f'''
                echo "Branch Name inside destroy step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "destroy-all" ]; then
                    echo "Preparing to destroy all resources..."
                    echo "Auto-confirming destruction"
                    echo "Destroying resources in workspace: {workspace}"
                    if ! terraform workspace select {workspace}; then
                        terraform workspace new {workspace}
                    fi
                    terraform init -reconfigure
                    terraform destroy -auto-approve -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID"
                else
                    echo "Destroy operation not allowed on this branch."
                fi
                '''
            ]
        }
    ])

cloudbuild = {
    'steps': steps,
    'options': {
        'dynamicSubstitutions': True,
        'automapSubstitutions': True
    }
}

with open('cloudbuild_generated.yaml', 'w') as file:
    yaml.dump(cloudbuild, file)