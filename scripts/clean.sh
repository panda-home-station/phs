#!/usr/bin/env bash
set -u

# 1. Load Environment Variables
if [ -f .env ]; then
  # Simple .env parser compatible with bash
  while IFS= read -r line; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [[ $line =~ ^# || -z $line ]]; then continue; fi
    if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)\= ]]; then
      key="${BASH_REMATCH[1]}"
      if [ -z "${!key:-}" ]; then
        export "$line"
      fi
    fi
  done < .env
fi

# 2. Define Variables (Defaults matching run_dev.sh)
BACKEND_PORT="${PNAS_PORT:-8000}"
FRONTEND_PORT=5173
DEV_PG_NAME="${DEV_PG_NAME:-pnas_dev_pg}"
DEV_PG_PORT_ALT="${DEV_PG_PORT_ALT:-55432}"

echo "Cleaning up PNAS development environment..."

# 3. Helper Function to Kill Processes by Port
kill_by_port() {
  local port="$1"
  local found=0
  
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids=$(lsof -ti tcp:"$port" || true)
    if [ -n "$pids" ]; then
      echo "Killing processes on port $port: $pids"
      kill -9 $pids || true
      found=1
    fi
  elif command -v fuser >/dev/null 2>&1; then
    if fuser "${port}/tcp" >/dev/null 2>&1; then
      echo "Killing processes on port $port"
      fuser -k "${port}/tcp" || true
      found=1
    fi
  else
    # Fallback using ss/netstat
    local pids
    pids=$(ss -lntp | awk -v p=":${port}" '$4 ~ p {print $NF}' | sed -E 's/.*pid=([0-9]+).*/\1/' | tr '\n' ' ')
    if [ -n "$pids" ]; then
      echo "Killing processes on port $port: $pids"
      kill -9 $pids || true
      found=1
    fi
  fi
  
  if [ $found -eq 0 ]; then
    echo "No processes found on port $port."
  fi
}

# 4. Clean Backend and Frontend Processes
echo "--- Stopping Processes ---"
kill_by_port "$BACKEND_PORT"
kill_by_port "$FRONTEND_PORT"

# 5. Clean Docker Containers and Volumes
echo "--- Cleaning Docker ---"

clean_docker_container() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    echo "Found container: $name"
    echo "Stopping $name..."
    docker stop "$name" >/dev/null 2>&1 || true
    echo "Removing $name and associated volumes..."
    docker rm -v "$name" >/dev/null 2>&1 || true
    echo "Done."
  else
    echo "Container $name not found."
  fi
}

# Clean default container
clean_docker_container "$DEV_PG_NAME"

# Clean alt container (if it exists)
ALT_NAME="${DEV_PG_NAME}_${DEV_PG_PORT_ALT}"
clean_docker_container "$ALT_NAME"

echo "Cleanup complete!"
