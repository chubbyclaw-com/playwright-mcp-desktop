#!/bin/bash
set -e

# Default ports
VNC_PORT=${VNC_PORT:-5901}
NOVNC_PORT=${NOVNC_PORT:-6080}

# Validate that the ports are numeric
if ! [[ "$VNC_PORT" =~ ^[0-9]+$ ]] || ! [[ "$NOVNC_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: invalid port configuration - VNC_PORT=$VNC_PORT, NOVNC_PORT=$NOVNC_PORT"
    exit 1
fi

# Wait for the VNC service to be ready
echo "Waiting for the VNC service..."
timeout=60
count=0
while ! netstat -ln | grep ":${VNC_PORT}" >/dev/null 2>&1 && [ $count -lt $timeout ]; do
    sleep 1
    count=$((count + 1))
done

if ! netstat -ln | grep ":${VNC_PORT}" >/dev/null 2>&1; then
    echo "Error: VNC service not ready, timed out"
    exit 1
fi

echo "VNC service is ready, starting noVNC..."

# Check noVNC availability
if [[ -n "${NOVNC_HOME}" && -d "${NOVNC_HOME}" ]]; then
    echo "noVNC home: ${NOVNC_HOME}"

    # Prefer the bundled launch script
    if [[ -f "${NOVNC_HOME}/utils/launch.sh" ]]; then
        echo "Using launch script: ${NOVNC_HOME}/utils/launch.sh"
        export VNC_HOST=localhost
        export VNC_PORT="${VNC_PORT}"
        export NOVNC_PORT="${NOVNC_PORT}"
        exec bash "${NOVNC_HOME}/utils/launch.sh"
    # Try utils/novnc_proxy (if present)
    elif [[ -f "${NOVNC_HOME}/utils/novnc_proxy" ]]; then
        echo "Using novnc_proxy: ${NOVNC_HOME}/utils/novnc_proxy"
        exec "${NOVNC_HOME}/utils/novnc_proxy" \
            --vnc localhost:${VNC_PORT} \
            --listen ${NOVNC_PORT}
    # Fall back to websockify directly
    elif command -v websockify >/dev/null 2>&1; then
        echo "Starting websockify directly..."
        echo "Command: websockify --web=${NOVNC_HOME} ${NOVNC_PORT} localhost:${VNC_PORT}"
        exec websockify --web="${NOVNC_HOME}" ${NOVNC_PORT} localhost:${VNC_PORT}
    else
        echo "Error: no valid way to start noVNC found"
        exit 1
    fi
else
    echo "Error: noVNC not available (home: ${NOVNC_HOME})"
    exit 1
fi
