import os
import yaml

def generate_cloudbuild(workspaces, tf_version):
    steps = [
        {
            'id': 'branch name',
            'name': 'ubuntu',
            'entrypoint': 'bash',
            'args': [
                '-c',
                'echo "************************"; echo "Branch Name: $BRANCH_NAME"; echo "Pull Request: $_PR_NUMBER"; echo "************************"'
            ]
        }
    ]

    for workspace in workspaces:
        steps.extend([
            {
                'id': f'setup and plan {workspace}',
                'name': f'hashicorp/terraform:{tf_version}',
                'entrypoint': 'sh',
                'args': [
                    '-c',
                    f'''
                    echo "Branch Name inside setup and plan step: $BRANCH_NAME"
                    if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "$_PR_NUMBER" ]; then
                        echo "Processing workspace: {workspace}"
                        terraform init -reconfigure
                        
                        # Create workspace if it doesn't exist
                        mkdir -p /workspace/$BUILD_ID # Create directory for storing plans
                        
                        # Wait for state lock with exponential backoff
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
                                
                                # Double the wait time for the next iteration
                                wait_time=$((wait_time * 2))
                                
                                # Cap the wait time at the maximum limit
                                if [ $wait_time -gt $max_wait_time ]; then
                                    wait_time=$max_wait_time
                                fi
                            fi
                        done
                        
                        terraform validate
                        terraform plan -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID" -out=/workspace/$BUILD_ID/tfplan_{workspace} -parallelism=60
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
                        
                        # Wait for state lock with exponential backoff
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
                                
                                # Double the wait time for the next iteration
                                wait_time=$((wait_time * 2))
                                
                                # Cap the wait time at the maximum limit
                                if [ $wait_time -gt $max_wait_time ]; then
                                    wait_time=$max_wait_time
                                fi
                            fi
                        done
                        
                        terraform apply -auto-approve /workspace/$BUILD_ID/tfplan_{workspace} -parallelism=60
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
                        
                        # Wait for state lock with exponential backoff
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
                                
                                # Double the wait time for the next iteration
                                wait_time=$((wait_time * 2))
                                
                                # Cap the wait time at the maximum limit
                                if [ $wait_time -gt $max_wait_time ]; then
                                    wait_time=$max_wait_time
                                fi
                            fi
                        done
                        
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