#!/bin/bash

# Chrome startup script
# Simplified configuration inspired by the ubuntu-vnc-xfce-g3 project.

# Display-related environment variables
export DISPLAY=${DISPLAY:-:1}
export LIBGL_ALWAYS_INDIRECT=1

# X11 authority file path
export XAUTHORITY=${XAUTHORITY:-/root/.Xauthority}

# Fontconfig path so CJK fonts can be loaded
export FONTCONFIG_PATH=/etc/fonts

# Chrome user-data directory
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/opt/chrome-userdata}

# Create required directories
mkdir -p "$CHROME_USER_DATA_DIR"
chmod 755 "$CHROME_USER_DATA_DIR"

# Wait for the X server to be ready
echo "Waiting for the X server..."
count=0
while ! xdpyinfo >/dev/null 2>&1 && [ $count -lt 30 ]; do
    sleep 1
    count=$((count + 1))
    echo "Waiting for the X server... ($count/30)"
done

if ! xdpyinfo >/dev/null 2>&1; then
    echo "Error: X server not ready, cannot start Chrome"
    exit 1
fi

echo "X server is ready"

# Extra environment variables to work around display issues
export NO_AT_BRIDGE=1
export QTWEBENGINE_DISABLE_SANDBOX=1

# Verify the X11 authority file
if [ ! -f "$XAUTHORITY" ]; then
    echo "Warning: X11 authority file missing, creating an empty one"
    touch "$XAUTHORITY"
    chmod 600 "$XAUTHORITY"
fi

# Test the X11 connection
echo "Testing the X11 connection..."
if ! xhost >/dev/null 2>&1; then
    echo "Warning: X11 connection test failed, starting Chrome anyway"
fi

# Chrome launch flags tuned for VNC to fix the blank-page issue.
# Inspired by the ubuntu-vnc-xfce-g3 project.
CHROME_ARGS=(
    # Basic security / sandbox settings
    --no-sandbox
    --disable-setuid-sandbox
    --disable-dev-shm-usage

    # GPU / rendering settings (key to fixing the blank page)
    --disable-gpu
    --disable-gpu-sandbox
    --disable-software-rasterizer
    --disable-features=VizDisplayCompositor
    --use-gl=swiftshader-webgl
    --enable-features=UseOzonePlatform
    --ozone-platform=x11

    # Disable features that can cause problems
    --disable-extensions
    --disable-plugins
    --disable-web-security
    --disable-features=TranslateUI
    --disable-ipc-flooding-protection

    # Performance and stability
    --no-first-run
    --disable-default-apps
    --disable-infobars
    --disable-background-timer-throttling
    --disable-backgrounding-occluded-windows
    --disable-renderer-backgrounding
    --disable-field-trial-config

    # Suppress various warnings and prompts (including the --disable-gpu-sandbox warning)
    --test-type
    --disable-logging
    --silent-debugger-extension-api

    # Debug and data directory
    # Note: --remote-debugging-port is passed on the command line to avoid duplication
    --user-data-dir="$CHROME_USER_DATA_DIR"

    # Window settings - start maximized
    --start-maximized
)

# Locate the Chrome / Chromium executable
if command -v google-chrome-stable &> /dev/null; then
    CHROME_EXEC="google-chrome-stable"
elif command -v google-chrome &> /dev/null; then
    CHROME_EXEC="google-chrome"
elif command -v chromium-browser &> /dev/null; then
    CHROME_EXEC="chromium-browser"
elif command -v chromium &> /dev/null; then
    CHROME_EXEC="chromium"
else
    echo "Error: no Chrome or Chromium executable found"
    exit 1
fi

echo "Starting Chrome: $CHROME_EXEC"
echo "Display: DISPLAY=$DISPLAY"
echo "Authority file: XAUTHORITY=$XAUTHORITY"
echo "User-data dir: $CHROME_USER_DATA_DIR"
echo "Args: ${CHROME_ARGS[@]} $@"

# Final check of the display connection
if ! xdpyinfo >/dev/null 2>&1; then
    echo "Warning: X server connection looks off at startup, trying to start Chrome anyway"
fi

# Helper to auto-maximize the Chrome window
maximize_chrome_window() {
    echo "Waiting for the Chrome window to appear, then auto-maximizing..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        # Wait one second
        sleep 1
        attempt=$((attempt + 1))

        # Try to maximize with wmctrl (Chromium window title/class is "Chromium")
        if wmctrl -l | grep -i "chrom" > /dev/null 2>&1; then
            echo "Found the browser window, maximizing..."
            wmctrl -r "Chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || \
            wmctrl -r "chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || \
            wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null

            # Also try xdotool as a fallback
            chrome_window_id=$(xdotool search --name "Chromium" 2>/dev/null | head -1)
            if [ -n "$chrome_window_id" ]; then
                echo "Maximizing window ID $chrome_window_id with xdotool"
                xdotool windowstate --add MAXIMIZED_VERT MAXIMIZED_HORZ "$chrome_window_id" 2>/dev/null
            fi

            echo "✅ Chrome window maximized"
            return 0
        fi

        echo "Waiting for the Chrome window... ($attempt/$max_attempts)"
    done

    echo "⚠️ Could not find the Chrome window to maximize in time"
    return 1
}

# Start Chrome
echo "Starting the Chrome browser..."

# Start Chrome in the background
"$CHROME_EXEC" "${CHROME_ARGS[@]}" "$@" &
CHROME_PID=$!

# Run the window-maximize helper in the background (don't block the main process)
maximize_chrome_window &

# Wait for the Chrome process
wait $CHROME_PID
