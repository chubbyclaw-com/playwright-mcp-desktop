#!/bin/bash
set -e

# 创建必要目录
mkdir -p /tmp/.X11-unix /run/user/0 /root/.vnc /root/.config /root/.cache
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0

# 创建 X11 认证文件
touch /root/.Xauthority
chmod 600 /root/.Xauthority

# 设置环境变量
export DISPLAY=${DISPLAY:-:1}
VNC_GEOMETRY=${VNC_RESOLUTION:-1280x720}
VNC_DEPTH=${VNC_COL_DEPTH:-24}

# 设置VNC密码
if [ -n "${VNC_PASSWORD}" ]; then
    echo "设置VNC密码认证..."
    echo "${VNC_PASSWORD}" | vncpasswd -f > /root/.vnc/passwd
    chmod 600 /root/.vnc/passwd
    
    cat > /root/.vnc/config << CONFIG_EOF
geometry=${VNC_GEOMETRY}
depth=${VNC_DEPTH}
securitytypes=vncauth
localhost=no
CONFIG_EOF
else
    echo "警告: 未设置VNC_PASSWORD，使用无密码模式"
    cat > /root/.vnc/config << CONFIG_EOF
geometry=${VNC_GEOMETRY}
depth=${VNC_DEPTH}
securitytypes=none
localhost=no
CONFIG_EOF
fi

# 创建VNC startup脚本
cat > /root/.vnc/xstartup << 'XSTARTUP_EOF'
#!/bin/bash

# 重置会话管理相关环境变量
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# 设置基础环境变量
export XDG_RUNTIME_DIR=/run/user/0
export XDG_SESSION_TYPE=x11
export XDG_SESSION_CLASS=user
export XDG_CURRENT_DESKTOP=XFCE
export XDG_CONFIG_HOME=/root/.config
export XDG_DATA_HOME=/root/.local/share
export XDG_CACHE_HOME=/root/.cache
export XAUTHORITY=/root/.Xauthority

# 创建必要的目录
mkdir -p /root/.config/xfce4 /root/.local/share /root/.cache

# 启动简化的会话服务（参考ubuntu-vnc-xfce-g3）
# 不依赖系统D-Bus服务，仅启动会话级别的服务
echo "启动会话服务..."
if command -v dbus-launch >/dev/null 2>&1; then
    eval $(dbus-launch --sh-syntax)
    echo "会话服务已启动"
else
    echo "注意: dbus-launch不可用，某些桌面功能可能受限"
fi

# 加载X资源
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources

# 设置XFCE特定环境变量
export XFCE_DISABLE_GLIB_LOOP_CHECK=1

# 预先启动一些XFCE服务来避免错误
echo "预启动XFCE服务..."

# 启动xfce4-settings-daemon (避免设置服务器错误)
if command -v xfce4-settings-daemon >/dev/null 2>&1; then
    echo "启动xfce4-settings-daemon..."
    xfce4-settings-daemon &
    SETTINGS_PID=$!
    
    # 等待设置守护进程启动
    timeout=10
    count=0
    while [ $count -lt $timeout ]; do
        if ps -p $SETTINGS_PID > /dev/null 2>&1; then
            echo "xfce4-settings-daemon已启动 (PID: $SETTINGS_PID)"
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    sleep 2
fi

# 启动窗口管理器
if command -v xfwm4 >/dev/null 2>&1; then
    echo "启动XFCE窗口管理器..."
    xfwm4 --daemon &
    WM_PID=$!
    
    # 等待窗口管理器启动
    timeout=15
    count=0
    while [ $count -lt $timeout ]; do
        if ps -p $WM_PID > /dev/null 2>&1; then
            echo "XFCE窗口管理器已启动 (PID: $WM_PID)"
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # 额外等待窗口管理器完全初始化
    sleep 3
fi

# 启动XFCE桌面环境前进行最终检查
echo "准备启动XFCE桌面环境..."

# 验证关键服务是否运行
services_ready=true
if ! pgrep -f "xfce4-settings-daemon" > /dev/null 2>&1; then
    echo "警告: xfce4-settings-daemon未运行"
    services_ready=false
