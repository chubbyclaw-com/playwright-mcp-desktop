#!/bin/bash

# Browser Manager - auto-recovery and health-check support
# Keeps a single Chromium instance alive with a CDP debug port so that
# @playwright/mcp can attach to it and survive browser crashes.

set -e

# Configuration
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/root/.chrome-userdata}
REMOTE_DEBUG_PORT=${REMOTE_DEBUG_PORT:-9222}
DISPLAY=${DISPLAY:-:1}
CHROME_PID_FILE="/tmp/chrome-manager.pid"
HEALTH_CHECK_INTERVAL=30
MAX_RESTART_ATTEMPTS=3

# Logging helper
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check whether the browser is running
is_browser_running() {
    local port=$1
    if curl -s "http://localhost:${port}/json/version" >/dev/null 2>&1; then
        return 0  # browser is running
    else
        return 1  # browser is not running
    fi
}

# Start the browser
start_browser() {
    local attempt=1

    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "Trying to start the browser (attempt $attempt)"

        # Clean up any leftover processes (thorough cleanup)
        log "Cleaning up leftover Chrome processes..."

        # 1. Kill Chrome processes bound to the debug port
        pkill -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true

        # 2. Kill Chrome processes using the same user-data dir
        pkill -f "chromium.*${CHROME_USER_DATA_DIR}" || true

        # 3. Wait for processes to exit
        sleep 3

        # 4. Force-kill remaining processes
        pkill -9 -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
        pkill -9 -f "chromium.*${CHROME_USER_DATA_DIR}" || true

        # 5. Remove lock / temp files
        rm -f "${CHROME_USER_DATA_DIR}/SingletonLock" || true
        rm -f "${CHROME_USER_DATA_DIR}/SingletonSocket" || true
        rm -f "${CHROME_USER_DATA_DIR}/SingletonCookie" || true

        sleep 2

        # Launch the browser
        DISPLAY=$DISPLAY /usr/local/bin/start-chrome.sh \
            --remote-debugging-port=$REMOTE_DEBUG_PORT \
            --user-data-dir="$CHROME_USER_DATA_DIR" \
            --no-first-run \
            --disable-background-mode \
            --disable-background-timer-throttling \
            --disable-backgrounding-occluded-windows \
            --disable-features=TranslateUI \
            --window-size=1280,720 \
            > /var/log/chrome-manager.log 2>&1 &

        local chrome_pid=$!
        echo $chrome_pid > "$CHROME_PID_FILE"

        # Wait for the browser to come up
        local wait_count=0
        while [ $wait_count -lt 30 ]; do
            if is_browser_running $REMOTE_DEBUG_PORT; then
                log "✅ Browser started (PID: $chrome_pid, Port: $REMOTE_DEBUG_PORT)"
                return 0
            fi
            sleep 1
            wait_count=$((wait_count + 1))
        done

        log "❌ Browser failed to start (attempt $attempt)"
        attempt=$((attempt + 1))
    done

    log "❌ Browser failed to start, max retries reached"
    return 1
}

# Stop the browser
stop_browser() {
    log "Stopping the browser..."

    if [ -f "$CHROME_PID_FILE" ]; then
        local chrome_pid=$(cat "$CHROME_PID_FILE")
        if kill -0 "$chrome_pid" 2>/dev/null; then
            kill "$chrome_pid"
            sleep 3
            if kill -0 "$chrome_pid" 2>/dev/null; then
                kill -9 "$chrome_pid"
            fi
        fi
        rm -f "$CHROME_PID_FILE"
    fi

    # Clean up all related processes (thorough cleanup)
    log "Cleaning up all Chrome-related processes..."
    pkill -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
    pkill -f "chromium.*${CHROME_USER_DATA_DIR}" || true
    sleep 2

    # Force-kill remaining processes
    pkill -9 -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
    pkill -9 -f "chromium.*${CHROME_USER_DATA_DIR}" || true

    # Remove lock files
    rm -f "${CHROME_USER_DATA_DIR}/SingletonLock" || true
    rm -f "${CHROME_USER_DATA_DIR}/SingletonSocket" || true
    rm -f "${CHROME_USER_DATA_DIR}/SingletonCookie" || true

    log "✅ Browser stopped"
}

# Health check with auto-recovery
health_check_and_recover() {
    log "🔍 Starting health-check loop (interval: ${HEALTH_CHECK_INTERVAL}s)..."

    # Brief wait before the first check
    log "⏳ Initial wait..."
    sleep 3

    while true; do
        if ! is_browser_running $REMOTE_DEBUG_PORT; then
            log "⚠️  Browser not running, starting auto-recovery..."
            if start_browser; then
                log "✅ Browser auto-recovery succeeded"
            else
                log "❌ Browser auto-recovery failed"
                # Send a notification or take other action
                curl -s -X POST http://localhost:9999/health/browser-down || true
            fi
        else
            log "✅ Browser is healthy"
        fi
        sleep $HEALTH_CHECK_INTERVAL
    done
}

# Main entry point
main() {
    case "${1:-start}" in
        "start")
            log "🚀 Starting the browser..."
            if start_browser; then
                log "✅ Browser started, done"
                exit 0
            else
                log "❌ Browser failed to start"
                exit 1
            fi
            ;;
        "stop")
            stop_browser
            ;;
        "restart")
            stop_browser
            sleep 2
            start_browser
            ;;
        "health-check")
            health_check_and_recover
            ;;
        "status")
            if is_browser_running $REMOTE_DEBUG_PORT; then
                log "✅ Browser is running (Port: $REMOTE_DEBUG_PORT)"
                exit 0
            else
                log "❌ Browser is not running"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|health-check|status}"
            exit 1
            ;;
    esac
}

# Signal handling
trap 'log "Received termination signal, stopping the browser..."; stop_browser; exit 0' TERM INT

# Run
main "$@"
