import os
import yaml

def generate_cloudbuild(workspaces, tf_version):
    steps = [
        {
            'id': 'branch-name',
            'name': 'ubuntu',
            'entrypoint': 'bash',
            'args': [
                '-c',
                'echo "************************"; echo "Branch Name: $BRANCH_NAME"; echo "Pull Request: $_PR_NUMBER"; echo "************************"'
            ]
        }
    ]

    for workspace in workspaces:
        step_id_prefix = workspace.replace(' ', '-').lower()
        wait_time_code = '''
        wait_time=20
        max_wait_time=300 # 5 minutes
        while true; do
            if terraform workspace select {workspace} 2>/dev/null; then
                break
            elif terraform workspace new {workspace}; then
                break
            else
                echo "Workspace {workspace} is locked or creation failed. Waiting for $wait_time seconds..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
                if [ $wait_time -gt $max_wait_time ]; then
                    wait_time=$max_wait_time
                fi
            fi
        done
        '''

        steps.extend([
            {
                'id': f'setup-and-plan-{step_id_prefix}',
                'name': f'hashicorp/terraform:{tf_version}',
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside setup and plan step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "$_PR_NUMBER" ]; then
                        echo "Processing workspace: {workspace}"
                        terraform init -reconfigure
                        mkdir -p /workspace/$BUILD_ID # Create directory for storing plans
                        {wait_time_code}
                        terraform validate
                        terraform plan -parallelism=60 -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID" -out=/workspace/$BUILD_ID/tfplan_{workspace} 
                    else
                        echo "Skipping setup and plan on branch $BRANCH_NAME"
                    fi
                    '''
                ]
            },
            {
                'id': f'apply-{step_id_prefix}',
                'name': f'hashicorp/terraform:{tf_version}',
                'waitFor': [f'setup-and-plan-{step_id_prefix}'],
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside apply step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                        echo "Applying Terraform plan for workspace: {workspace}"
                        terraform init -reconfigure
                        {wait_time_code}
                        terraform apply -parallelism=60 -auto-approve /workspace/$BUILD_ID/tfplan_{workspace}
                    else
                        echo "Skipping apply on branch $BRANCH_NAME"
                    fi
                    '''
                ]
            },
            {
                'id': f'destroy-{step_id_prefix}',
                'name': f'hashicorp/terraform:{tf_version}',
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside destroy step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "destroy-all" ]; then
                        echo "Destroying resources in workspace: {workspace}"
                        terraform init -reconfigure
                        {wait_time_code}
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
            'substitutionOption': 'ALLOW_LOOSE'
        }
    }

    return cloudbuild

if __name__ == '__main__':
    workspaces = os.environ['WORKSPACES'].split(',')
    tf_version = os.environ['TF_VERSION']
    cloudbuild = generate_cloudbuild(workspaces, tf_version)
    with open('cloudbuild_generated.yaml', 'w') as file:
        yaml.dump(cloudbuild, file)

    print("cloudbuild_generated.yaml file generated successfully.")
