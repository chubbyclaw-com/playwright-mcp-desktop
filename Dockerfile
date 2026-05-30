ARG BASEIMAGE=ubuntu
ARG BASETAG=24.04

# VNC 相关参数
ARG ARG_VNC_COL_DEPTH=24
ARG ARG_VNC_DISPLAY=:1
ARG ARG_VNC_PORT=5901
ARG ARG_VNC_PW=password
ARG ARG_VNC_RESOLUTION=1280x720
ARG ARG_VNC_VIEW_ONLY=false

# noVNC 相关参数
ARG ARG_NOVNC_PORT=6080
ARG ARG_NOVNC_VERSION=1.7.0
ARG ARG_WEBSOCKIFY_VERSION=0.13.0

# 构建优化参数
ARG ARG_APT_NO_RECOMMENDS=1

###############
### stage_cache - 建立APT缓存层
###############
FROM ${BASEIMAGE}:${BASETAG} AS stage_cache

# 配置APT缓存
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# 更新APT缓存
RUN apt-get update

####################
### stage_essentials - 基础工具层
####################
FROM ${BASEIMAGE}:${BASETAG} AS stage_essentials

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 安装基础工具和依赖
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
### stage_system_setup - 系统配置层
###################
FROM stage_essentials AS stage_system_setup

# 创建必要的系统用户和目录
RUN \
    # 创建 messagebus 用户（D-Bus 需要），如果不存在的话
    id -u messagebus >/dev/null 2>&1 || \
        useradd --system --no-create-home --home-dir /nonexistent \
                --shell /usr/sbin/nologin --user-group messagebus && \
    # 创建必要目录
    mkdir -p /tmp/.X11-unix /run/dbus /run/user/0 /var/lib/dbus \
             /var/log/supervisor /etc/supervisor/conf.d && \
    # 设置目录权限
    chmod 1777 /tmp/.X11-unix && \
    chmod 700 /run/user/0 && \
    chmod 755 /run/dbus && \
    chown messagebus:messagebus /run/dbus /var/lib/dbus && \
    # 生成 D-Bus 机器 ID
    dbus-uuidgen > /etc/machine-id && \
    dbus-uuidgen > /var/lib/dbus/machine-id



#################
### stage_xserver - X服务器层
#################
FROM stage_system_setup AS stage_xserver

ENV \
    FEATURES_BUILD_SLIM_XSERVER="${ARG_APT_NO_RECOMMENDS:+1}" \
    NO_AT_BRIDGE=1

# 安装X服务器组件
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
### stage_xfce - XFCE桌面环境层
##############
FROM stage_xserver AS stage_xfce

ENV FEATURES_BUILD_SLIM_XFCE="${ARG_APT_NO_RECOMMENDS:+1}"

# 安装XFCE桌面环境和中文字体支持
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
        # 中文字体支持
        fonts-noto-cjk \
        fonts-noto-cjk-extra \
        fonts-wqy-zenhei \
        fonts-wqy-microhei \
        fonts-arphic-ukai \
        fonts-arphic-uming \
        # 彩色 emoji 字体（💡✅🚀 等 icon 渲染所需）
        fonts-noto-color-emoji \
        language-pack-zh-hans \
        language-pack-zh-hans-base

###################
### stage_xfce_config - XFCE配置层
###################
FROM stage_xfce AS stage_xfce_config

# 创建 XFCE 配置目录和基础配置
RUN \
    mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml \
             /root/.config/autostart \
             /root/.local/share \
             /root/.cache \
             /root/.vnc && \
    # 设置默认XFCE环境变量以避免错误
    echo 'export XFCE_DISABLE_GLIB_LOOP_CHECK=1' >> /etc/environment && \
    echo 'export XDG_CONFIG_HOME=/root/.config' >> /etc/environment && \
    echo 'export XDG_DATA_HOME=/root/.local/share' >> /etc/environment && \
    echo 'export XDG_CACHE_HOME=/root/.cache' >> /etc/environment && \
    echo 'export XDG_RUNTIME_DIR=/run/user/0' >> /etc/environment && \
    # 生成中文locale支持（但不设为默认）
    locale-gen zh_CN.UTF-8 && \
    dpkg-reconfigure --frontend=noninteractive locales

# 创建基本的XFCE4设置配置
COPY configs/xfce/xfce4-settings-manager.xml /root/.config/xfce4/xfconf/xfce-perchannel-xml/

# 创建XFCE4桌面配置
COPY configs/xfce/xfce4-desktop.xml /root/.config/xfce4/xfconf/xfce-perchannel-xml/

# 复制中文字体配置
COPY configs/fonts/99-chinese-fonts.conf /etc/fonts/conf.d/

###############
### stage_tools - 工具层
###############
FROM stage_xfce_config AS stage_tools

ENV \
    FEATURES_BUILD_SLIM_TOOLS="${ARG_APT_NO_RECOMMENDS:+1}" \
    FEATURES_SCREENSHOOTING=1 \
    FEATURES_THUMBNAILING=1

# 安装其他工具
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        mousepad \
        ristretto \
        xfce4-screenshooter \
        tumbler

#############
### stage_vnc - VNC服务器层  
#############
FROM stage_tools AS stage_vnc

# 安装VNC服务器和相关工具
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        tigervnc-common \
        tightvncserver \
        x11vnc \
        xvfb

# 设置VNC环境变量
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
### stage_vnc_config - VNC配置层
##################
FROM stage_vnc AS stage_vnc_config

# 创建 X11 认证文件
RUN touch /root/.Xauthority && chmod 600 /root/.Xauthority

# 创建VNC startup脚本
COPY configs/vnc/xstartup /root/.vnc/
RUN chmod +x /root/.vnc/xstartup

