import os
import yaml

def generate_cloudbuild():
    workspaces = os.environ.get('_WORKSPACES', 'dev,staging,gitops').split(',')
    tf_version = os.environ.get('_TF_VERSION', '1.8')
    pr_number = os.getenv('_PR_NUMBER', '')  # Use directly from environment

    steps = [
        {
            'id': 'branch name',
            'name': 'ubuntu',
            'entrypoint': 'sh',
            'args': [
                '-c',
                f'echo "************************"; echo "Branch Name: $BRANCH_NAME"; echo "Pull Request: {pr_number}"; echo "************************"'
            ]
        }
    ]

    for workspace in workspaces:
        steps.extend([
            {
                'id': f'setup and plan {workspace}',
                'name': f'hashicorp/terraform:{tf_version}',
                'entrypoint': 'bash',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside setup and plan step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "{pr_number}" ]; then
                        echo "Processing workspace: {workspace}"
                        terraform init -reconfigure
                        
                        # Create workspace if it doesn't exist
                        terraform workspace new {workspace} || terraform workspace select {workspace}
                        
                        # Wait for state lock
                        while ! terraform workspace select {workspace}; do
                            echo "Workspace {workspace} is locked. Waiting for 10 seconds..."
                            sleep 10
                        done
                        
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
                'name': f'hashicorp/terraform:{tf_version}',
                'waitFor': [f'setup and plan {workspace}'],
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside apply step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                        echo "Applying Terraform plan for workspace: {workspace}"
                        terraform init -reconfigure
                        
                        # Create workspace if it doesn't exist
                        terraform workspace new {workspace} || terraform workspace select {workspace}
                        
                        # Wait for state lock
                        while ! terraform workspace select {workspace}; do
                            echo "Workspace {workspace} is locked. Waiting for 10 seconds..."
                            sleep 10
                        done
                        
                        terraform apply -auto-approve /workspace/$BUILD_ID/tfplan_{workspace}
                    else
                        echo "Skipping apply on branch $BRANCH_NAME"
                    fi
                    '''
                ]
            },
            {
                'id': f'destroy {workspace}',
                'name': f'hashicorp/terraform:{tf_version}',
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside destroy step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "destroy-all" ]; then
                        echo "Preparing to destroy all resources..."
                        echo "Auto-confirming destruction"
                        echo "Destroying resources in workspace: {workspace}"
                        terraform init -reconfigure
                        
                        # Create workspace if it doesn't exist
                        terraform workspace new {workspace} || terraform workspace select {workspace}
                        
                        # Wait for state lock
                        while ! terraform workspace select {workspace}; do
                            echo "Workspace {workspace} is locked. Waiting for 10 seconds..."
                            sleep 10
                        done
                        
                        terraform destroy -auto-approve -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID"
                    else
                        echo "Destroy operation not allowed on this branch."
                    fi
                    '''
                ]
            }
        ])

    cloudbuild = {'steps': steps}

    with open('cloudbuild_generated.yaml', 'w') as file:
        yaml.dump(cloudbuild, file, default_flow_style=False)

    print("cloudbuild_generated.yaml file generated successfully.")

if __name__ == '__main__':
    generate_cloudbuild()
