
# docker-to-compose.sh

A Bash script that automatically generates a docker-compose.yml file based on the configuration of running Docker containers.

## Features

- **Single container conversion**: Generates a docker-compose.yml for the specified container in the current directory.
- **All containers conversion**: For each running container, creates a folder named after the container and generates a docker-compose.yml inside it.

## Usage

```bash
# Convert a single container
./docker-to-compose.sh <container_name_or_id>

# Convert all running containers
./docker-to-compose.sh --all

# Help
./docker-to-compose.sh -h
./docker-to-compose.sh --help
```

### Examples

```bash
# Generate docker-compose.yml for my-container
./docker-to-compose.sh my-container

# Generate folders and docker-compose.yml for all running containers
./docker-to-compose.sh --all
```

## Options

- `-h`, `--help`: Show help message
- `--all`: Convert all running containers

## Requirements

- bash
- docker
- jq

## Notes

- Always review the generated docker-compose.yml file before use.
- Sensitive information (such as environment variables) may be included.
- Make sure external networks/volumes actually exist.
- Test before running with `docker-compose up -d`.
