package main

import (
    "fmt"
    "os"
    "strings"

    "gopkg.in/yaml.v3"
)

type Step struct {
    ID         string   `yaml:"id"`
    Name       string   `yaml:"name"`
    Entrypoint string   `yaml:"entrypoint"`
    Args       []string `yaml:"args"`
    WaitFor    []string `yaml:"waitFor,omitempty"`
}

type CloudBuild struct {
    Steps []Step `yaml:"steps"`
}

func main() {
    workspaces := getEnv("_WORKSPACES", "dev,staging,gitops")
    tfVersion := getEnv("_TF_VERSION", "1.8")
    prNumber := getEnv("_PR_NUMBER", "")

    steps := []Step{
        {
            ID:         "branch name",
            Name:       "ubuntu",
            Entrypoint: "bash",
            Args: []string{
                "-c",
                fmt.Sprintf("echo \"************************\"; echo \"Branch Name: $BRANCH_NAME\"; echo \"Pull Request: %s\"; echo \"************************\"", prNumber),
            },
        },
    }

    for _, workspace := range strings.Split(workspaces, ",") {
        steps = append(steps, Step{
            ID:         fmt.Sprintf("setup and plan %s", workspace),
            Name:       fmt.Sprintf("hashicorp/terraform:%s", tfVersion),
            Entrypoint: "sh",
            Args: []string{
                "-c",
                fmt.Sprintf(`
                echo "Branch Name inside setup and plan step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ] || [ -n "%s" ]; then
                    echo "Processing workspace: %s"
					
					mkdir -p /workspace/$BUILD_ID  # Create directory for storing plans
                    terraform init -reconfigure
                    
                    # Create workspace if it doesn't exist
                    terraform workspace new %s || terraform workspace select %s
                    
                    # Wait for state lock
                    while ! terraform workspace select %s; do
                        echo "Workspace %s is locked. Waiting for 10 seconds..."
                        sleep 10
                    done
                    
                    terraform validate
                    terraform plan -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID" -out=/workspace/$BUILD_ID/tfplan_%s
                else
                    echo "Skipping setup and plan on branch $BRANCH_NAME"
                fi
                `, prNumber, workspace, workspace, workspace, workspace, workspace, workspace),
            },
        }, Step{
            ID:         fmt.Sprintf("apply %s", workspace),
            Name:       fmt.Sprintf("hashicorp/terraform:%s", tfVersion),
            WaitFor:    []string{fmt.Sprintf("setup and plan %s", workspace)},
            Entrypoint: "sh",
            Args: []string{
                "-c",
                fmt.Sprintf(`
                echo "Branch Name inside apply step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "main" ] || [ "$BRANCH_NAME" = "master" ]; then
                    echo "Applying Terraform plan for workspace: %s"
                    terraform init -reconfigure
                    
                    # Create workspace if it doesn't exist
                    terraform workspace new %s || terraform workspace select %s
                    
                    # Wait for state lock
                    while ! terraform workspace select %s; do
                        echo "Workspace %s is locked. Waiting for 10 seconds..."
                        sleep 10
                    done
                    
                    terraform apply -auto-approve /workspace/$BUILD_ID/tfplan_%s
                else
                    echo "Skipping apply on branch $BRANCH_NAME"
                fi
                `, workspace, workspace, workspace, workspace, workspace, workspace),
            },
        }, Step{
            ID:         fmt.Sprintf("destroy %s", workspace),
            Name:       fmt.Sprintf("hashicorp/terraform:%s", tfVersion),
            Entrypoint: "sh",
            Args: []string{
                "-c",
                fmt.Sprintf(`
                echo "Branch Name inside destroy step: $BRANCH_NAME"
                if [ "$BRANCH_NAME" = "destroy-all" ]; then
                    echo "Preparing to destroy all resources..."
                    echo "Auto-confirming destruction"
                    echo "Destroying resources in workspace: %s"
                    terraform init -reconfigure
                    
                    # Create workspace if it doesn't exist
                    terraform workspace new %s || terraform workspace select %s
                    
                    # Wait for state lock
                    while ! terraform workspace select %s; do
                        echo "Workspace %s is locked. Waiting for 10 seconds..."
                        sleep 10
                    done
                    
                    terraform destroy -auto-approve -var="compute_engine_service_account=terraform@$PROJECT_ID.iam.gserviceaccount.com" -var="project_id=$PROJECT_ID"
                else
                    echo "Destroy operation not allowed on this branch."
                fi
                `, workspace, workspace, workspace, workspace, workspace),
            },
        })
    }

    cloudBuild := CloudBuild{
        Steps: steps,
    }

    yamlData, err := yaml.Marshal(cloudBuild)
    if err != nil {
        fmt.Printf("Error marshaling YAML: %v\n", err)
        return
    }

    err = os.WriteFile("go_cloudbuild_generated.yaml", yamlData, 0644)
    if err != nil {
        fmt.Printf("Error writing YAML file: %v\n", err)
        return
    }

    fmt.Println("go_cloudbuild_generated.yaml file generated successfully.")
}

func getEnv(key, defaultValue string) string {
    value := os.Getenv(key)
    if value == "" {
        return defaultValue
    }
    return value
}