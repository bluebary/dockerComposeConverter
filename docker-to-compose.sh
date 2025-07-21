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
    echo "Usage: $0 <container_name_or_id>"
    echo ""
    echo "Examples:"
    echo "  $0 my-container"
    echo "  $0 abc123def456"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
}

# Check arguments
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

CONTAINER_NAME="$1"

# Check if container exists
if ! docker inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
    echo -e "${RED}Error: Container '$CONTAINER_NAME' not found.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}Extracting information from container '$CONTAINER_NAME' and generating docker-compose.yml...${NC}"

# Extract container information
INSPECT_OUTPUT=$(docker inspect "$CONTAINER_NAME")

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install it using the following command:${NC}" >&2
    echo "  Ubuntu/Debian: sudo apt-get install jq" >&2
    echo "  CentOS/RHEL: sudo yum install jq" >&2
    echo "  macOS: brew install jq" >&2
    exit 1
fi

 # Extract information from JSON
IMAGE=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Image')
CONTAINER_NAME_ACTUAL=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Name' | sed 's|^/||')
HOSTNAME=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Hostname // empty')
WORKING_DIR=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.WorkingDir // empty')
USER=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.User // empty')
RESTART_POLICY=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.RestartPolicy.Name // "no"')
PRIVILEGED=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.Privileged // false')

 # Start docker-compose.yml
OUTPUT_FILE="docker-compose.yml"
cat > "$OUTPUT_FILE" << 'EOF'
version: '3.3'

services:
EOF

 # Add service name
echo "  $CONTAINER_NAME_ACTUAL:" >> "$OUTPUT_FILE"
echo "    image: $IMAGE" >> "$OUTPUT_FILE"

 # If container name is different from service name
if [ "$CONTAINER_NAME_ACTUAL" != "$CONTAINER_NAME" ]; then
    echo "    container_name: $CONTAINER_NAME_ACTUAL" >> "$OUTPUT_FILE"
fi

 # Add hostname
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "null" ]; then
    echo "    hostname: $HOSTNAME" >> "$OUTPUT_FILE"
fi

 # Add working directory
if [ -n "$WORKING_DIR" ] && [ "$WORKING_DIR" != "null" ] && [ "$WORKING_DIR" != "/" ]; then
    echo "    working_dir: $WORKING_DIR" >> "$OUTPUT_FILE"
fi

 # Add user
if [ -n "$USER" ] && [ "$USER" != "null" ]; then
    echo "    user: $USER" >> "$OUTPUT_FILE"
fi

 # Add restart policy
if [ "$RESTART_POLICY" != "no" ]; then
    echo "    restart: $RESTART_POLICY" >> "$OUTPUT_FILE"
fi

 # Add privileged
if [ "$PRIVILEGED" = "true" ]; then
    echo "    privileged: true" >> "$OUTPUT_FILE"
fi

 # Extract and add environment variables
ENV_VARS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Env[]?' 2>/dev/null | grep -v '^PATH=' | grep -v '^HOME=' | grep -v '^HOSTNAME=' || true)
if [ -n "$ENV_VARS" ]; then
    echo "    environment:" >> "$OUTPUT_FILE"
    while IFS= read -r env; do
        if [ -n "$env" ]; then
            echo "      - \"$env\"" >> "$OUTPUT_FILE"
        fi
    done <<< "$ENV_VARS"
fi

 # Extract and add port mappings
PORTS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].NetworkSettings.Ports | to_entries[]? | select(.value != null) | .key as $container_port | .value[]? | "\(.HostPort):\($container_port)"' 2>/dev/null || true)
if [ -n "$PORTS" ]; then
    echo "    ports:" >> "$OUTPUT_FILE"
    while IFS= read -r port; do
        if [ -n "$port" ]; then
            echo "      - \"$port\"" >> "$OUTPUT_FILE"
        fi
    done <<< "$PORTS"
fi

 # Extract and add volume mounts
MOUNTS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Mounts[]? | "\(.Source):\(.Destination)" + (if .Mode then ":" + .Mode else "" end)' 2>/dev/null || true)
if [ -n "$MOUNTS" ]; then
    echo "    volumes:" >> "$OUTPUT_FILE"
    while IFS= read -r mount; do
        if [ -n "$mount" ]; then
            echo "      - \"$mount\"" >> "$OUTPUT_FILE"
        fi
    done <<< "$MOUNTS"
fi

 # Extract and add networks
NETWORKS=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].NetworkSettings.Networks | keys[]?' 2>/dev/null | grep -v '^bridge$' || true)
if [ -n "$NETWORKS" ]; then
    echo "    networks:" >> "$OUTPUT_FILE"
    while IFS= read -r network; do
        if [ -n "$network" ]; then
            echo "      - $network" >> "$OUTPUT_FILE"
        fi
    done <<< "$NETWORKS"
    
    # Add network definition section
    echo "" >> "$OUTPUT_FILE"
    echo "networks:" >> "$OUTPUT_FILE"
    while IFS= read -r network; do
        if [ -n "$network" ]; then
            echo "  $network:" >> "$OUTPUT_FILE"
            echo "    external: true" >> "$OUTPUT_FILE"
        fi
    done <<< "$NETWORKS"
fi

 # Add command (if different from default image command)
CMD=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].Config.Cmd[]?' 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)
if [ -n "$CMD" ]; then
    # Convert command to array format
    CMD_FORMATTED=$(echo "$CMD" | sed 's/^/["/' | sed 's/ /", "/g' | sed 's/$/"]/')
    echo "    command: $CMD_FORMATTED" >> "$OUTPUT_FILE"
fi

 # Add memory limit
MEMORY_LIMIT=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.Memory // empty' 2>/dev/null || true)
if [ -n "$MEMORY_LIMIT" ] && [ "$MEMORY_LIMIT" != "0" ] && [ "$MEMORY_LIMIT" != "null" ]; then
    echo "    mem_limit: ${MEMORY_LIMIT}" >> "$OUTPUT_FILE"
fi

 # Add CPU limit
CPU_LIMIT=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.CpuQuota // empty' 2>/dev/null || true)
if [ -n "$CPU_LIMIT" ] && [ "$CPU_LIMIT" != "0" ] && [ "$CPU_LIMIT" != "null" ]; then
    CPU_PERIOD=$(echo "$INSPECT_OUTPUT" | jq -r '.[0].HostConfig.CpuPeriod // 100000' 2>/dev/null)
    if command -v bc &> /dev/null; then
        CPU_CORES=$(echo "scale=2; $CPU_LIMIT / $CPU_PERIOD" | bc 2>/dev/null || echo "1")
        echo "    cpus: $CPU_CORES" >> "$OUTPUT_FILE"
    fi
fi

echo -e "${GREEN}Successfully generated '$OUTPUT_FILE'!${NC}"
echo -e "${YELLOW}Caution:${NC}"
echo "  1. Please review the generated file and modify as needed."
echo "  2. Secrets or sensitive information may be included."
echo "  3. Make sure external networks or volumes actually exist."
echo "  4. Test before running with 'docker-compose up -d'."