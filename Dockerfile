ARG BASEIMAGE=ubuntu
ARG BASETAG=24.04

# VNC-related build args
ARG ARG_VNC_COL_DEPTH=24
ARG ARG_VNC_DISPLAY=:1
ARG ARG_VNC_PORT=5901
ARG ARG_VNC_PW=password
ARG ARG_VNC_RESOLUTION=1280x720
ARG ARG_VNC_VIEW_ONLY=false

# noVNC-related build args
ARG ARG_NOVNC_PORT=6080
ARG ARG_NOVNC_VERSION=1.7.0
ARG ARG_WEBSOCKIFY_VERSION=0.13.0

# Build-optimization args
ARG ARG_APT_NO_RECOMMENDS=1

###############
### stage_cache - build the APT cache layer
###############
FROM ${BASEIMAGE}:${BASETAG} AS stage_cache

# Configure the APT cache
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Refresh the APT cache
RUN apt-get update

####################
### stage_essentials - base tooling layer
####################
FROM ${BASEIMAGE}:${BASETAG} AS stage_essentials

# Environment
ENV DEBIAN_FRONTEND=noninteractive

# Install base tools and dependencies
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        less \
        curl \
        dbus \
        dbus-x11 \
        gettext-base \
        git \
        gnupg \
        jq \
        lsb-release \
        nano \
        net-tools \
        psmisc \
        python3 \
        python3-pip \
        software-properties-common \
        sudo \
        supervisor \
        wget \
        xxd

###################
### stage_system_setup - system configuration layer
###################
FROM stage_essentials AS stage_system_setup

# Create the required system users and directories
RUN \
    # Create the messagebus user (needed by D-Bus) if it does not exist
    id -u messagebus >/dev/null 2>&1 || \
        useradd --system --no-create-home --home-dir /nonexistent \
                --shell /usr/sbin/nologin --user-group messagebus && \
    # Create required directories
    mkdir -p /tmp/.X11-unix /run/dbus /run/user/0 /var/lib/dbus \
             /var/log/supervisor /etc/supervisor/conf.d && \
    # Set directory permissions
    chmod 1777 /tmp/.X11-unix && \
    chmod 700 /run/user/0 && \
    chmod 755 /run/dbus && \
    chown messagebus:messagebus /run/dbus /var/lib/dbus && \
    # Generate the D-Bus machine ID
    dbus-uuidgen > /etc/machine-id && \
    dbus-uuidgen > /var/lib/dbus/machine-id



#################
### stage_xserver - X server layer
#################
FROM stage_system_setup AS stage_xserver

ENV \
    FEATURES_BUILD_SLIM_XSERVER="${ARG_APT_NO_RECOMMENDS:+1}" \
    NO_AT_BRIDGE=1

# Install X server components
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        dbus-x11 \
        xauth \
        xinit \
        x11-xserver-utils \
        xdg-utils \
        libxshmfence1 \
        libxcvt0 \
        libgbm1 \
        wmctrl \
        xdotool

##############
### stage_xfce - XFCE desktop layer
##############
FROM stage_xserver AS stage_xfce

ENV FEATURES_BUILD_SLIM_XFCE="${ARG_APT_NO_RECOMMENDS:+1}"

# Install the XFCE desktop and CJK font support
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-terminal \
        xfce4-goodies \
        elementary-xfce-icon-theme \
        fonts-dejavu \
        fontconfig \
        # CJK font support
        fonts-noto-cjk \
        fonts-noto-cjk-extra \
        fonts-wqy-zenhei \
        fonts-wqy-microhei \
        fonts-arphic-ukai \
        fonts-arphic-uming \
        # Color emoji font (needed to render 💡✅🚀 and similar icons)
        fonts-noto-color-emoji \
        language-pack-zh-hans \
        language-pack-zh-hans-base

###################
### stage_xfce_config - XFCE configuration layer
###################
FROM stage_xfce AS stage_xfce_config