fi

if ! pgrep -f "xfwm4" > /dev/null 2>&1; then
    echo "警告: xfwm4窗口管理器未运行"
    services_ready=false
fi

if [ "$services_ready" = "true" ]; then
    echo "所有关键服务已就绪，启动XFCE桌面环境..."
else
    echo "部分服务未就绪，但继续启动XFCE桌面环境..."
fi

# 启动XFCE桌面环境
exec startxfce4
XSTARTUP_EOF
chmod +x /root/.vnc/xstartup

# 创建XFCE4配置以避免设置服务器错误
echo "创建XFCE4配置..."
mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml

# 创建基本的XFCE4设置配置
cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-settings-manager.xml << 'XFCE_SETTINGS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-settings-manager" version="1.0">
  <property name="last" type="empty">
    <property name="window-width" type="int" value="640"/>
    <property name="window-height" type="int" value="500"/>
  </property>
</channel>
XFCE_SETTINGS_EOF

# 创建XFCE4桌面配置
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

# 清理旧的VNC进程和锁文件
echo "清理旧的VNC会话..."
vncserver -kill ${DISPLAY} 2>/dev/null || true
rm -rf /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true

# 设置 X11 认证
export XAUTHORITY=/root/.Xauthority
if command -v xxd >/dev/null 2>&1; then
    xauth add ${DISPLAY} . $(xxd -l 16 -p /dev/urandom)
else
    xauth add ${DISPLAY} . $(head -c 16 /dev/urandom | od -A n -t x8 | tr -d ' ')
fi

echo "VNC配置: 几何=${VNC_GEOMETRY}, 深度=${VNC_DEPTH}, 显示=${DISPLAY}"

# 添加VNC服务器启动后的桌面环境检查功能
create_desktop_health_check() {
    cat > /tmp/check_desktop.sh << 'CHECK_EOF'
#!/bin/bash
# 桌面环境健康检查脚本

check_desktop_health() {
    local max_attempts=30
    local attempt=0
    
    echo "开始桌面环境健康检查..."
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        # 检查X服务器是否响应
        if ! xset q >/dev/null 2>&1; then
            echo "尝试 $attempt/$max_attempts: X服务器未响应"
            sleep 2
            continue
        fi
        
        # 检查窗口管理器是否运行
        if ! pgrep -f "xfwm4" >/dev/null 2>&1; then
            echo "尝试 $attempt/$max_attempts: 窗口管理器未运行"
            sleep 2
            continue
        fi
        
        # 检查桌面是否可用（尝试获取屏幕信息）
        if xrandr >/dev/null 2>&1; then
            echo "桌面环境健康检查通过！(尝试 $attempt/$max_attempts)"
            return 0
        fi
        
        echo "尝试 $attempt/$max_attempts: 桌面环境尚未完全就绪"
        sleep 2
    done
    
    echo "警告: 桌面环境健康检查超时，但VNC服务器将继续运行"
    return 1
}

# 运行健康检查
check_desktop_health
CHECK_EOF
    chmod +x /tmp/check_desktop.sh
}

# 创建健康检查脚本
create_desktop_health_check

echo "VNC配置: 几何=${VNC_GEOMETRY}, 深度=${VNC_DEPTH}, 显示=${DISPLAY}"

# 根据是否设置密码选择启动参数
if [ -n "${VNC_PASSWORD}" ]; then
    echo "启动VNC服务器（密码认证模式，监听所有地址）..."
    
    # 启动VNC服务器并在后台运行桌面健康检查
    {
        sleep 10  # 等待VNC服务器完全启动
        /tmp/check_desktop.sh
    } &
    
    exec tigervncserver ${DISPLAY} -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -rfbauth /root/.vnc/passwd -localhost no -fg
else
    echo "启动VNC服务器（无密码模式，监听所有地址）..."
    
    # 启动VNC服务器并在后台运行桌面健康检查
    {
        sleep 10  # 等待VNC服务器完全启动
        /tmp/check_desktop.sh
    } &
    
    exec tigervncserver ${DISPLAY} -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -SecurityTypes None -localhost no -fg
fi