###############
### stage_novnc - noVNC网页客户端层
###############
FROM stage_vnc_config AS stage_novnc

ENV \
    FEATURES_BUILD_SLIM_NOVNC="${ARG_APT_NO_RECOMMENDS:+1}" \
    FEATURES_NOVNC=1 \
    NOVNC_HOME="/usr/libexec/novnc" \
    NOVNC_PORT="${ARG_NOVNC_PORT}"

# 安装python3-numpy并下载noVNC和websockify
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3-numpy && \
    # 设置版本变量
    NOVNC_VERSION="${ARG_NOVNC_VERSION:-1.7.0}" && \
    WEBSOCKIFY_VERSION="${ARG_WEBSOCKIFY_VERSION:-0.13.0}" && \
    echo "下载 noVNC v${NOVNC_VERSION} 和 websockify v${WEBSOCKIFY_VERSION}" && \
    # 创建noVNC目录
    mkdir -p "${NOVNC_HOME}"/utils/websockify && \
    # 下载noVNC
    wget --show-progress --progress=bar:force:noscroll \
        https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.tar.gz \
        -O /tmp/novnc.tar.gz && \
    # 下载websockify
    wget --show-progress --progress=bar:force:noscroll \
        https://github.com/novnc/websockify/archive/v${WEBSOCKIFY_VERSION}.tar.gz \
        -O /tmp/websockify.tar.gz && \
    # 解压noVNC
    tar xzf /tmp/novnc.tar.gz --strip 1 -C "${NOVNC_HOME}" && \
    # link to vnc.html
    ln -sv "${NOVNC_HOME}"/{vnc,index}.html && \
    # 解压websockify到utils目录
    tar xzf /tmp/websockify.tar.gz --strip 1 -C "${NOVNC_HOME}"/utils/websockify && \
    # 检查并设置权限
    if [ -f "${NOVNC_HOME}"/utils/novnc_proxy ]; then \
        chmod 755 "${NOVNC_HOME}"/utils/novnc_proxy; \
    fi && \
    # 清理临时文件
    rm -f /tmp/novnc.tar.gz /tmp/websockify.tar.gz

EXPOSE "${NOVNC_PORT}"

####################
### stage_browser - 浏览器层
####################
FROM stage_novnc AS stage_browser

# 安装 Chromium（原生 amd64/arm64 真·deb，经 xtradeb PPA 提供，规避 snap）
# Google Chrome 官方仅发布 amd64，arm64 宿主无法安装；改用 Chromium 原生包
# 软链 google-chrome-stable / google-chrome → chromium，保持既有脚本零改动
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
### stage_mcp_tools - MCP工具层
#####################
FROM stage_browser AS stage_mcp_tools

ARG ARG_PLAYWRIGHT_MCP_PORT=3000

# 安装Node.js 和 npm
RUN \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/cache/apt,target=/var/cache/apt \
    --mount=type=cache,from=stage_cache,sharing=locked,source=/var/lib/apt,target=/var/lib/apt \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

# 设置环境变量
ENV \
    PLAYWRIGHT_MCP_PORT="${ARG_PLAYWRIGHT_MCP_PORT}" \
    CHROME_USER_DATA_DIR="/opt/chrome-userdata" \
    FEATURES_PLAYWRIGHT_MCP=1

# 创建Chrome用户数据目录
RUN mkdir -p "${CHROME_USER_DATA_DIR}" && chmod 755 "${CHROME_USER_DATA_DIR}"

# 暴露MCP端口
EXPOSE "${PLAYWRIGHT_MCP_PORT}"

#####################
### stage_desktop_setup - 桌面配置层
#####################
FROM stage_mcp_tools AS stage_desktop_setup

# 创建桌面目录和快捷方式
RUN mkdir -p /root/Desktop

# 创建Chrome配置文件
COPY configs/browser/google-chrome.init /root/.google-chrome.init

# 复制桌面快捷方式文件
COPY configs/desktop/google-chrome.desktop /root/Desktop/
COPY configs/desktop/terminal.desktop /root/Desktop/
COPY scripts/start-chrome.sh /usr/local/bin/
RUN chmod +x /root/Desktop/google-chrome.desktop && \
    chmod +x /root/Desktop/terminal.desktop && \
    chmod +x /usr/local/bin/start-chrome.sh

#######################
### stage_supervisor_config - Supervisor配置层
#######################
FROM stage_desktop_setup AS stage_supervisor_config

# 复制 supervisor 配置文件
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

COPY supervisor/vnc.conf /etc/supervisor/conf.d/
COPY supervisor/novnc.conf /etc/supervisor/conf.d/
COPY supervisor/playwright-mcp.conf /etc/supervisor/conf.d/
COPY supervisor/browser-manager.conf /etc/supervisor/conf.d/

# 复制服务启动脚本

COPY scripts/start-vnc.sh /usr/local/bin/
COPY scripts/start-novnc.sh /usr/local/bin/
COPY scripts/start-playwright-mcp.sh /usr/local/bin/
COPY scripts/browser-manager.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start-vnc.sh /usr/local/bin/start-novnc.sh /usr/local/bin/start-playwright-mcp.sh /usr/local/bin/browser-manager.sh

###############
### FINAL STAGE - 最终阶段
###############
FROM stage_supervisor_config AS stage_final

# 设置环境变量
ENV \
    HOME="/root" \
    USER="root"

WORKDIR "${HOME}"

# 暴露端口
EXPOSE "${VNC_PORT}" "${NOVNC_PORT}" "${PLAYWRIGHT_MCP_PORT}"

# 直接使用 supervisord 作为入口点
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]