# Create the XFCE config directories and base config
RUN \
    mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml \
             /root/.config/autostart \
             /root/.local/share \
             /root/.cache \
             /root/.vnc && \
    # Set default XFCE environment variables to avoid errors
    echo 'export XFCE_DISABLE_GLIB_LOOP_CHECK=1' >> /etc/environment && \
    echo 'export XDG_CONFIG_HOME=/root/.config' >> /etc/environment && \
    echo 'export XDG_DATA_HOME=/root/.local/share' >> /etc/environment && \
    echo 'export XDG_CACHE_HOME=/root/.cache' >> /etc/environment && \
    echo 'export XDG_RUNTIME_DIR=/run/user/0' >> /etc/environment && \
    # Generate Chinese locale support (but don't make it the default)
    locale-gen zh_CN.UTF-8 && \
    dpkg-reconfigure --frontend=noninteractive locales

# Copy the XFCE4 settings-manager config
COPY configs/xfce/xfce4-settings-manager.xml /root/.config/xfce4/xfconf/xfce-perchannel-xml/

# Copy the XFCE4 desktop config
COPY configs/xfce/xfce4-desktop.xml /root/.config/xfce4/xfconf/xfce-perchannel-xml/

# Copy the CJK fontconfig snippet
COPY configs/fonts/99-chinese-fonts.conf /etc/fonts/conf.d/

###############
### stage_tools - tooling layer
###############
FROM stage_xfce_config AS stage_tools

ENV \
    FEATURES_BUILD_SLIM_TOOLS="${ARG_APT_NO_RECOMMENDS:+1}" \
    FEATURES_SCREENSHOOTING=1 \
    FEATURES_THUMBNAILING=1

# Install additional tools
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        mousepad \
        ristretto \
        xfce4-screenshooter \
        tumbler

#############
### stage_vnc - VNC server layer
#############
FROM stage_tools AS stage_vnc

# Install the VNC server and related tools
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        tigervnc-common \
        tightvncserver \
        x11vnc \
        xvfb

# VNC environment variables
ENV \
    DISPLAY="${ARG_VNC_DISPLAY}" \
    FEATURES_VNC=1 \
    VNC_COL_DEPTH="${ARG_VNC_COL_DEPTH}" \
    VNC_PORT="${ARG_VNC_PORT}" \
    VNC_PW="${ARG_VNC_PW}" \
    VNC_PASSWORD="${ARG_VNC_PW}" \
    VNC_RESOLUTION="${ARG_VNC_RESOLUTION}" \
    VNC_VIEW_ONLY="${ARG_VNC_VIEW_ONLY}"

EXPOSE "${VNC_PORT}"

##################
### stage_vnc_config - VNC configuration layer
##################
FROM stage_vnc AS stage_vnc_config

# Create the X11 authority file
RUN touch /root/.Xauthority && chmod 600 /root/.Xauthority

# Install the VNC startup script
COPY configs/vnc/xstartup /root/.vnc/
RUN chmod +x /root/.vnc/xstartup

###############
### stage_novnc - noVNC web client layer
###############
FROM stage_vnc_config AS stage_novnc

ENV \
    FEATURES_BUILD_SLIM_NOVNC="${ARG_APT_NO_RECOMMENDS:+1}" \
    FEATURES_NOVNC=1 \
    NOVNC_HOME="/usr/libexec/novnc" \
    NOVNC_PORT="${ARG_NOVNC_PORT}"

# Install python3-numpy and download noVNC + websockify
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3-numpy && \
    # Resolve version variables
    NOVNC_VERSION="${ARG_NOVNC_VERSION:-1.7.0}" && \
    WEBSOCKIFY_VERSION="${ARG_WEBSOCKIFY_VERSION:-0.13.0}" && \
    echo "Downloading noVNC v${NOVNC_VERSION} and websockify v${WEBSOCKIFY_VERSION}" && \
    # Create the noVNC directory
    mkdir -p "${NOVNC_HOME}"/utils/websockify && \
    # Download noVNC
    wget --show-progress --progress=bar:force:noscroll \
        https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.tar.gz \
        -O /tmp/novnc.tar.gz && \
    # Download websockify
    wget --show-progress --progress=bar:force:noscroll \
        https://github.com/novnc/websockify/archive/v${WEBSOCKIFY_VERSION}.tar.gz \
        -O /tmp/websockify.tar.gz && \
    # Extract noVNC
    tar xzf /tmp/novnc.tar.gz --strip 1 -C "${NOVNC_HOME}" && \
    # Link vnc.html to index.html
    ln -sv "${NOVNC_HOME}"/{vnc,index}.html && \
    # Extract websockify into the utils directory
    tar xzf /tmp/websockify.tar.gz --strip 1 -C "${NOVNC_HOME}"/utils/websockify && \
    # Check and set permissions
    if [ -f "${NOVNC_HOME}"/utils/novnc_proxy ]; then \
        chmod 755 "${NOVNC_HOME}"/utils/novnc_proxy; \
    fi && \
    # Clean up temp files
    rm -f /tmp/novnc.tar.gz /tmp/websockify.tar.gz

