#!/bin/bash
set -e

# Create required directories
mkdir -p /tmp/.X11-unix /run/user/0 /root/.vnc /root/.config /root/.cache
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0

# Create the X11 authority file
touch /root/.Xauthority
chmod 600 /root/.Xauthority

# Environment variables
export DISPLAY=${DISPLAY:-:1}
VNC_GEOMETRY=${VNC_RESOLUTION:-1280x720}
VNC_DEPTH=${VNC_COL_DEPTH:-24}

# Set the VNC password
if [ -n "${VNC_PASSWORD}" ]; then
    echo "Setting up VNC password authentication..."
    echo "${VNC_PASSWORD}" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd

    cat > /root/.vnc/config << CONFIG_EOF
geometry=${VNC_GEOMETRY}
depth=${VNC_DEPTH}
securitytypes=vncauth
localhost=no
CONFIG_EOF
else
    echo "Warning: VNC_PASSWORD not set, using passwordless mode"
    cat > /root/.vnc/config << CONFIG_EOF
geometry=${VNC_GEOMETRY}
depth=${VNC_DEPTH}
securitytypes=none
localhost=no
CONFIG_EOF
fi

# Create the VNC startup script
cat > /root/.vnc/xstartup << 'XSTARTUP_EOF'
#!/bin/bash

# Reset session-management environment variables
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Base environment variables
export XDG_RUNTIME_DIR=/run/user/0
export XDG_SESSION_TYPE=x11
export XDG_SESSION_CLASS=user
export XDG_CURRENT_DESKTOP=XFCE
export XDG_CONFIG_HOME=/root/.config
export XDG_DATA_HOME=/root/.local/share
export XDG_CACHE_HOME=/root/.cache
export XAUTHORITY=/root/.Xauthority

# Create required directories
mkdir -p /root/.config/xfce4 /root/.local/share /root/.cache

# Start a minimal session bus (inspired by ubuntu-vnc-xfce-g3).
# Don't rely on the system D-Bus; only start a session-level bus.
echo "Starting session services..."
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
    echo "Session services started"
else
    echo "Note: dbus-launch unavailable, some desktop features may be limited"
fi

# Load X resources
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources

# XFCE-specific environment variable
export XFCE_DISABLE_GLIB_LOOP_CHECK=1

# Pre-start some XFCE services to avoid errors
echo "Pre-starting XFCE services..."

# Start xfce4-settings-daemon (avoids settings-server errors)
if command -v xfce4-settings-daemon >/dev/null 2>&1; then
    echo "Starting xfce4-settings-daemon..."
    xfce4-settings-daemon &
    SETTINGS_PID=$!

    # Wait for the settings daemon to start
    timeout=10
    count=0
    while [ $count -lt $timeout ]; do
        if ps -p $SETTINGS_PID > /dev/null 2>&1; then
            echo "xfce4-settings-daemon started (PID: $SETTINGS_PID)"
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    sleep 2
fi

# Start the window manager
if command -v xfwm4 >/dev/null 2>&1; then
    echo "Starting the XFCE window manager..."
    xfwm4 --daemon &
    WM_PID=$!

    # Wait for the window manager to start
    timeout=15
    count=0
    while [ $count -lt $timeout ]; do
        if ps -p $WM_PID > /dev/null 2>&1; then
            echo "XFCE window manager started (PID: $WM_PID)"
            break
        fi
        sleep 1
        count=$((count + 1))
    done

    # Extra wait for the window manager to fully initialize
    sleep 3
fi

# Final checks before starting the XFCE desktop
echo "Preparing to start the XFCE desktop..."

# Verify the key services are running
services_ready=true
if ! pgrep -f "xfce4-settings-daemon" > /dev/null 2>&1; then
    echo "Warning: xfce4-settings-daemon is not running"
    services_ready=false
fi

