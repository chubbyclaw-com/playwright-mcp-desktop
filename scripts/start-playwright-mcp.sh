#!/bin/bash
set -e

# Playwright MCP gateway startup script - with auto-recovery.
# Runs @playwright/mcp over SSE/HTTP and attaches it to the Chromium instance
# managed by browser-manager via the CDP endpoint, so the MCP server keeps
# working across browser restarts.

# Default ports and directories
PLAYWRIGHT_MCP_PORT=${PLAYWRIGHT_MCP_PORT:-9999}
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/opt/chrome-userdata}
REMOTE_DEBUG_PORT=${REMOTE_DEBUG_PORT:-9222}
DISPLAY=${DISPLAY:-:1}
BROWSER_MANAGER_SCRIPT="/usr/local/bin/browser-manager.sh"

# Optional: comma-separated Host header allowlist for the SSE/HTTP endpoint
# (passes through to @playwright/mcp's --allowed-hosts).
#
# Leave unset to preserve @playwright/mcp's built-in default
# ("localhost:<port>"), which means only same-host clients can connect.
# Set to your reachable host(s) when serving from non-localhost — e.g.
# "100.99.99.139:9999,my.host:9999" — or "*" to disable the host check
# entirely (DNS rebinding protection off).
PLAYWRIGHT_MCP_ALLOWED_HOSTS=${PLAYWRIGHT_MCP_ALLOWED_HOSTS:-}

echo "🎭 Starting the Playwright MCP gateway (with auto-recovery)..."
echo "📍 MCP port: ${PLAYWRIGHT_MCP_PORT}"
echo "🌐 Remote debug port: ${REMOTE_DEBUG_PORT}"
echo "💾 Chrome user-data dir: ${CHROME_USER_DATA_DIR}"
echo "🖥️  Display: ${DISPLAY}"
if [ -n "${PLAYWRIGHT_MCP_ALLOWED_HOSTS}" ]; then
	echo "🛡️  Allowed Hosts: ${PLAYWRIGHT_MCP_ALLOWED_HOSTS}"
else
	echo "🛡️  Allowed Hosts: (default) localhost:${PLAYWRIGHT_MCP_PORT}"
fi

# Validate that the MCP port is numeric
if ! [[ "$PLAYWRIGHT_MCP_PORT" =~ ^[0-9]+$ ]]; then
	echo "❌ Error: invalid MCP port - PLAYWRIGHT_MCP_PORT=$PLAYWRIGHT_MCP_PORT"
	exit 1
fi

if ! [[ "$REMOTE_DEBUG_PORT" =~ ^[0-9]+$ ]]; then
	echo "❌ Error: invalid remote debug port - REMOTE_DEBUG_PORT=$REMOTE_DEBUG_PORT"
	exit 1
fi

# Check the Chrome user-data directory
if [ ! -d "$CHROME_USER_DATA_DIR" ]; then
	echo "📁 Creating Chrome user-data dir: $CHROME_USER_DATA_DIR"
	mkdir -p "$CHROME_USER_DATA_DIR"
	chmod 755 "$CHROME_USER_DATA_DIR"
fi

# Check the browser-manager script
if [ ! -f "$BROWSER_MANAGER_SCRIPT" ]; then
	echo "❌ Error: browser-manager script not found: $BROWSER_MANAGER_SCRIPT"
	exit 1
fi

# Check Node.js availability
if ! command -v node >/dev/null 2>&1; then
	echo "❌ Error: Node.js not found"
	exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
	echo "❌ Error: npx not found"
	exit 1
fi

# Check Chrome availability
if ! command -v google-chrome-stable >/dev/null 2>&1; then
	echo "❌ Error: Google Chrome not found"
	exit 1
fi

# Wait for the display service (VNC) to be ready
echo "⏳ Waiting for the display service..."
timeout=30                    # shorter timeout
max_attempts=$((timeout * 2)) # 0.5s interval
count=0
while ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && [ $count -lt $max_attempts ]; do
	sleep 0.5 # check more frequently
	count=$((count + 1))
	if [ $((count % 10)) -eq 0 ]; then # log status every 5s
		elapsed=$((count / 2))
		echo "⏳ Waiting for the display service... (${elapsed}/${timeout}s)"
	fi
done

if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
	echo "⚠️  Warning: display service not ready, continuing..."
fi

echo "✅ Display service is ready"

# Export environment variables
export PLAYWRIGHT_MCP_PORT
export CHROME_USER_DATA_DIR
export REMOTE_DEBUG_PORT
export DISPLAY
export NODE_ENV=production

# Playwright browser configuration
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Wait for the browser to be ready (started and managed by browser-manager)
echo "🔍 Waiting for the browser service..."
timeout=60                    # wait up to 1 minute
max_attempts=$((timeout * 2)) # 0.5s interval, so double it
count=0
while ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1 && [ $count -lt $max_attempts ]; do
	sleep 0.5 # check more frequently
	count=$((count + 1))
	if [ $((count % 6)) -eq 0 ]; then # log status every 3s
		elapsed=$((count / 2))           # elapsed seconds
		echo "⏳ Waiting for the browser service... (${elapsed}/${timeout}s)"
	fi
done

if ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1; then
	echo "❌ Browser service not ready, check the browser-manager service"
	exit 1
else
	echo "✅ Browser service is ready"
fi

# Wrapper with auto-reconnect
start_mcp_with_auto_recovery() {
	local retry_count=0
	local max_retries=6
	local retry_delay=5

	while [ $retry_count -lt $max_retries ]; do
		echo "🚀 Starting the Playwright MCP server (attempt $((retry_count + 1))/$max_retries)..."
		echo "🎭 Using @playwright/mcp@latest"
		echo "🌐 SSE port: ${PLAYWRIGHT_MCP_PORT}"
		echo "🔗 Connecting to the existing Chrome instance (port: ${REMOTE_DEBUG_PORT})"

		# Check the browser is available
		if ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1; then
			echo "⚠️  Browser connection failed, waiting for browser-manager to recover..."
			echo "💡 The browser is managed by browser-manager and recovers automatically"
			sleep 5 # wait for browser-manager to auto-recover
		fi

		# Assemble args; only pass --allowed-hosts when explicitly configured,
		# so leaving the env unset preserves @playwright/mcp's built-in default
		# (localhost:<port>).
		local mcp_args=(
			--port "${PLAYWRIGHT_MCP_PORT}"
			--user-data-dir="${CHROME_USER_DATA_DIR}"
			--browser=chrome
			--cdp-endpoint="http://localhost:${REMOTE_DEBUG_PORT}"
			--output-dir=/tmp/playwright-output
			--host=0.0.0.0
		)
		if [ -n "${PLAYWRIGHT_MCP_ALLOWED_HOSTS}" ]; then
			mcp_args+=(--allowed-hosts "${PLAYWRIGHT_MCP_ALLOWED_HOSTS}")
		fi

		# Start the MCP server
		if npx @playwright/mcp@latest "${mcp_args[@]}"; then
			echo "✅ Playwright MCP server started"
			return 0
		else
			echo "❌ Playwright MCP server failed to start"
			retry_count=$((retry_count + 1))
			if [ $retry_count -lt $max_retries ]; then
				echo "⏳ Retrying in ${retry_delay}s..."
				sleep $retry_delay
			fi
		fi
	done

	echo "❌ MCP server failed to start, max retries reached"
	return 1
}

echo "🎯 Mode: remote browser + auto-recovery"
echo "🌐 Remote debug URL: http://localhost:${REMOTE_DEBUG_PORT}"

# Start the MCP server (with retry)
start_mcp_with_auto_recovery
