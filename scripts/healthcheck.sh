#!/bin/bash

# Container health probe.
#
# Verifies that the three service ports are listening and that the Chromium
# browser process is alive. Uses bash /dev/tcp for the port checks so the
# probe is fully self-contained and, crucially, leak-free: the previous probe
# ran `curl http://localhost:9999/sse`, which opens an infinite Server-Sent
# Events stream that never returns. Docker's healthcheck timeout killed the
# wrapping shell but orphaned the curl, leaking one hung process every
# interval (thousands accumulated, exhausting container memory).
#
# Chromium auto-recovery is NOT handled here: browser-manager.sh (a
# supervisor-managed daemon, autorestart=true) already polls the CDP endpoint
# every 30s and relaunches the browser when it is gone. This probe only
# reports status; reporting "unhealthy" while the browser is being relaunched
# is expected and clears on the next interval.

set -u

VNC_PORT=${VNC_PORT:-5901}
NOVNC_PORT=${NOVNC_PORT:-6080}
MCP_PORT=${PLAYWRIGHT_MCP_PORT:-9999}

# Return 0 if a TCP connection to 127.0.0.1:<port> succeeds within 3s.
check_port() {
    local name=$1 port=$2
    if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" 2>/dev/null; then
        return 0
    fi
    echo "unhealthy: ${name} port ${port} not listening"
    return 1
}

check_port "VNC"   "$VNC_PORT"   || exit 1
check_port "noVNC" "$NOVNC_PORT" || exit 1
check_port "MCP"   "$MCP_PORT"   || exit 1

if ! pgrep -x chromium >/dev/null 2>&1; then
    echo "unhealthy: chromium process not found"
    exit 1
fi

echo "healthy"
exit 0
