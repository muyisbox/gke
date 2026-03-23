#!/usr/local/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

check_requirements() {
    echo -e "${YELLOW}Checking requirements...${NC}"
    for cmd in jq terraform; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: Required command not found: $cmd${NC}"
            exit 1
        fi
    done
}

remove_resources() {
    local WORKSPACE=$1

    echo -e "${YELLOW}Switching to workspace: ${WORKSPACE}...${NC}"
    terraform -chdir="$PROJECT_DIR" workspace select "$WORKSPACE"

    echo -e "${YELLOW}Analyzing state for cluster-dependent resources...${NC}"

    # Find all resources managed by kubernetes, helm, or kubectl providers
    RESOURCES=$(terraform -chdir="$PROJECT_DIR" show -json 2>/dev/null | jq -r '
        .. |
        select(.type? and .address?) |
        select(.type | startswith("kubernetes_") or startswith("helm_") or startswith("kubectl_")) |
        .address
    ' 2>/dev/null | sort -u | grep -v '^$' || true)

    TOTAL=$(echo "$RESOURCES" | grep -c -v '^$' 2>/dev/null || echo 0)

    if [ "$TOTAL" -eq 0 ]; then
        echo -e "${GREEN}No cluster-dependent resources found in ${WORKSPACE}${NC}"
        return 0
    fi

    echo -e "${YELLOW}Found $TOTAL resources to remove from state:${NC}"
    echo "$RESOURCES" | sed 's/^/  - /'
    echo ""

    read -p "Remove these resources from state? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipped ${WORKSPACE}${NC}"
        return 0
    fi

    # Remove resources one by one (compatible with macOS bash)
    echo "${RESOURCES}" | while IFS= read -r resource; do
        if [[ -n "${resource}" ]]; then
            echo -e "${YELLOW}Removing:${NC} ${resource}"
            if terraform -chdir="${PROJECT_DIR}" state rm "${resource}" 2>/dev/null; then
                echo -e "${GREEN}  Removed:${NC} ${resource}"
            else
                echo -e "${RED}  Failed:${NC} ${resource}"
            fi
        fi
    done
    echo -e "${GREEN}Done processing ${TOTAL} resources from ${WORKSPACE}${NC}"
}

main() {
    echo -e "${YELLOW}=== Terraform State Cleanup: Remove Cluster-Dependent Resources ===${NC}"
    echo -e "${YELLOW}This removes kubernetes_, helm_, and kubectl_ resources from state${NC}"
    echo -e "${YELLOW}so that terraform can operate after clusters have been destroyed.${NC}"
    echo ""

    check_requirements

    if [ "$#" -gt 0 ]; then
        # Clean specific workspaces
        for ws in "$@"; do
            remove_resources "$ws"
        done
    else
        # Clean all non-default workspaces
        WORKSPACES=$(terraform -chdir="$PROJECT_DIR" workspace list | grep -v '^\*\?\s*default$' | sed 's/^[ *]*//' | grep -v '^$')
        if [ -z "$WORKSPACES" ]; then
            echo -e "${YELLOW}No non-default workspaces found${NC}"
            exit 0
        fi

        echo -e "${YELLOW}Workspaces to process: $(echo $WORKSPACES | tr '\n' ' ')${NC}"
        echo ""

        for ws in $WORKSPACES; do
            remove_resources "$ws"
            echo ""
        done
    fi

    echo -e "${GREEN}Cleanup complete${NC}"
}

main "$@"