EXPOSE "${NOVNC_PORT}"

####################
### stage_browser - browser layer
####################
FROM stage_novnc AS stage_browser

# Install Chromium (native amd64/arm64 .deb via the xtradeb PPA, avoiding snap).
# Google Chrome only ships amd64 officially, so it can't be installed on arm64
# hosts; we use the native Chromium package instead.
# Symlink google-chrome-stable / google-chrome -> chromium so existing scripts
# keep working unchanged.
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    wget -qO- "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5301FA4FD93244FBC6F6149982BB6851C64F6880" \
        | gpg --dearmor -o /usr/share/keyrings/xtradeb.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/xtradeb.gpg] https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu noble main" \
        > /etc/apt/sources.list.d/xtradeb.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y chromium \
    && ln -sf /usr/bin/chromium /usr/bin/google-chrome-stable \
    && ln -sf /usr/bin/chromium /usr/bin/google-chrome

#####################
### stage_mcp_tools - MCP tooling layer
#####################
FROM stage_browser AS stage_mcp_tools

ARG ARG_PLAYWRIGHT_MCP_PORT=3000

# Install Node.js and npm
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

# Environment
ENV \
    PLAYWRIGHT_MCP_PORT="${ARG_PLAYWRIGHT_MCP_PORT}" \
    CHROME_USER_DATA_DIR="/opt/chrome-userdata" \
    FEATURES_PLAYWRIGHT_MCP=1

# Create the Chrome user-data directory
RUN mkdir -p "${CHROME_USER_DATA_DIR}" && chmod 755 "${CHROME_USER_DATA_DIR}"

# Expose the MCP port
EXPOSE "${PLAYWRIGHT_MCP_PORT}"

#####################
### stage_desktop_setup - desktop configuration layer
#####################
FROM stage_mcp_tools AS stage_desktop_setup

# Create the desktop directory and shortcuts
RUN mkdir -p /root/Desktop

# Copy the Chrome init file
COPY configs/browser/google-chrome.init /root/.google-chrome.init

# Copy the desktop shortcut files
COPY configs/desktop/google-chrome.desktop /root/Desktop/
COPY configs/desktop/terminal.desktop /root/Desktop/
COPY scripts/start-chrome.sh /usr/local/bin/
RUN chmod +x /root/Desktop/google-chrome.desktop && \
    chmod +x /root/Desktop/terminal.desktop && \
    chmod +x /usr/local/bin/start-chrome.sh

#######################
### stage_supervisor_config - Supervisor configuration layer
#######################
FROM stage_desktop_setup AS stage_supervisor_config

# Copy the supervisor config files
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

COPY supervisor/vnc.conf /etc/supervisor/conf.d/
COPY supervisor/novnc.conf /etc/supervisor/conf.d/
COPY supervisor/playwright-mcp.conf /etc/supervisor/conf.d/
COPY supervisor/browser-manager.conf /etc/supervisor/conf.d/

# Copy the service startup scripts
COPY scripts/start-vnc.sh /usr/local/bin/
COPY scripts/start-novnc.sh /usr/local/bin/
COPY scripts/start-playwright-mcp.sh /usr/local/bin/
COPY scripts/browser-manager.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start-vnc.sh /usr/local/bin/start-novnc.sh /usr/local/bin/start-playwright-mcp.sh /usr/local/bin/browser-manager.sh

###############
### FINAL STAGE
###############
FROM stage_supervisor_config AS stage_final

# Environment
ENV \
    HOME="/root" \
    USER="root"

WORKDIR "${HOME}"

# Expose all service ports
EXPOSE "${VNC_PORT}" "${NOVNC_PORT}" "${PLAYWRIGHT_MCP_PORT}"

# Use supervisord as the entrypoint
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
