#!/bin/bash

# Docker Container to docker-compose.yml converter
# Usage: ./docker-to-compose.sh <container_name_or_id>

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


# Show help message
show_help() {
    echo "Usage: $0 <container_name_or_id> | --all"
    echo ""
    echo "Examples:"
    echo "  $0 my-container"
    echo "  $0 abc123def456"
    echo "  $0 --all"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --all         Generate docker-compose.yml for all running containers"
}


# Function to generate docker-compose.yml for a given container
generate_compose_file() {
    local container_name="$1"
    local output_dir="$2"
    local output_file="$output_dir/docker-compose.yml"

    # Check if container exists
    if ! docker inspect "$container_name" > /dev/null 2>&1; then
        echo -e "${RED}Error: Container '$container_name' not found.${NC}" >&2
        return 1
    fi

    echo -e "${GREEN}Extracting information from container '$container_name' and generating $output_file...${NC}"

    # Extract container information
    INSPECT_OUTPUT=$(docker inspect "$container_name")

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed. Please install it using the following command:${NC}" >&2
        echo "  Ubuntu/Debian: sudo apt-get install jq" >&2
        echo "  CentOS/RHEL: sudo yum install jq" >&2
        echo "  macOS: brew install jq" >&2
        return 1
    fi

    # Extract information from JSON
    IMAGE=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Image')
    CONTAINER_NAME_ACTUAL=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Name' | sed 's|^/||')
    HOSTNAME=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Hostname // empty')
    WORKING_DIR=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.WorkingDir // empty')
    USER=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.User // empty')
    RESTART_POLICY=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.RestartPolicy.Name // "no"')
    PRIVILEGED=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.Privileged // false')

    mkdir -p "$output_dir"
    cat > "$output_file" << 'EOF'
version: '3.3'

services:
EOF

    echo "  $CONTAINER_NAME_ACTUAL:" >> "$output_file"
    echo "    image: $IMAGE" >> "$output_file"

    if [ "$CONTAINER_NAME_ACTUAL" != "$container_name" ]; then
        echo "    container_name: $CONTAINER_NAME_ACTUAL" >> "$output_file"
    fi

    if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "null" ]; then
        echo "    hostname: $HOSTNAME" >> "$output_file"
    fi

    if [ -n "$WORKING_DIR" ] && [ "$WORKING_DIR" != "null" ] && [ "$WORKING_DIR" != "/" ]; then
        echo "    working_dir: $WORKING_DIR" >> "$output_file"
    fi

    if [ -n "$USER" ] && [ "$USER" != "null" ]; then
        echo "    user: $USER" >> "$output_file"
    fi

    if [ "$RESTART_POLICY" != "no" ]; then
        echo "    restart: $RESTART_POLICY" >> "$output_file"
    fi

    if [ "$PRIVILEGED" = "true" ]; then
        echo "    privileged: true" >> "$output_file"
    fi

    ENV_VARS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Env[]?' 2>/dev/null | grep -v '^PATH=' | grep -v '^HOME=' | grep -v '^HOSTNAME=' || true)
    if [ -n "$ENV_VARS" ]; then
        echo "    environment:" >> "$output_file"
        while IFS= read -r env; do
            if [ -n "$env" ]; then
                echo "      - \"$env\"" >> "$output_file"
            fi
        done <<< "$ENV_VARS"
    fi

    PORTS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].NetworkSettings.Ports | to_entries[]? | select(.value != null) | .key as $container_port | .value[]? | "\(.HostPort):\($container_port)"' 2>/dev/null || true)
    if [ -n "$PORTS" ]; then
        echo "    ports:" >> "$output_file"
        while IFS= read -r port; do
            if [ -n "$port" ]; then
                echo "      - \"$port\"" >> "$output_file"
            fi
        done <<< "$PORTS"
    fi

    MOUNTS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Mounts[]? | "\(.Source):\(.Destination)" + (if .Mode then ":" + .Mode else "" end)' 2>/dev/null || true)
    if [ -n "$MOUNTS" ]; then
        echo "    volumes:" >> "$output_file"
        while IFS= read -r mount; do
            if [ -n "$mount" ]; then
                echo "      - \"$mount\"" >> "$output_file"
            fi
        done <<< "$MOUNTS"
    fi

    NETWORKS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].NetworkSettings.Networks | keys[]?' 2>/dev/null | grep -v '^bridge$' || true)
    if [ -n "$NETWORKS" ]; then
        echo "    networks:" >> "$output_file"
        while IFS= read -r network; do
            if [ -n "$network" ]; then
                echo "      - $network" >> "$output_file"
            fi
        done <<< "$NETWORKS"

        echo "" >> "$output_file"
        echo "networks:" >> "$output_file"
        while IFS= read -r network; do
            if [ -n "$network" ]; then
                echo "  $network:" >> "$output_file"
                echo "    external: true" >> "$output_file"
            fi
        done <<< "$NETWORKS"
    fi

    CMD=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Cmd[]?' 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)
    if [ -n "$CMD" ]; then
        CMD_FORMATTED=$(echo "$CMD" | sed 's/^/["/' | sed 's/ /", "/g' | sed 's/$/"]/')
        echo "    command: $CMD_FORMATTED" >> "$output_file"
    fi

    MEMORY_LIMIT=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.Memory // empty' 2>/dev/null || true)
    if [ -n "$MEMORY_LIMIT" ] && [ "$MEMORY_LIMIT" != "0" ] && [ "$MEMORY_LIMIT" != "null" ]; then
        echo "    mem_limit: ${MEMORY_LIMIT}" >> "$output_file"
    fi

    CPU_LIMIT=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.CpuQuota // empty' 2>/dev/null || true)
    if [ -n "$CPU_LIMIT" ] && [ "$CPU_LIMIT" != "0" ] && [ "$CPU_LIMIT" != "null" ]; then
        CPU_PERIOD=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.CpuPeriod // 100000' 2>/dev/null)
        if command -v bc &> /dev/null; then
            CPU_CORES=$(echo "scale=2; $CPU_LIMIT / $CPU_PERIOD" | bc 2>/dev/null || echo "1")
            echo "    cpus: $CPU_CORES" >> "$output_file"
        fi
    fi

    echo -e "${GREEN}Successfully generated '$output_file'!${NC}"
    echo -e "${YELLOW}Caution:${NC}"
    echo "  1. Please review the generated file and modify as needed."
    echo "  2. Secrets or sensitive information may be included."
    echo "  3. Make sure external networks or volumes actually exist."
    echo "  4. Test before running with 'docker-compose up -d'."
}

# Main logic
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ "$1" = "--all" ]; then
    # Get all running container IDs
    CONTAINER_IDS=$(docker ps -q)
    if [ -z "$CONTAINER_IDS" ]; then
        echo -e "${YELLOW}No running containers found.${NC}"
        exit 0
    fi
    for cid in $CONTAINER_IDS; do
        # Get actual container name
        cname=$(docker inspect --format='{{.Name}}' "$cid" | sed 's|^/||')
        generate_compose_file "$cid" "$cname"
    done
    exit 0
fi

# Default: single container mode
generate_compose_file "$1" "."