if ! pgrep -f "xfwm4" > /dev/null 2>&1; then
    echo "Warning: xfwm4 window manager is not running"
    services_ready=false
fi

if [ "$services_ready" = "true" ]; then
    echo "All key services ready, starting the XFCE desktop..."
else
    echo "Some services not ready, starting the XFCE desktop anyway..."
fi

# Start the XFCE desktop
exec startxfce4
XSTARTUP_EOF
chmod +x /root/.vnc/xstartup

# Create the XFCE4 configuration to avoid settings-server errors
echo "Creating the XFCE4 configuration..."
mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

# Basic XFCE4 settings-manager config
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-settings-manager.xml << 'XFCE_SETTINGS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-settings-manager" version="1.0">
  <property name="last" type="empty">
    <property name="window-width" type="int" value="640"/>
    <property name="window-height" type="int" value="500"/>
  </property>
</channel>
XFCE_SETTINGS_EOF

# XFCE4 desktop config
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'XFCE_DESKTOP_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value=""/>
        </property>
      </property>
    </property>
  </property>
</channel>
XFCE_DESKTOP_EOF

# Clean up old VNC processes and lock files
echo "Cleaning up old VNC sessions..."
vncserver -kill ${DISPLAY} 2>/dev/null || true
rm -rf /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true

# Set up X11 authentication
export XAUTHORITY=/root/.Xauthority
if command -v xxd >/dev/null 2>&1; then
    xauth add ${DISPLAY} . $(xxd -l 16 -p /dev/urandom)
else
    xauth add ${DISPLAY} . $(head -c 16 /dev/urandom | od -A n -t x8 | tr -d ' ')
fi

echo "VNC config: geometry=${VNC_GEOMETRY}, depth=${VNC_DEPTH}, display=${DISPLAY}"

# Add a desktop health check that runs after the VNC server starts
create_desktop_health_check() {
    cat > /tmp/check_desktop.sh << 'CHECK_EOF'
#!/bin/bash
# Desktop environment health-check script

check_desktop_health() {
    local max_attempts=30
    local attempt=0

    echo "Starting desktop health check..."

    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))

        # Check the X server responds
        if ! xset q >/dev/null 2>&1; then
            echo "Attempt $attempt/$max_attempts: X server not responding"
            sleep 2
            continue
        fi

        # Check the window manager is running
        if ! pgrep -f "xfwm4" >/dev/null 2>&1; then
            echo "Attempt $attempt/$max_attempts: window manager not running"
            sleep 2
            continue
        fi

        # Check the desktop is usable (try to read screen info)
        if xrandr >/dev/null 2>&1; then
            echo "Desktop health check passed! (attempt $attempt/$max_attempts)"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts: desktop not fully ready yet"
        sleep 2
    done

    echo "Warning: desktop health check timed out, but the VNC server keeps running"
    return 1
}

# Run the health check
check_desktop_health
CHECK_EOF
    chmod +x /tmp/check_desktop.sh
}

# Create the health-check script
create_desktop_health_check

echo "VNC config: geometry=${VNC_GEOMETRY}, depth=${VNC_DEPTH}, display=${DISPLAY}"

# Choose launch arguments based on whether a password is set
if [ -n "${VNC_PASSWORD}" ]; then
    echo "Starting the VNC server (password auth, listening on all interfaces)..."

    # Start the VNC server and run the desktop health check in the background
    {
        sleep 10  # wait for the VNC server to fully start
        /tmp/check_desktop.sh
    } &

    exec tigervncserver ${DISPLAY} -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -rfbauth /root/.vnc/passwd -localhost no -fg
else
    echo "Starting the VNC server (passwordless, listening on all interfaces)..."

    # Start the VNC server and run the desktop health check in the background
    {
        sleep 10  # wait for the VNC server to fully start
        /tmp/check_desktop.sh
    } &

    exec tigervncserver ${DISPLAY} -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -SecurityTypes None -localhost no -fg
fi
